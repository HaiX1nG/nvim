# nvim

我的 Neovim 配置：**NvChad v2.5（base46 / ui 走 v3.0）+ Neovim 0.12**，
一台新的 macOS 从零到能用只要一条命令。

```
git clone https://github.com/HaiX1nG/nvim.git ~/.config/nvim
cd ~/.config/nvim && bash install.sh
```

不想手动 clone 也可以：

```
bash <(curl -fsSL https://raw.githubusercontent.com/HaiX1nG/nvim/main/install.sh)
```

脚本会装 Homebrew（没有的话）、neovim、ripgrep、fd、node、字体，
备份旧配置到 `nvim.bak.时间戳`，再同步插件和 treesitter 解析器。
`--dry-run` 可以先看它打算干什么，`--with-tools` 会把 LSP 也一起装好。

> 国内网络：`raw.githubusercontent.com` 经常连不上，那就走上面 `git clone` 那条，
> 或者给 brew / git 挂好代理再来。插件是从 GitHub 拉的，同理。

## 这套配置里有什么

**观感**

- 主题 `tokyonight`，编辑区铺一层主题底色（半透明交给终端的不透明度）
- 分模式光标：普通蓝块 / 插入绿竖线 / 替换红横线，换主题后颜色跟着重算
- `smear-cursor` 光标拖尾，颜色从光标高亮组反查，改一处两边一起变
- 代码的**粗体 / 斜体**（关键字、类型、常量加粗；注释、参数、内建类型斜体），
  `:StyleCheck` 一键自检「到底生效没有」
- 彩虹括号，取的是 tokyonight 调色板
- Markdown 富文本渲染（标题放大、表格画框、代码块加边框），`:RenderMarkdown toggle` 可关

**写代码**

- treesitter 高亮（Neovim 0.12 下要自己 `vim.treesitter.start()`，配置里用 FileType 自动命令接上了）
- LSP：rust / go / python / typescript / html / css / json / yaml / bash
- 自动导包
  - Rust：光标停下就按词问 `textDocument/codeAction`，命中 `Import ...` 就 resolve 落地
  - TS/JS：命中 `Cannot find name` 后走 `source.addMissingImports`
  - Go：走 `source.organizeImports`（会连没用到的 import 一起删，跟 GoLand 一样）
  - Python：靠 pyright 补全自带的 `additionalTextEdits`，不用额外代码
- 安静落盘：退出插入模式 500ms、切窗口、失焦时保存（类 IDEA autosave）
- 补全 `nvim-cmp`：Tab 确认，上下键翻页
- 状态栏 LSP 模块改过：多服务器全列出来，不再被终端列宽吃掉

## 键位

NvChad 默认的那套都在，常用：

| 键 | 干什么 |
| --- | --- |
| `<C-n>` | 文件树 |
| `<C-s>` | 保存 |
| `<leader>ff` | 找文件 |
| `<leader>fw` | 全文搜索 |
| `<leader>th` | 换主题 |
| `<Tab>` / `<S-Tab>` | 切缓冲区 |
| `;` | 进命令行模式 |

自己加的：

| 键 | 干什么 |
| --- | --- |
| `jk`（插入模式） | 回普通模式 |
| `<leader>ca` | 代码动作（code action） |
| `<leader>cs` | 开关光标拖尾 |
| `<leader>rr` | 编译运行当前 Rust 文件（`cargo run --bin <文件名>`） |
| `<leader>rh` | 开关类型提示（inlay hints） |

## 依赖

| 东西 | 为什么 |
| --- | --- |
| Neovim ≥ 0.11 | 用了 `vim.lsp.config` / `vim.lsp.enable` / `vim.uv`；0.12 最稳 |
| git | lazy.nvim 拉插件 |
| ripgrep | telescope 全文搜索 |
| fd | telescope 找文件 |
| node | pyright / ts_ls / prettier 这些 mason 包要 node |
| python3 | python provider |
| Nerd Font | 图标（脚本默认装 JetBrainsMono Nerd Font）|

Mason 装的 LSP / 格式化工具在 `~/.local/share/nvim/mason`，
配置里开了 `run_on_start`，缺什么会在打开 nvim 后自动补。

## 目录结构

```
init.lua              # 入口：bootstrap lazy、加载主题缓存、require 各模块
install.sh            # macOS 一键安装
lazy-lock.json        # 插件版本锁（跟着仓库走，换机装到同一批 commit）
lua/
├── chadrc.lua        # 主题、状态栏模块顺序、自定义 lsp 模块
├── options.lua       # 光标 / 粗体斜体 / :StyleCheck
├── mappings.lua      # 自定义键位
├── autocmds.lua      # treesitter 启动、状态栏刷新、解析器自动安装
├── configs/
│   ├── cursor.lua        # 光标：颜色、形状（单一数据源）
│   ├── style.lua         # 粗体 / 斜体规则表 + 自检
│   ├── rainbow.lua       # 彩虹括号配色
│   ├── transparency.lua  # 编辑区 / 文件树铺底色
│   ├── cmp.lua           # 补全键位
│   ├── lspconfig.lua     # LSP 服务器、自动导包、安静落盘
│   ├── conform.lua       # 格式化（stylua）
│   └── lazy.lua          # lazy.nvim 设置
└── plugins/
    ├── init.lua        # 插件清单
    └── smear_cursor.lua
```

## 常见问题

**图标全是方块** —— 字体没选对。终端设置里把字体换成 `JetBrainsMono Nerd Font`。

**第一次打开半天没动静** —— 在装东西。mason 的 LSP 是后台装的，` :Mason ` 能看到进度。

**报 `No highlight group 'IblChar' found`（indent-blankline）**
第一次启动时 base46 的主题缓存还没生成，重开一次 nvim 就好。
`install.sh` 里已经加了一次预热启动，正常情况下碰不到。

**`:StyleCheck` 说粗体/斜体没生效**
多半是主题缓存和装载顺序的问题，`:Lazy sync` 后重开 nvim 再看；
还不行就 `:lua require("configs.style").apply()` 手动套一次。

**终端里颜色发灰、没有真彩色**
`echo $COLORTERM` 应该是 `truecolor`；Terminal.app 需要换掉（iTerm2 / kitty / Ghostty 都行）。

**`curl` 那行装不动**
`raw.githubusercontent.com` 被墙了，用 `git clone` 那条路，或者挂好代理。

## 更新

```
cd ~/.config/nvim && git pull
```

然后在 nvim 里 `:Lazy sync`。插件版本由 `lazy-lock.json` 钉住，
`:Lazy update` 之后记得把新的 lock 文件提交回来。

## 卸载 / 回退

配置是纯文件，删了就没了；插件数据在 `~/.local/share/nvim`、
状态在 `~/.local/state/nvim`、缓存 `~/.cache/nvim`，三个目录一起删就干净了。
装的时候会自动备份旧配置到 `~/.config/nvim.bak.时间戳`，想回退改名回来即可。

## 说明

- 这是从 [NvChad/starter](https://github.com/NvChad/starter) 长出来的配置，
  主题/UI 那部分还是 NvChad 的功劳，LICENSE 沿用上游（Unlicense）。
- 代码里的注释写的是「为什么这么写」而不是「这行在干嘛」，
  踩过的坑（0.12 的 treesitter 行为、base46 缓存覆盖粗体、r-a 不分析脏缓冲区……）
  都留在对应位置，改之前值得先看一眼。

## Credits

1. [NvChad](https://github.com/NvChad/NvChad) / [starter](https://github.com/NvChad/starter)
2. [LazyVim starter](https://github.com/LazyVim/starter) —— NvChad starter 的灵感来源
