require "nvchad.options"

-- add yours here!

-- 光标：分模式形状 + 分模式颜色
-- 配色、形状集中在 lua/configs/cursor.lua，smear-cursor 的拖尾颜色也从那里同步
local cursor = require "configs.cursor"

cursor.apply()

-- 换主题后重新套用光标配色，并把颜色同步给 smear-cursor
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    cursor.apply()
  end,
})

-- 代码的粗体 / 斜体
--
-- base46 的 tokyonight 只定义颜色，粗体/斜体要单独补；
-- 换主题时得重新套一遍，否则会被新主题的缓存覆盖掉。
local style = require "configs.style"

style.apply()

-- :StyleCheck —— 自检「到底生效没有」
vim.api.nvim_create_user_command("StyleCheck", function()
  style.check()
end, { desc = "检查代码粗体/斜体是否生效" })

-- 启动自检：只有真的没生效时才提示（正常情况保持安静）
vim.schedule(function()
  local st = style.stats()
  if st.bold == 0 or st.italic == 0 then
    vim.notify(
      string.format(
        "粗体/斜体未生效（bold=%d italic=%d），配置文件: %s",
        st.bold,
        st.italic,
        vim.fn.stdpath "config"
      ),
      vim.log.levels.WARN,
      { title = "style" }
    )
  end
end)

vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    style.apply()
  end,
})

-- base46 切换主题走的是 load_all_highlights()，它会重新编译并加载所有缓存，
-- 触发的事件是 User NvThemeReload（不是 ColorScheme）
vim.api.nvim_create_autocmd("User", {
  pattern = "NvThemeReload",
  callback = function()
    style.apply()
  end,
})

-- local o = vim.o
-- o.cursorlineopt ='both' -- to enable cursorline!
