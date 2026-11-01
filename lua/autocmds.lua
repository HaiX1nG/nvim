require "nvchad.autocmds"

-- 启动 treesitter 高亮
--
-- nvim-treesitter 的 main 分支（适配 Neovim 0.12）不再自动开启高亮，
-- 必须在 FileType 事件里显式调用 vim.treesitter.start()。
-- 对没装 parser 的文件类型会抛错，pcall 吞掉即可 —— 它们继续走传统 syntax 高亮。
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("TSSyntaxStart", { clear = true }),
  callback = function()
    pcall(vim.treesitter.start)
  end,
})

-- LSP 客户端挂载/卸载时刷新状态栏
--
-- 原因：状态栏是惰性求值的（%!v:lua...），只有在下一个重绘触发点才会重新计算。
-- LSP 是在打开文件后才异步 attach 的，如果之后没有光标移动等事件触发重绘，
-- 状态栏里的服务器名会停留在旧值（刚打开文件时显示空白，过一会儿才变过来）。
-- 这里显式 redrawstatus，保证 attach 完成那一刻就能看到正确的服务器名。
vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
  callback = function()
    vim.cmd.redrawstatus()
  end,
})

-- 新环境首次启动后自动安装 treesitter parser
-- （NvChad v2.5 的 TSInstallAll 是空操作：spec.opts 是 function，传给 install() 的是 nil）
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(function()
      local installed = require("nvim-treesitter.config").get_installed "parsers"
      local need = {
        "rust",
        "go",
        "lua",
        "vim",
        "vimdoc",
        "luadoc",
        "json",
        "yaml",
        "html",
        "css",
        "javascript",
        "typescript",
        "toml",
        "bash",
        "python",
        "markdown",
        -- render-markdown.nvim 要用 markdown_inline 处理行内样式
        "markdown_inline",
      }
      local to_install = {}
      for _, lang in ipairs(need) do
        if not vim.tbl_contains(installed, lang) then
          to_install[#to_install + 1] = lang
        end
      end
      if #to_install > 0 then
        vim.notify("TSInstall: " .. table.concat(to_install, " "), vim.log.levels.INFO)
        vim.cmd("TSInstall! " .. table.concat(to_install, " "))
      end
    end, 2000)
  end,
  once = true,
})
