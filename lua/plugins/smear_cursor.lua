-- 光标拖尾 / 涂抹动画
--
-- 原理：监听 CursorMoved / CursorMovedI，在光标身后绘制渐隐的方块拖尾。
-- 动画期间插件会临时往 vim.o.guicursor 追加一段 `a:SmearCursorHide`
-- 把原生光标藏起来，停稳后再用 gsub 摘掉这一段 —— 所以不会破坏
-- lua/configs/cursor.lua 里 nCursor / iCursor / rCursor 的分模式绑定。
--
-- 拖尾颜色不写死：由 configs.cursor 从实际生效的高亮组反查后推给插件，
-- 所以改 lua/configs/cursor.lua 里的颜色，光标和拖尾两边同时变。

local cursor = require "configs.cursor"

return {
  {
    "sphamba/smear-cursor.nvim",
    config = function()
      require("smear_cursor").setup {
        -- 跨 buffer / 窗口跳转时也带拖尾
        smear_between_buffers = true,
        smear_between_neighbor_lines = true,
        smear_insert_mode = true,

        -- 火花粒子（不覆盖光标所在格，停下时露出原生光标）
        particles_enabled = true,
        never_draw_over_target = true,
      }

      -- 高亮组可能还没建好（options.lua 在 lazy.setup 之后才执行），
      -- 同步是幂等的，两边谁后跑谁生效
      cursor.sync_smear()
    end,
  },
}
