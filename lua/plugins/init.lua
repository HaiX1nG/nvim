-- render-markdown 在本机是「手动克隆到 manual 目录」的那一份（原因见下面的注释）。
-- 换台机器（比如 macOS）上没这个目录，就得让 lazy 正常从 GitHub 拉，
-- 所以这里只在目录真的存在时才写死 dir。
local markdown_local = vim.fn.stdpath "data" .. "/manual/render-markdown.nvim"

local render_markdown = {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = "markdown",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  opts = {},
}

if vim.uv.fs_stat(markdown_local) then
  render_markdown.dir = markdown_local
end

return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    event = "User VeryLazy",
    opts = require "configs.conform",
  },

  -- 覆盖 NvChad 默认的 cmp 配置（Tab 接受补全、方向键翻页）
  {
    "hrsh7th/nvim-cmp",
    opts = function()
      return require "configs.cmp"
    end,
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    -- event = "User FilePost",
    lazy = false,
    config = function()
      require "configs.lspconfig"
    end,
  },

  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

  -- {
  -- 	"nvim-treesitter/nvim-treesitter",
  -- 	opts = {
  -- 		ensure_installed = {
  -- 			"vim", "lua", "vimdoc",
  --      "html", "css"
  -- 		},
  -- 	},
  -- },

  -- 接管 nvim-treesitter 的加载顺序（覆盖 NvChad 默认的 spec）
  --
  -- 为什么必须接管：
  --   NvChad 的 spec 用 opts 函数返回 nvchad.configs.treesitter，
  --   而那个模块在被 require 时会 dofile base46 的 syntax/treesitter 缓存。
  --   nvim-treesitter 是 event = { "BufReadPost", "BufNewFile" } 懒加载的，
  --   所以这次缓存加载发生在启动之后；而 nvim_set_hl 是「整体替换」语义，
  --   缓存里只有 fg/bg 没有 bold/italic —— 启动时套好的粗体/斜体会被整个冲掉。
  --
  -- lazy.nvim 的 loader 里 opts() 是在 config() 之前才被调用的
  -- （lua/lazy/core/loader.lua:361 M.config → Plugin.values(plugin, "opts")），
  --   所以自己写 config：让 opts() 先把缓存加载掉，再套粗体/斜体，顺序就是对的。
  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    -- 新分支（main）只有这几个命令：TSInstall / TSUpdate / TSUninstall / TSLog
    -- 旧的 TSBufEnable / TSModuleInfo / TSInstallAll 已经不存在了
    cmd = { "TSInstall", "TSUpdate", "TSUninstall" },
    build = ":TSUpdate",
    opts = function()
      return require "nvchad.configs.treesitter"
    end,
    config = function(_, opts)
      require("nvim-treesitter").setup(opts)
      -- 高亮由 autocmds.lua 里的 FileType 自动命令负责开启
      -- 粗体/斜体必须是最后一步
      require("configs.style").apply()
    end,
  },

  -- Markdown 富文本渲染
  --
  -- 让 Markdown 在编辑器里接近"渲染后的样子"：
  --   标题   -> 放大加粗 + 图标
  --   表格   -> 自动对齐、画框线
  --   代码块 -> 加边框
  --   列表   -> 换成圆点/勾选符号
  --   引用   -> 左侧竖线
  -- 依赖 nvim-treesitter 的 markdown / markdown_inline 解析器（site/parser 里已有）。
  -- 随时可用 :RenderMarkdown toggle 开关渲染。
  --
  -- 为什么可能用 dir 而不是让 lazy 自己 clone：
  --   本机 git 走 SSH，但 /etc/ssh 下有个配置文件权限损坏（owner 是 nobody），
  --   ssh 读配置就报 "Bad owner or permissions"，lazy 的 git clone 全部失败；
  --   而它失败后会反复重试，每次启动都刷屏。
  --   插件已经用 ssh -F /dev/null 直连 22 端口手动克隆到 manual 目录，
  --   这里只让 lazy 负责加载。
  -- 为什么不能写死 dir：
  --   别的机器（比如 macOS）上没有这个目录，写死就是「插件不存在」。
  --   所以 manual 目录存在才用它，否则退回正常的仓库拉取（见文件开头）。
  render_markdown,

  -- 彩虹括号
  --
  -- Neovim 0.12 没有内置彩虹括号，NvChad / base46 也不提供，必须外挂插件。
  -- 选 HiPhish/rainbow-delimiters.nvim 的原因：
  --   p00f/nvim-ts-rainbow 和 HiPhish/nvim-ts-rainbow2 都是 nvim-treesitter 的
  --   「模块」，而 nvim-treesitter 已经废弃了 module 系统，两者都已归档；
  --   rainbow-delimiters.nvim 是独立插件，只用 Neovim 内置的 treesitter API。
  {
    "HiPhish/rainbow-delimiters.nvim",
    -- 必须启动期加载（不能按 BufReadPost 懒加载）：
    --   插件靠 FileType 自动命令把缓冲区挂上去，而 FileType 是在
    --   BufReadPost **之后** 才触发的（实测：BufReadPre -> BufReadPost
    --   -> FileType -> BufEnter）。如果按 BufReadPost 加载，
    --   插件的 FileType 自动命令会错过第一个打开的文件，
    --   结果就是「括号一直是普通颜色」，而且看起来像插件没生效。
    lazy = false,
    opts = {
      -- 七种颜色的轮转顺序（插件默认：红 黄 蓝 橙 绿 紫 青）
      highlight = require("configs.rainbow").groups,
    },
    config = function(_, opts)
      -- setup 在 rainbow-delimiters.setup 这个模块里，
      -- 主模块 rainbow-delimiters 只导出 enable/disable/toggle，没有 setup
      require("rainbow-delimiters.setup").setup(opts)
      -- 插件自带的是通用默认色，这里换成 tokyonight 调色板
      require("configs.rainbow").apply()
      require("configs.rainbow").watch()
    end,
  },

  -- 自动安装 Mason 包（LSP / 格式化 / Linter）
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    event = "VimEnter",
    dependencies = { "mason-org/mason.nvim" },
    config = function()
      require("mason-tool-installer").setup {
        ensure_installed = {
          -- LSP 服务器
          "lua-language-server",
          "html-lsp",
          "css-lsp",
          "typescript-language-server",
          "json-lsp",
          "yaml-language-server",
          "pyright",
          "bash-language-server",
          "rust-analyzer",

          -- 格式化工具
          "stylua",
          "prettier",
          "shfmt",

          -- Linter
          "eslint_d",
          "ruff",
        },
        auto_update = true,
        run_on_start = true,
      }
    end,
  },
}
