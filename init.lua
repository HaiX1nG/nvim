vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    branch = "v2.5",
    import = "nvchad.plugins",
  },

  { import = "plugins" },
}, lazy_config)

-- load theme
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

-- 重新加载语法/treesitter 缓存
--
-- 为什么必须放在 defaults 之后：
--   base46 的 defaults 缓存里有 `vim.o.bg='dark'`。
--   给 'background' 赋值会触发 Neovim 重新初始化高亮（init_highlight），
--   把所有高亮组重置回 Neovim 内置的 dev_theme 默认值。
--   而 syntax / treesitter 两个缓存是在 lazy.setup() 阶段
--   （nvchad.configs.treesitter 里）就已经加载好了，
--   于是在这里被那一次重置整个清空 —— 结果就是：
--     Function 变成 #8cf8f7（dev_theme 的颜色）而不是 tokyonight 的 #2ac3de，
--     所有 @xxx 捕获组也退回链接到传统组。
--   base46 自己的 load_all_highlights()（切换主题时走的那条路径）里，
--   integrations 的顺序是 defaults -> ... -> syntax -> treesitter，
--   也就是 syntax/treesitter 在 defaults 之后 —— 这里跟它保持一致。
dofile(vim.g.base46_cache .. "syntax")
dofile(vim.g.base46_cache .. "treesitter")

require "options"
require "autocmds"

-- 编辑区半透明（见 lua/configs/transparency.lua）
require "configs.transparency"

vim.schedule(function()
  require "mappings"
end)
