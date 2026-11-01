-- 个人定制：Tab 接受补全、方向键翻页（保留 NvChad 默认的补全来源/片段/菜单配置）
local cmp = require "cmp"

local options = {
  completion = { completeopt = "menu,menuone" },

  snippet = {
    expand = function(args)
      require("luasnip").lsp_expand(args.body)
    end,
  },

  mapping = {
    ["<Up>"] = cmp.mapping.select_prev_item(),
    ["<Down>"] = cmp.mapping.select_next_item(),
    ["<Tab>"] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.confirm { select = true }
      elseif require("luasnip").expand_or_jumpable() then
        require("luasnip").expand_or_jump()
      else
        fallback()
      end
    end, { "i", "s" }),

    ["<S-Tab>"] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_prev_item()
      elseif require("luasnip").jumpable(-1) then
        require("luasnip").jump(-1)
      else
        fallback()
      end
    end, { "i", "s" }),
  },

  sources = {
    { name = "nvim_lsp" },
    { name = "luasnip" },
    { name = "buffer" },
    { name = "nvim_lua" },
    { name = "async_path" },
  },
}

-- 注意：tbl_deep_extend("force", A, B) 是 B 覆盖 A，个人配置放最后优先生效。
-- 必须是 nvchad.configs.cmp（完整配置：全套键位 + base46 高亮），
-- 而不是 nvchad.cmp（那是 ui 里的纯样式模块，只有 formatting/window）。
return vim.tbl_deep_extend("force", require "nvchad.configs.cmp", options)
