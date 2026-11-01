-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = "tokyonight",

  hl_override = {
    Comment = { italic = true },
    ["@comment"] = { italic = true },
  },
}

M.nvdash = { load_on_startup = true }

M.ui = {
  tabufline = {
    lazyload = true,
  },
  statusline = {
    theme = "default",
    -- 调整模块顺序，"%=" 代表左右对齐的分隔点
    order = { "mode", "file", "git", "diagnostics", "%=", "lsp", "%=", "cursor", "cwd" },

    -- 微调特定模块的内容
    modules = {
      -- 例如，将光标位置显示改为 "行:列" 格式
      cursor = " %l:%c ",

      -- 覆盖 NvChad 默认的 lsp 模块
      --
      -- 上游实现（~/.local/share/nvim/lazy/ui/lua/nvchad/stl/utils.lua）：
      --   return (vim.o.columns > 100 and "  LSP ~ " .. client.name .. " ") or "  LSP "
      -- 问题 1：终端宽度 <= 100 列时只显示笼统的 "LSP"，服务器名被丢弃。
      --         （kitty 窗口实测 94 列，所以永远命中不到带名字的分支）
      -- 问题 2：return 写在循环体内，多个 LSP 同时挂载时只显示第一个服务器的名字。
      --
      -- 这里改为：只要当前 buffer 挂了 LSP，就列出全部服务器名（去重、逗号分隔），
      -- 与终端列宽无关；同时顺带修掉问题 2。
      lsp = function()
        local utils = require "nvchad.stl.utils"
        local bufnr = utils.stbufnr()

        local names, seen = {}, {}
        for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
          if not seen[client.name] then
            seen[client.name] = true
            names[#names + 1] = client.name
          end
        end

        if #names == 0 then
          return ""
        end

        return "%#St_Lsp#  LSP ~ " .. table.concat(names, ", ") .. " "
      end,
    },
  },
}

return M
