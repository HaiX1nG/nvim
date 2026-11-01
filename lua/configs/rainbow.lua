-- 彩虹括号（rainbow delimiters）的配色
--
-- 为什么需要单独一个文件：
--   rainbow-delimiters.nvim 用的是七个「非标准」高亮组
--   （RainbowDelimiterRed / Yellow / Blue / Orange / Green / Violet / Cyan），
--   任何主题都不会自动定义它们 —— 插件只给一组默认值，
--   想跟当前主题统一就得自己定义一遍。
--
-- 颜色全部取自 base46 的 tokyonight 调色板，保证和其它语法颜色是同一套色系：
--   baseB #f7768e  baseD #e0af68  base8 #7aa2f7  baseC #ff9e64
--   baseF #9ece6a  magenta #bb9af7  base7 #7dcfff
--
-- 插件默认的分组顺序是「红 黄 蓝 橙 绿 紫 青」，刻意不按彩虹顺序排，
-- 这样相邻的两层括号对比更明显（红/黄、蓝/橙 都不是邻近色）。

local M = {}

--- 插件使用的高亮组，顺序即配色轮转顺序
---@type string[]
M.groups = {
  "RainbowDelimiterRed",
  "RainbowDelimiterYellow",
  "RainbowDelimiterBlue",
  "RainbowDelimiterOrange",
  "RainbowDelimiterGreen",
  "RainbowDelimiterViolet",
  "RainbowDelimiterCyan",
}

--- 每个高亮组的颜色
---@type table<string, string>
M.colors = {
  RainbowDelimiterRed = "#f7768e",
  RainbowDelimiterYellow = "#e0af68",
  RainbowDelimiterBlue = "#7aa2f7",
  RainbowDelimiterOrange = "#ff9e64",
  RainbowDelimiterGreen = "#9ece6a",
  RainbowDelimiterViolet = "#bb9af7",
  RainbowDelimiterCyan = "#7dcfff",
}

--- 应用配色
---
--- 用 nvim_set_hl（整体替换语义）而不是 highlight link：
--- 插件的默认值是硬编码的一套通用色，跟 tokyonight 的实际色值对不上。
function M.apply()
  for group, color in pairs(M.colors) do
    vim.api.nvim_set_hl(0, group, { fg = color })
  end
end

--- 主题切换后重新应用配色
---
--- 两个坑：
---   1. 插件自己在 ColorScheme 时会重新定义这七个组（用它的通用默认色），
---      把我们的 tokyonight 配色冲掉。它的自动命令是在 packadd 时注册的，
---      我们的注册在它之后 —— 自动命令按注册顺序执行，所以我们赢。
---   2. base46 切换主题走的是 User NvThemeReload，不是 ColorScheme，
---      得单独接上。
function M.watch()
  local group = vim.api.nvim_create_augroup("UserRainbowDelimiters", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    desc = "重新应用彩虹括号配色",
    callback = M.apply,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "NvThemeReload",
    desc = "重新应用彩虹括号配色（base46 切主题）",
    callback = M.apply,
  })
end

return M
