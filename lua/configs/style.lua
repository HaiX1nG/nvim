-- 代码高亮的粗体 / 斜体
--
-- 为什么需要单独一个文件：
--   1. base46 的 tokyonight 主题只定义颜色，不定义 bold/italic。
--      现在能看到的粗体关键字是 Neovim 自带 dev_theme 给的，
--      属于"意外继承"—— 主题缓存一覆盖就没了。
--   2. 终端侧本来就具备渲染能力：kitty 的 bold_font/italic_font 都是 auto，
--      而 JetBrainsMono Nerd Font Mono 这个字体家族带齐了
--      Regular / Bold / Italic / Bold Italic 四个字重（fc-list 实测）。
--      缺的只是 nvim 侧告诉终端"这里用粗体/斜体"。
--
-- 作用范围：treesitter 的 @xxx 捕获组 + 传统 syntax 组，两边都设。
-- 这样装了 parser 的语言走 @xxx，没装 parser 的文件类型走传统组，观感一致。

local M = {}

--- 粗体：强调「结构」—— 关键字、类型、常量、函数
---@type string[]
M.bold = {
  -- 传统 syntax 组放在前面：@xxx 往往是指向它们的链接，
  -- 先把目标组加粗，后面的 @xxx 就能直接继承，不用拆链接。
  "Keyword",
  "Conditional",
  "Repeat",
  "Statement",
  "Label",
  "Exception",
  "StorageClass",
  "Define",
  "Include",
  "PreProc",
  "Type",
  "Typedef",
  "Structure",
  "Constant",
  "Boolean",
  "Number",
  "Float",
  "Function",
  "Special",
  "Tag",
  "Macro",
  "Debug",

  -- treesitter 捕获组
  "@keyword",
  "@keyword.function",
  "@keyword.return",
  "@keyword.repeat",
  "@keyword.operator",
  "@keyword.conditional",
  "@keyword.conditional.ternary",
  "@keyword.exception",
  "@keyword.storage",
  "@keyword.directive",
  "@keyword.directive.define",
  "@type",
  "@type.definition",
  "@constructor",
  "@constant",
  "@constant.builtin",
  "@constant.macro",
  "@function",
  "@function.builtin",
  "@function.macro",
  "@function.call",
  "@function.method",
  "@function.method.call",
  "@module",
  "@property",
  "@attribute",
  "@definition",
  "@field",
  -- 数字：14 种语言都用它（bash/c/css/go/json/lua/python/rust/toml/vim/yaml…）
  -- 漏了它数字就是「有颜色但没粗体」，是跨语言最明显的一处缺口
  "@number",
  "@number.float",
  -- 字段 / 成员访问：Rust 的 cfg.count、Python 的 obj.attr、Go 的 s.field
  "@variable.member",
  "@variable.member.key",
  -- HTML / CSS 的标签名
  "@tag",
}

--- 斜体：弱化「修饰」—— 注释、参数、内建类型
---@type string[]
M.italic = {
  "Comment",
  "SpecialComment",

  "@comment",
  "@comment.documentation",
  "@comment.note",
  "@comment.warning",
  "@comment.danger",
  "@variable.parameter",
  "@variable.parameter.builtin",
  -- 内建变量：Rust 的 self、Python 的 self、JS 的 this
  "@variable.builtin",
  "@parameter",
  "@type.builtin",
  "@markup.italic",
  "@markup.link",
  "@markup.link.url",
  "@markup.underline",
  "@diff.delta",
  -- HTML / CSS 的属性名
  "@tag.attribute",
}

--- 给一个高亮组叠加 bold/italic
---
--- 两个坑：
---   1. nvim_set_hl 是「整体替换」语义，不是「合并」。
---      只写 { bold = true } 会把该组原有的 fg/bg 一起清掉。
---      所以先取解析后的实际属性，带着颜色一起写回。
---   2. 链接组（例如 @variable.parameter -> Identifier）如果把属性加到
---      链接目标上，会污染所有指向同一目标的组（Identifier 到处都是）。
---      所以这里选择「实体化」：复制目标的颜色，在链接组自己身上加属性。
---
---@param group string
---@param attr "bold"|"italic"
local function apply_attr(group, attr)
  -- 组不存在就别造：凭空造一个 @xxx 会顶掉 @xxx 的逐级回退
  -- （@function.call.lua -> @function.call -> @function -> Function）
  if vim.fn.hlexists(group) == 0 then
    return
  end

  local resolved = vim.api.nvim_get_hl(0, { name = group, link = false })

  -- 已经有这个属性就别动，保住原来的链接关系
  if resolved[attr] then
    return
  end

  local def = vim.deepcopy(resolved)
  def.link = nil
  def[attr] = true

  vim.api.nvim_set_hl(0, group, def)
end

--- 应用全部粗体/斜体规则
function M.apply()
  for _, group in ipairs(M.bold) do
    apply_attr(group, "bold")
  end

  for _, group in ipairs(M.italic) do
    apply_attr(group, "italic")
  end
end

--- 当前生效的高亮组统计
---@return {bold: integer, italic: integer, total: integer}
function M.stats()
  local bold, italic, total = 0, 0, 0
  for _, group in ipairs(M.bold) do
    local d = vim.api.nvim_get_hl(0, { name = group, link = false })
    if d.bold then
      bold = bold + 1
      total = total + 1
    end
  end
  for _, group in ipairs(M.italic) do
    local d = vim.api.nvim_get_hl(0, { name = group, link = false })
    if d.italic then
      italic = italic + 1
      total = total + 1
    end
  end
  return { bold = bold, italic = italic, total = total }
end

--- 解析一个捕获名最终落到哪个高亮组、什么属性
---
--- treesitter 的回退链是 @foo.bar -> @foo -> 传统组，
--- 逐级往上找第一个真正带属性的定义。
---@param capture string
---@return string|nil group
---@return table|nil def
local function resolve(capture)
  local name = capture:match "^@" and capture or ("@" .. capture)
  while true do
    if vim.fn.hlexists(name) == 1 then
      local d = vim.api.nvim_get_hl(0, { name = name, link = false })
      if d.bold or d.italic or d.fg then
        local l = vim.api.nvim_get_hl(0, { name = name })
        return name, d, l.link
      end
    end
    local parent = name:match "^(.*)%.[^.]+$"
    if not parent then
      return nil, nil, nil
    end
    name = parent
  end
end

--- :StyleCheck —— 一键自检
---
-- 用来回答「到底生效没有」：
--   1. 当前会话是否加载了这份配置（配置路径 + 文件 mtime）
--   2. 粗体/斜体到底套上了多少个组
--   3. 光标所在 token 的【最终生效属性】（这才是屏幕上看到的东西）
function M.check()
  local lines = {}

  local function add(fmt, ...)
    lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  end

  local function fmt_attrs(d)
    local attrs = {}
    if d.bold then
      attrs[#attrs + 1] = "粗体"
    end
    if d.italic then
      attrs[#attrs + 1] = "斜体"
    end
    if d.fg then
      attrs[#attrs + 1] = string.format("fg=#%06x", d.fg)
    end
    return #attrs > 0 and table.concat(attrs, " ") or "无属性"
  end

  add("配置文件     : %s", vim.fn.stdpath "config")
  local style_file = vim.fn.stdpath "config" .. "/lua/configs/style.lua"
  if vim.fn.filereadable(style_file) == 1 then
    add("style.lua    : mtime=%s", vim.fn.strftime("%Y-%m-%d %H:%M:%S", vim.fn.getftime(style_file)))
  else
    add("style.lua    : 【不存在】%s", style_file)
  end

  local st = M.stats()
  add(
    "粗体/斜体    : 粗体 %d 组 / 斜体 %d 组（规则表共 %d 条）",
    st.bold,
    st.italic,
    #M.bold + #M.italic
  )

  -- 找真正带代码高亮的缓冲区：当前缓冲区优先，否则挑最近一个开了 treesitter 的
  local cur = vim.api.nvim_get_current_buf()
  local target = cur
  if not vim.b[cur].ts_highlight then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.b[b].ts_highlight then
        target = b
      end
    end
  end

  local name = vim.api.nvim_buf_get_name(target)
  add ""
  add(
    "检查缓冲区   : %s (ft=%s%s)",
    name ~= "" and vim.fn.fnamemodify(name, ":t") or "<无名>",
    vim.bo[target].filetype,
    target == cur and "" or "，自动从其它缓冲区挑的"
  )
  add(
    "treesitter   : %s",
    vim.b[target].ts_highlight and "已启用" or "未启用（该缓冲区没有代码高亮）"
  )

  -- 彩虹括号
  local rb_loaded = pcall(require, "rainbow-delimiters")
  local rb_count = 0
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(target, -1, 0, -1, { details = true })) do
    local d = m[4] or {}
    if d.hl_group and d.hl_group:match "^RainbowDelimiter" then
      rb_count = rb_count + 1
    end
  end
  add(
    "彩虹括号     : %s",
    (not rb_loaded) and "插件未加载"
      or (
        rb_count > 0 and ("已启用，该缓冲区 %d 个括号已上色"):format(rb_count)
        or "已加载，但该缓冲区还没有括号被着色"
      )
  )

  -- 光标处 token 的最终属性
  -- 注意：get_captures_at_cursor 收的是【窗口号】，不是 buffer 号
  local win = vim.fn.bufwinid(target)
  if vim.b[target].ts_highlight and win > 0 then
    local ok, caps = pcall(vim.treesitter.get_captures_at_cursor, win)
    if ok and caps and #caps > 0 then
      add ""
      add "光标处 token 的最终属性："
      for _, cap in ipairs(caps) do
        local cname = type(cap) == "table" and (cap.capture or cap[1]) or tostring(cap)
        local grp, def, link = resolve(tostring(cname))
        if grp then
          add(
            "  %-26s -> %-16s %s%s",
            "@" .. tostring(cname),
            grp,
            fmt_attrs(def),
            link and ("  (链接→" .. link .. ")") or ""
          )
        else
          add("  %-26s -> 未匹配到高亮组", "@" .. tostring(cname))
        end
      end
    else
      add ""
      add "光标处 token : 拿不到（该位置没有可解析的捕获）"
    end
  elseif win <= 0 then
    add ""
    add "光标处 token : 拿不到（该缓冲区没显示在任何窗口里）"
  end

  -- 列出所有开了 treesitter 的缓冲区，方便定位
  local code_bufs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.b[b].ts_highlight then
      code_bufs[#code_bufs + 1] = string.format("%d:%s", b, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t"))
    end
  end
  if #code_bufs > 0 then
    add ""
    add("开了高亮的缓冲区 : %s", table.concat(code_bufs, "  "))
  end

  local msg = table.concat(lines, "\n")
  vim.notify(msg, vim.log.levels.INFO, { title = "StyleCheck" })
  print("\n" .. msg .. "\n")
end

return M
