require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")
map("n", "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })
map("n", "<leader>cs", "<cmd>SmearCursorToggle<CR>", { desc = "Toggle smear cursor" })

-- 写作业常用：<leader>rr 直接编译运行当前练习文件
--
-- 只在 cargo 包里的 .rs 上生效，按文件所在位置推 bin 名：
--   作业在 src/bin/e3.rs  -> cargo run --bin e3
--   否则（answers/e1_x.rs）-> cargo run --bin 文件名
-- 因为 nvim 不是终端，用 :te 开一个底部终端跑，能看到 stdin 和输出。
map("n", "<leader>rr", function()
  if vim.bo.filetype ~= "rust" then
    return vim.notify("不是 Rust 文件", vim.log.levels.WARN)
  end
  local file = vim.api.nvim_buf_get_name(0)
  local root = vim.fs.root(0, "Cargo.toml")
  if not root then
    return vim.notify("这个文件不在 cargo 包里，先看 README 把作业目录改成项目", vim.log.levels.ERROR)
  end
  local bin = vim.fs.basename(file):gsub("%.rs$", "")
  -- 必须显式 cd 到包根再跑：:term 继承的是 nvim 的启动目录，
  -- 从 ~ 启动打开文件的话 cargo 会在 ~ 找不到 Cargo.toml（实测报过错）。
  local cmd = ("cd %s && cargo run --bin %s"):format(vim.fn.shellescape(root), vim.fn.shellescape(bin))
  vim.cmd("botright split | resize 15 | term " .. cmd)
  vim.cmd "startinsert"
end, { desc = "Rust: cargo run 当前文件" })

-- 类型提示开/关（有些地方太花，可以随手关）
map("n", "<leader>rh", function()
  local on = vim.lsp.inlay_hint.is_enabled { bufnr = 0 }
  vim.lsp.inlay_hint.enable(not on, { bufnr = 0 })
  vim.notify("类型提示 " .. (on and "关" or "开"))
end, { desc = "Rust: 切换类型提示" })


-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
