-- 半透明编辑区 + 文件树
--
-- Neovim 的高亮背景不支持 alpha。把 bg 设成 NONE 是「全透明」（直接看到桌面），
-- 不是主人要的「半透明」。这里统一给编辑区和文件树铺一层主题的深色底，
-- 真正的透明度交给终端：kitty 的 background_opacity = 0.75，
-- 即窗口整体 75% 不透明，背后的桌面会有 25% 透进来。
--
-- 同时把 nvim-tree 的底色从 base46 默认的 darker_black 拉平到 Normal 的 black，
-- 避免「代码区一个色、文件树另一个色」的割裂感。

local M = {}

-- 主题取不到 bg 时的兜底（tokyonight 的 black）
local fallback_bg = 0x1a1b26

local groups = {
  -- 编辑区
  "Normal",
  "NormalNC",
  "SignColumn",
  "LineNr",
  "EndOfBuffer",
  "FoldColumn",
  -- 文件树（nvim-tree.lua）
  "NvimTreeNormal",
  "NvimTreeNormalNC",
  "NvimTreeEndOfBuffer",
  "NvimTreeLineNr",
  "NvimTreeSignColumn",
}

function M.apply()
  -- 以主题的 Normal 背景为准；如果当前是 NONE（旧配置残留），用兜底色
  local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
  local bg = normal.bg or fallback_bg

  for _, name in ipairs(groups) do
    -- 用 :highlight 只改背景，保留 fg / bold 等原有属性
    pcall(vim.cmd, ("highlight %s guibg=#%06x"):format(name, bg))
  end
end

M.apply()

local augroup = vim.api.nvim_create_augroup("WhaleTransparency", { clear = true })

-- 切主题后重新铺底
vim.api.nvim_create_autocmd("ColorScheme", {
  group = augroup,
  callback = function()
    M.apply()
  end,
})

-- 文件树加载/打开后兜底一次（nvim-tree 是懒加载的）
vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = "NvimTree",
  callback = function()
    M.apply()
  end,
})

-- lazy.nvim 启动完成后再兜底一次
vim.api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "VeryLazy",
  callback = function()
    M.apply()
  end,
})

return M
