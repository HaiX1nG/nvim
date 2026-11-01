require("nvchad.configs.lspconfig").defaults()

local servers = { "html", "cssls", "pyright", "ts_ls", "gopls", "rust_analyzer", "bashls", "jsonls", "yamlls" }

-- rust-analyzer：让它把「不是 cargo 项目」的目录也当项目处理
--
-- 背景：散装 .rs 文件（没有 Cargo.toml 的目录）会让 rust-analyzer 直接报
--   ERROR failed to find any projects in [AbsPathBuf("...")]
--   然后 FetchWorkspaceError，补全永远返回 0 条 —— 表现就是"跟 txt 一样没提示"。
-- 统一做法是把练习目录做成 cargo 包（见 rust-course/01-基础/我的作业/Cargo.toml），
-- 这里不再强行 root_dir，避免抢走正常项目的根。
vim.lsp.config("rust_analyzer", {
  settings = {
    ["rust-analyzer"] = {
      -- 类型提示：let x = 5 旁边显示 : i32
      -- 默认是 off，Neovim 也不会自己开，要在 LspAttach 里 enable（见下）
      inlayHints = {
        enable = true,
        typeHints = { enable = true },
        parameterHints = { enable = true },
        chainingHints = { enable = true },
        closureReturnTypeHints = { enable = "always" },
        bindingModeHints = { enable = false },
        lifetimeElisionHints = { enable = "never" },
      },
      -- 检查所有 target（含 src/bin 下的练习），否则只查 main
      check = { allTargets = true },
      -- 保存后立刻重新分析，不用等默认的延迟
      cargo = { allFeatures = true },
      procMacro = { enable = true },
    },
  },
  on_attach = function(client, bufnr)
    -- 按缓冲区开类型提示。rust-analyzer 支持，别的 server 未必
    if not client:supports_method("textDocument/inlayHint") then
      return
    end

    -- 为什么要「关掉再开」而不是直接 enable：
    --   rust-analyzer 刚 attach 时 workspace 还没 build 完，
    --   此时 Neovim 发的 textDocument/inlayHint 拿到空数组后就缓存了，
    --   此后不再重发 —— 表现是"打开文件半天没有类型提示，
    --   手敲一个字符突然全冒出来"（打字才触发新请求）。
    --   实测：同一次 enable(true) 完全无效；enable(false) 后紧接
    --   enable(true) 就能立刻拉到结果。所以这里走一遍关闭再打开，
    --   强制在 workspace 就绪后重新请求一次。
    local function refresh()
      if not (vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr)) then
        return
      end
      vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
          vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end
      end, 100)
    end

    vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    -- 首次打开：等 rust-analyzer 把 crate 图建好再刷一遍
    vim.defer_fn(refresh, 2000)
  end,
})

vim.lsp.enable(servers)

-- 自动导包：保存 .rs 时，把缺失的 use 补上
--
-- 为什么不用 vim.lsp.buf.code_action{ apply = true }：
--   rust-analyzer 对每个缺失符号返回 2 个 quickfix（Import / Qualify），
--   Neovim 只在「只剩 1 个候选」时才自动应用，否则弹窗等你手选。
-- 为什么是 BufWritePost，而不是 BufWritePre / DiagnosticChanged：
--   实测本机 rust-analyzer 对「未保存」的改动不会刷新 cannot-find 诊断——
--   新增 BTreeSet 后等 10s，诊断里依然没有它；写盘触发重新分析后才出现。
--   所以 BufWritePre 里只能拿到上一轮的旧诊断（永远慢一拍），
--   DiagnosticChanged 回调里更是稳定拿到 0 个动作。
-- 为什么直接调 apply_text_edits，而不是 apply_workspace_edit：
--   rust-analyzer 的 edit 带 textDocument.version，而写盘后 buffer 版本已经更高，
--   apply_workspace_edit 会打印 "Buffer newer than edits" 并把 edit 丢掉。
--   apply_text_edits 是同一套落地逻辑但不做版本比较，正是我们要的。
-- 流程：保存 → 等诊断刷新（最多 8 轮 × 700ms）→ 同步请求 codeAction
--       → resolve 拿 edit → 去重 → 应用 → 写回磁盘。
--
-- 已知边界：
--   1. 文件存在语法错误时，rust-analyzer 不产出 cannot find 诊断，此时不会导包。
--   2. 手动删掉一个仍在使用的 use，保存时会被自动加回来。
--   3. 保存后会额外写一次盘（把补上的 use 落到磁盘）。

-- 重入保护：写回磁盘会再次触发本回调，vim.wait 期间也可能被其它事件打断
local pending = {}

-- 从 action title 取导入路径，如 "Import `std::collections::HashMap`" → "std::collections::HashMap"
local function import_path(title)
  return title:match "^Import `(.+)`$"
end

-- 缓冲区里是否已经有这条 use（避免重复插入叠成两行）
local function already_imported(bufnr, path)
  if not path then
    return true -- 解析不出路径就别动
  end
  -- 同时匹配 `use a::b::c;` 与合并形式 `use a::b::{c, d};`
  local leaf = vim.pesc(path:match "([^:]+)$")
  local esc = vim.pesc(path)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:match "^%s*use%s" and (line:match(esc) or line:match("[%{%s]" .. leaf .. "%s*[,}]")) then
      return true
    end
  end
  return false
end

-- 返回本次实际应用的 action 数量
local function rust_auto_import(bufnr)
  local client = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" })[1]
  if not client then
    return 0
  end

  local applied = 0
  local seen = {}

  for _, d in ipairs(vim.diagnostic.get(bufnr)) do
    -- 只处理"找不到符号"类诊断；用 message 去重，避免同一符号重复收集
    if d.message:match "cannot find" then
      local key = d.message:gsub("%s+", " ")
      if not seen[key] then
        seen[key] = true

        local resp = client:request_sync("textDocument/codeAction", {
          textDocument = { uri = vim.uri_from_bufnr(bufnr) },
          range = {
            start = { line = d.lnum, character = d.col },
            ["end"] = { line = d.end_lnum, character = d.end_col },
          },
          context = { only = { "quickfix" }, diagnostics = {}, triggerKind = 1 },
        }, 4000, bufnr)

        if resp and not resp.err and resp.result then
          for _, a in ipairs(resp.result) do
            if a.kind == "quickfix" and a.title:match "^Import " then
              local action = a
              -- rust-analyzer 的 import action 首次返回不带 edit，需要 resolve
              if not action.edit then
                local resolved = client:request_sync("codeAction/resolve", action, 4000, bufnr)
                if resolved and not resolved.err and resolved.result then
                  action = resolved.result
                end
              end

              if action.edit and not already_imported(bufnr, import_path(action.title)) then
                for _, ch in ipairs(action.edit.documentChanges or {}) do
                  if ch.textDocument and ch.edits then
                    vim.lsp.util.apply_text_edits(
                      ch.edits,
                      vim.uri_to_bufnr(ch.textDocument.uri),
                      client.offset_encoding
                    )
                    applied = applied + 1
                  end
                end
              end
              break
            end
          end
        end
      end
    end
  end

  return applied
end

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.rs",
  callback = function(args)
    local bufnr = args.buf
    if pending[bufnr] or vim.bo[bufnr].filetype ~= "rust" then
      return
    end

    pending[bufnr] = true
    local attempt = 0

    local function tick()
      attempt = attempt + 1

      local ok, applied = pcall(rust_auto_import, bufnr)

      if not ok then
        vim.notify("rust auto-import 失败: " .. tostring(applied), vim.log.levels.WARN)
        pending[bufnr] = false
        return
      end

      if applied > 0 then
        -- 补上的 use 只在 buffer 里，写回让磁盘同步（noautocmd 避免再次触发本回调）
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd "silent noautocmd write"
        end)
        pending[bufnr] = false
        return
      end

      if attempt >= 8 then
        pending[bufnr] = false
        return
      end

      vim.defer_fn(tick, 700)
    end

    -- 保存后 rust-analyzer 需要重新分析，先等一轮再查
    vim.defer_fn(tick, 700)
  end,
})

--------------------------------------------------------------------------
-- 一、诊断：插入模式里也刷新
--------------------------------------------------------------------------
-- NvChad 的 diagnostic_config()（ui/lua/nvchad/lsp/init.lua）只设了
-- virtual_text / signs / underline / float，没设 update_in_insert。
-- Neovim 默认 update_in_insert = false：插入模式里收到的诊断只记账、
-- 不往界面画，等退出插入模式才一次性刷出来 —— 看起来就像"不报错"。
-- 这行把它打开，边打字边有红线。
vim.diagnostic.config { update_in_insert = true }

--------------------------------------------------------------------------
-- 二、实时导包：按标识符问 codeAction，不等诊断、不等保存
--------------------------------------------------------------------------
-- 为什么不能沿用上面那段「扫诊断找 cannot find」的逻辑：
--   实测这台机器（Neovim 0.12 + rust-analyzer 1.99），把一个缺 import
--   的符号打进一个**未保存**的缓冲区后：
--     · textDocument/diagnostic 一直返回 { kind = "full", items = {} }，
--       等 60 秒也不来；存盘后 120ms 内就有了。
--     · 同一时刻 hover / completion 在脏缓冲区里完全正常，
--       对着标识符 range 问 textDocument/codeAction 也能拿到
--       `Import \`std::collections::HashSet\``。
--   结论：r-a 把「有未保存改动」的文件当 transient，只给语法错误，
--   语义诊断（cannot find type）要等它变成磁盘上的实体文件。
--   所以凡是「靠诊断」的自动导包，天生被保存卡住 —— 换条路走。
--
-- 现在的做法：停下来的时候，拿光标所在词 + 本行首字母大写的词
-- （类型 / 模块名最常见）各问一次 codeAction，命中 `Import ...` 就
-- resolve + 落地。脏缓冲区照样能用，全程不落盘。
-- 每种语言的导包动作长得不一样，实测（不是猜）：
--
--   rust  : 对着标识符 range 问 quickfix → `Import \`std::...\``（需 resolve）
--   ts/js : 整文件问 source.addMissingImports → "Add all missing imports"（需 resolve）
--           只加不删，安全
--   go    : 整文件问 source.organizeImports → "Organize Imports"（自带 edit）
--           注意：gopls 这个动作会**顺带删掉没用到的 import**，跟 GoLand 保存时
--           optimize imports 是一样的行为，不想要的把 go 这条删掉即可
--   python: pyright 没有任何能补 import 的 code action，只能靠补全项自带的
--           additionalTextEdits —— nvim-cmp 的 core.lua:410 已经会应用，
--           所以 Python 这边不需要额外代码，写 import 时接受补全即可
--
-- mode = "quickfix"：拿光标附近/本行大写的词逐个问（rust 的路子，脏缓冲区也能用）
-- mode = "source"  ：整文件问一次某个 source action（TS/Go 的路子）
--                    必须配合 diag：非 Rust 的服务器在未保存时**是有实时诊断的**，
--                    不靠它兜一层，每停顿一次都会白跑一次整文件请求
local IMPORT_STRATEGY = {
  rust = { mode = "quickfix" },
  typescript = { mode = "source", only = { "source.addMissingImports" }, diag = "[Cc]annot find name" },
  typescriptreact = {
    mode = "source",
    only = { "source.addMissingImports" },
    diag = "[Cc]annot find name",
  },
  javascript = { mode = "source", only = { "source.addMissingImports" }, diag = "[Cc]annot find name" },
  javascriptreact = {
    mode = "source",
    only = { "source.addMissingImports" },
    diag = "[Cc]annot find name",
  },
  go = { mode = "source", only = { "source.organizeImports" }, diag = "^undefined: " },
}

-- 定义在下面「三、安静落盘」里；导包成功后要把改动顺手落盘，
-- 否则缓冲区里多了个 use、磁盘上还没有，诊断会停在旧的那一版
local schedule_save

-- 光标所在（或紧邻左侧）的标识符，返回 0 基的 LSP range
-- 打字时通常停在词尾（HashSet| ），所以右边不是词就往左收一格
local function word_range_at_cursor()
  local pos = vim.api.nvim_win_get_cursor(0)
  local lnum, col = pos[1] - 1, pos[2]
  local line = vim.api.nvim_get_current_line()

  local function is_word(i)
    return i >= 1 and i <= #line and line:sub(i, i):match "[%w_]"
  end

  local i = col + 1
  if not is_word(i) then
    i = col
    if not is_word(i) then
      return nil
    end
  end

  local s, e = i, i
  while is_word(s - 1) do
    s = s - 1
  end
  while is_word(e + 1) do
    e = e + 1
  end

  local word = line:sub(s, e)
  if #word < 2 or word:match "^%d" then
    return nil
  end
  return { word = word, lnum = lnum, from = s - 1, to = e }
end

-- 候选词：光标处的词优先，再补本行首字母大写的标识符
local function import_candidates()
  local line = vim.api.nvim_get_current_line()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local out, seen = {}, {}

  local function push(word, from, to)
    if not seen[word] then
      seen[word] = true
      out[#out + 1] = { lnum = lnum, from = from, to = to }
    end
  end

  local w = word_range_at_cursor()
  if w then
    push(w.word, w.from, w.to)
  end

  local init = 1
  while true do
    local s, e = line:find("[%u][%w_]*", init)
    if not s then
      break
    end
    push(line:sub(s, e), s - 1, e)
    init = e + 1
  end

  -- 一行两三个就够，问太多既慢又容易导错
  return vim.list_slice(out, 1, math.min(#out, 4))
end

-- 把一个 codeAction 的 edit 落地；返回 true 表示缓冲区内容确实变了
--
-- 两种情况都要认：
--   edit.documentChanges（r-a / ts_ls 常用）
--   edit.changes（gopls 的 organizeImports 常用，key 是 uri）
local function apply_code_action(client, bufnr, action)
  if not action or not action.edit then
    return false
  end

  -- 只有能从 title 里解析出路径的（rust 的 `Import \`a::b\``）才做重复检查；
  -- 整文件动作（"Add all missing imports"/"Organize Imports"）解析不出，
  -- 靠下面的"内容变了没"来判断
  local path = import_path(action.title)
  if path and already_imported(bufnr, path) then
    return false
  end

  local jobs = {}
  for _, ch in ipairs(action.edit.documentChanges or {}) do
    if ch.textDocument and ch.edits and #ch.edits > 0 then
      jobs[#jobs + 1] = { buf = vim.uri_to_bufnr(ch.textDocument.uri), edits = ch.edits }
    end
  end
  for uri, edits in pairs(action.edit.changes or {}) do
    if edits and #edits > 0 then
      jobs[#jobs + 1] = { buf = vim.uri_to_bufnr(uri), edits = edits }
    end
  end
  if #jobs == 0 then
    return false
  end

  local before = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  for _, j in ipairs(jobs) do
    vim.lsp.util.apply_text_edits(j.edits, j.buf, client.offset_encoding)
  end
  local after = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  return before ~= after
end

-- live_import 定义在下面（按 filetype 分派），这里先声明：
-- commit_action 补完一轮后要递归调它，不声明就会引用到全局 nil
local live_import

-- 落一个动作 + 收尾（写盘让诊断跟上，必要时再来一轮）
local function commit_action(bufnr, client, act, on_fail, depth)
  if apply_code_action(client, bufnr, act) then
    -- 补上了：把这一版写回去，好让诊断跟上（否则红线还停在补课前）
    if schedule_save then
      schedule_save(bufnr, 60)
    end
    -- 同一行可能还缺第二个 import，行号已经变了，重算一轮
    if depth and depth < 3 then
      vim.defer_fn(function()
        if
          vim.api.nvim_buf_is_valid(bufnr)
          and vim.api.nvim_get_current_buf() == bufnr
          and IMPORT_STRATEGY[vim.bo[bufnr].filetype]
        then
          live_import(bufnr, depth + 1)
        end
      end, 150)
    end
    return true
  end
  if on_fail then
    on_fail()
  end
  return false
end

-- 策略一（rust）：拿光标附近/本行大写的词逐个问 quickfix
--
-- depth 是"补完一轮再来一轮"的次数：落地一次会在上方插一行 `use`，
-- 后面候选词记的行号就整体下移一位，所以不接着用旧 range，而是重算一轮。
local function quickfix_import(client, bufnr, depth)
  local cands = import_candidates()
  local idx = 0

  local function next_candidate()
    idx = idx + 1
    local c = cands[idx]
    if not c then
      return
    end
    if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_get_current_buf() ~= bufnr then
      return
    end

    client:request("textDocument/codeAction", {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      range = {
        start = { line = c.lnum, character = c.from },
        ["end"] = { line = c.lnum, character = c.to },
      },
      context = { only = { "quickfix" }, diagnostics = {}, triggerKind = 1 },
    }, function(err, result)
      if err or not result then
        return vim.schedule(next_candidate)
      end

      for _, a in ipairs(result) do
        if a.kind == "quickfix" and a.title:match "^Import " then
          local function finish(act)
            commit_action(bufnr, client, act, next_candidate, depth)
          end

          if a.edit then
            return vim.schedule(function()
              finish(a)
            end)
          end

          -- r-a 的 import action 首次返回不带 edit，要 resolve
          return client:request("codeAction/resolve", a, function(err2, resolved)
            vim.schedule(function()
              finish((not err2 and resolved) or nil)
            end)
          end, bufnr)
        end
      end

      vim.schedule(next_candidate)
    end, bufnr)
  end

  next_candidate()
end

-- 策略二（ts/js/go）：整文件问一次 source action
--
-- 只在出现对应的 error 诊断时才动手：这几个 server 在未保存的缓冲区上
-- 是有实时诊断的，拿它当闸门，免得每停顿一次都白跑整文件请求。
-- 对 go 来说 organizeImports 会连"没用到的 import"一起删掉，属正常行为。
local function source_import(client, bufnr, strategy)
  if strategy.diag then
    local hit = false
    for _, d in ipairs(vim.diagnostic.get(bufnr)) do
      if d.severity == vim.diagnostic.severity.ERROR and d.message:match(strategy.diag) then
        hit = true
        break
      end
    end
    if not hit then
      return
    end
  end

  local doc = {
    start = { line = 0, character = 0 },
    ["end"] = { line = math.max(vim.api.nvim_buf_line_count(bufnr) - 1, 0), character = 0 },
  }

  client:request("textDocument/codeAction", {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    range = doc,
    context = { only = strategy.only, diagnostics = {}, triggerKind = 1 },
  }, function(err, result)
    if err or not result or #result == 0 then
      return
    end

    local a = result[1]
    if a.edit then
      return vim.schedule(function()
        commit_action(bufnr, client, a)
      end)
    end

    -- 有的 server 首次不给 edit（ts_ls 的 addMissingImports 就是），要 resolve
    client:request("codeAction/resolve", a, function(err2, resolved)
      local act = (not err2 and resolved) or nil
      if act and act.edit then
        vim.schedule(function()
          commit_action(bufnr, client, act)
        end)
      end
    end, bufnr)
  end, bufnr)
end

-- 按 filetype 分派
live_import = function(bufnr, depth)
  depth = depth or 1
  local strategy = IMPORT_STRATEGY[vim.bo[bufnr].filetype]
  if not strategy then
    return
  end

  local client = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" })[1]
  if not client then
    return
  end

  if strategy.mode == "quickfix" then
    quickfix_import(client, bufnr, depth)
  else
    source_import(client, bufnr, strategy)
  end
end

local live_group = vim.api.nvim_create_augroup("MyLiveImport", { clear = true })
local live_timer = vim.uv.new_timer()

local function schedule_live_import()
  local bufnr = vim.api.nvim_get_current_buf()
  if not IMPORT_STRATEGY[vim.bo[bufnr].filetype] then
    return
  end

  live_timer:stop()
  live_timer:start(
    300,
    0,
    vim.schedule_wrap(function()
      local b = vim.api.nvim_get_current_buf()
      if not vim.api.nvim_buf_is_valid(b) or not IMPORT_STRATEGY[vim.bo[b].filetype] then
        return
      end
      -- 补全菜单开着的时候别动缓冲区，不然会跟选中项打架
      local ok, cmp = pcall(require, "cmp")
      if ok and cmp.visible() then
        return
      end
      live_import(b)
    end)
  )
end

vim.api.nvim_create_autocmd({ "InsertLeave", "CursorHold", "CursorHoldI" }, {
  group = live_group,
  callback = schedule_live_import,
})

--------------------------------------------------------------------------
-- 三、安静落盘：让 rust-analyzer 看得见"当前这版代码"
--------------------------------------------------------------------------
-- 上面查到根因了：r-a 对未保存的缓冲区不出语义诊断。
-- 所以「写的时候就报错」在 Rust 里只有一条路 —— 让磁盘跟得上。
-- 落盘 → r-a 重新分析 → 大约 100~300ms 后红线就到。
--
-- 节奏按 IDEA 的 autosave 语义来，而不是定时心跳：
--   · 退出插入模式后 500ms（比自动导包晚一拍，让 use 先补上再一起写）
--   · 离开缓冲区 / 切窗口 / 失焦：立刻（对应 IDEA 的 frame deactivation）
--   · 其它改动只在待机 5s 后兜底，不跟着每次停顿写盘
-- 区别在于：打字中途（还没 ESC）不会有新红线。这是与 IDEA 唯一
-- 补不上的差距 —— r-a 不分析内存文档，Neovim 这层绕不过去。
--
-- 代价与开关：
--   1. 文件 mtime 会在你 ESC / 切窗口时变，不是每次停顿都变；
--   2. r-a 的 checkOnSave 随之触发（增量很快，但占 CPU）；
--      介意就在 rust_analyzer 的 settings 里加 check = { on_save = false }，
--      关掉的是 cargo check，不影响原生诊断；
--   3. 想临时关掉：`:lua vim.g.autosave_enabled = false`（不用重启）。
--   4. 已知冲突：`:e!` / `:q!` 会先触发 BufLeave —— 想在丢弃改动前先关
--      autosave，或者用 `:config`… 简单点：先 `:lua vim.g.autosave_enabled = false`。
local AUTOSAVE = {
  enabled = true,
  idle_ms = 5000, -- 待机兜底
  leave_ms = 500, -- 退出插入模式后（等自动导包落地）
  min_gap_ms = 2000, -- 同一缓冲区两次写盘的最小间隔
  filetypes = {
    rust = true,
    go = true,
    python = true,
    typescript = true,
    typescriptreact = true,
    javascript = true,
    javascriptreact = true,
  },
}

local save_group = vim.api.nvim_create_augroup("MyAutoSave", { clear = true })
local save_pending = {} -- bufnr -> timer
local last_save = {} -- bufnr -> uv.now()

-- schedule_save 在「二、实时导包」那边已经前向声明过了，这里只赋值不重新 local，
-- 否则会遮蔽掉那边的名字，导包后的落盘就永远调不到。

-- 真正写盘；force 用于「离开缓冲区」这类低频但重要的时机，跳过最小间隔限制
local function do_save(bufnr, force)
  if not AUTOSAVE.enabled or vim.g.autosave_enabled == false then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if not vim.bo[bufnr].modified or vim.bo[bufnr].buftype ~= "" then
    return
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or not AUTOSAVE.filetypes[vim.bo[bufnr].filetype] then
    return
  end
  -- 只读文件、没权限的目录（比如挂在只读盘上的练习）直接跳过
  if not vim.bo[bufnr].modifiable or vim.fn.filewritable(name) == 0 then
    return
  end

  local now = vim.uv.now()
  local gap = now - (last_save[bufnr] or 0)
  if not force and gap < AUTOSAVE.min_gap_ms then
    -- 还没到最小间隔：排个队再来，别把这次改动丢了
    -- （自动导包落地的 use 常常紧跟在一次写盘之后）
    schedule_save(bufnr, AUTOSAVE.min_gap_ms - gap + 50)
    return
  end
  last_save[bufnr] = now

  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd "silent! write"
  end)
end

-- 每个缓冲区各排各的：切来切去时不会互相把待办顶掉
schedule_save = function(bufnr, delay, force)
  if not AUTOSAVE.enabled or vim.g.autosave_enabled == false then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local old = save_pending[bufnr]
  if old then
    old:stop()
    old:close()
  end

  local timer = vim.uv.new_timer()
  save_pending[bufnr] = timer
  timer:start(
    delay or AUTOSAVE.idle_ms,
    0,
    vim.schedule_wrap(function()
      if save_pending[bufnr] == timer then
        save_pending[bufnr] = nil
      end
      timer:stop()
      timer:close()
      do_save(bufnr, force)
    end)
  )
end

-- 缓冲区没了就把待办收掉，别留着写一个已经不存在的 buffer
vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, {
  group = save_group,
  callback = function(args)
    local t = save_pending[args.buf]
    if t then
      t:stop()
      t:close()
      save_pending[args.buf] = nil
    end
    last_save[args.buf] = nil
  end,
})

-- 待机兜底：停止改动 5s 后写一次
-- CursorHold 一并挂上：有些改动（宏、:g、别的插件走 API 改文本）不一定
-- 触发 TextChanged，但停在原地一会儿总会有 CursorHold
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "CursorHold", "CursorHoldI" }, {
  group = save_group,
  callback = function(args)
    schedule_save(args.buf, AUTOSAVE.idle_ms)
  end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
  group = save_group,
  callback = function(args)
    schedule_save(args.buf, AUTOSAVE.leave_ms)
  end,
})

-- IDEA 的 deactivation 语义：离开这个缓冲区 / 切窗口 / 失焦就落盘
-- force = true：这类事件低频，跳过最小间隔直接写
vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "FocusLost" }, {
  group = save_group,
  callback = function(args)
    schedule_save(args.buf, 0, true)
  end,
})

-- read :h vim.lsp.config for changing options of lsp servers
