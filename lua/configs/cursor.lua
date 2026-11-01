-- 光标配置的单一数据源
--
-- lua/options.lua（形状 + 高亮组）和 lua/plugins/smear_cursor.lua（拖尾颜色）
-- 都从这里取值 —— 改光标配色只需要动这一个文件。

local M = {}

-- 分模式光标颜色
M.colors = {
  normal = "#7aa2f7", -- 普通模式：tokyonight 蓝
  insert = "#9ece6a", -- 插入模式：绿
  replace = "#f7768e", -- 替换模式：红
}

M.fg = "#1a1b26" -- 光标底色上的前景

-- 光标高亮组名 -> M.colors 的键
M.groups = {
  nCursor = "normal",
  iCursor = "insert",
  rCursor = "replace",
}

-- 分模式形状。kitty 支持 DECSCUSR，形状由终端原生渲染，不需要插件。
-- group-name 把每个模式绑到对应高亮组。
--
-- 注意 1：高亮组上绝对不要加 blend=100。
-- neovim src/nvim/tui/tui.c:1389 是这么写的：
--     tui->want_invisible = aep.hl_blend == 100;
-- blend=100 的含义是「把这个光标藏掉」，不是「让颜色生效」，
-- 加了光标就整个消失（ESC[?25l），这正是「光标不显示」的根因。
--
-- 注意 2：顺序必须是「先设高亮组，再设 guicursor」。
-- 'guicursor' 解析时会 syn_id2attr() 抓当时的颜色快照发给 TUI，
-- 先设 guicursor 再设颜色的话，TUI 拿到的还是空高亮组（没有 bg）。
--
-- 终端光标颜色也是 nvim 自己下发的，不用手动发 OSC 12：
-- tui.c:2055 的 terminfo_is_term_family("xterm-kitty", "xterm") 命中 xterm 家族，
-- 于是 tui.c:2395 启用 "\033]12;%p1%s\007"，nvim 拿高亮组的 bg 当光标色，
-- 退出时 tui.c:569 自动 OSC 112 复位。
M.guicursor =
  "n-v-c-sm:block-nCursor,i-ci-ve:ver25-iCursor,r-cr-o:hor20-rCursor,t:block-blinkon500-blinkoff500-TermCursor"

--- 从当前实际生效的高亮组反查颜色（改 :hi 也能跟上）
---@return table<string, string>
function M.colors_from_hl()
  local out = {}
  for group, mode in pairs(M.groups) do
    local hl = vim.api.nvim_get_hl(0, { name = group })
    if hl.bg then
      out[mode] = string.format("#%06x", hl.bg)
    end
  end
  return out
end

--- 把颜色推给 smear-cursor（插件没加载时静默跳过）
function M.sync_smear()
  local ok, sc = pcall(require, "smear_cursor")
  if not ok then
    return
  end

  local c = M.colors_from_hl()
  if c.normal then
    sc.cursor_color = c.normal
  end
  if c.insert then
    sc.cursor_color_insert_mode = c.insert
  end
end

--- 应用形状 + 高亮组
function M.apply()
  for group, mode in pairs(M.groups) do
    vim.api.nvim_set_hl(0, group, {
      fg = M.fg,
      bg = M.colors[mode],
    })
  end

  vim.o.guicursor = M.guicursor

  M.sync_smear()
end

return M
