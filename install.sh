#!/usr/bin/env bash
#
# install.sh —— 在 macOS 上一键装好 Neovim + 本仓库的 NvChad 配置
#
#   用法：
#     bash install.sh                 # 装依赖 → 拉配置 → 装插件和解析器
#     bash install.sh --with-tools    # 再把 LSP / 格式化 / linter 一起装好（几分钟）
#     bash install.sh --dry-run       # 只打印要做什么，不动手
#     bash install.sh --no-font       # 不装 Nerd Font（自己已经有字体时用）
#
#   环境变量（可选）：
#     NVIM_CONFIG_REPO    换个仓库地址
#     NVIM_CONFIG_BRANCH  分支名，默认 main
#     NVIM_CONFIG_DIR     配置目录，默认 ~/.config/nvim
#
# 不会删除任何东西：老配置只做改名备份（nvim.bak.时间戳）。
#
set -euo pipefail

REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/HaiX1nG/nvim.git}"
BRANCH="${NVIM_CONFIG_BRANCH:-main}"
CONFIG_DIR="${NVIM_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nvim}"

DRY_RUN=0
WITH_FONT=1
WITH_TOOLS=0
SKIP_PLUGINS=0

# macOS 自带的 bash 是 3.2，这里只用 3.2 也支持的写法
# （没有关联数组、没有 ${var,,}、没有 mapfile）

# ---------------------------------------------------------------- 输出样式

if [ -t 1 ]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_BLUE=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
fi

step() { printf '\n%s==> %s%s\n' "$C_BLUE$C_BOLD" "$*" "$C_RESET"; }
info() { printf '    %s\n' "$*"; }
ok() { printf '    %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '    %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() {
  printf '\n%s✗ %s%s\n\n' "$C_RED$C_BOLD" "$*" "$C_RESET" >&2
  exit 1
}

# 会真正执行的命令都走这里，dry-run 时只打印
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '    %s[dry-run] %s%s\n' "$C_DIM" "$*" "$C_RESET"
    return 0
  fi
  "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  # 只打印文件开头那段注释，遇到第一行非注释就停
  awk 'NR > 1 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else { exit } }' "$0"
  exit 0
}

# 版本比较：version_ge 1.2.3 1.1.0 → 真
version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) {
      if (x[i] + 0 > y[i] + 0) exit 0
      if (x[i] + 0 < y[i] + 0) exit 1
    }
    exit 0
  }'
}

# ---------------------------------------------------------------- 参数

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage ;;
    --dry-run) DRY_RUN=1 ;;
    --no-font) WITH_FONT=0 ;;
    --with-tools) WITH_TOOLS=1 ;;
    --skip-plugins) SKIP_PLUGINS=1 ;;
    --repo)
      [ $# -ge 2 ] || die "--repo 后面要跟仓库地址"
      REPO_URL="$2"
      shift
      ;;
    --branch)
      [ $# -ge 2 ] || die "--branch 后面要跟分支名"
      BRANCH="$2"
      shift
      ;;
    --dir)
      [ $# -ge 2 ] || die "--dir 后面要跟目录"
      CONFIG_DIR="$2"
      shift
      ;;
    *) die "看不懂的参数：$1（用 --help 看用法）" ;;
  esac
  shift
done

# ---------------------------------------------------------------- 0. 环境检查

step "0/7 环境检查"

SYS="$(uname -s)"
if [ "$SYS" != "Darwin" ]; then
  if [ "${NVIM_SETUP_FORCE:-0}" = "1" ]; then
    warn "当前不是 macOS（$SYS），但 NVIM_SETUP_FORCE=1，继续"
  else
    die "这个脚本是给 macOS 用的（当前系统：$SYS）。"
  fi
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) BREW_PREFIX="/opt/homebrew" ;;
  x86_64) BREW_PREFIX="/usr/local" ;;
  *) BREW_PREFIX="/opt/homebrew" ;;
esac
info "系统 $SYS / $ARCH"

# Xcode 命令行工具：编译 treesitter 解析器要 clang，没有它 brew 也装不了
if [ "${NVIM_SETUP_FORCE:-0}" = "1" ]; then
  ok "跳过 Xcode CLT 检查（NVIM_SETUP_FORCE=1）"
elif xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools 已就绪"
else
  warn "缺少 Xcode Command Line Tools（编译 treesitter 解析器需要 clang）"
  if [ "$DRY_RUN" = 1 ]; then
    info "[dry-run] xcode-select --install"
  else
    info "正在唤起系统安装窗口，点「安装」，装完再跑一次本脚本就好"
    xcode-select --install || true
    exit 0
  fi
fi

# ---------------------------------------------------------------- 1. Homebrew

step "1/7 Homebrew"

if have brew; then
  ok "brew 已安装：$(command -v brew)"
elif [ -x "$BREW_PREFIX/bin/brew" ]; then
  # 装了但没进 PATH（Apple Silicon 上很常见）
  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
  ok "brew 已在 $BREW_PREFIX，已临时加进 PATH"
else
  info "没有 Homebrew，开始安装（中途可能要输 sudo 密码）"
  info "装完会写进 ~/.zprofile，新的终端会自动带上 PATH"
  if [ "$DRY_RUN" = 1 ]; then
    info "[dry-run] 安装 Homebrew 到 $BREW_PREFIX"
  else
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" ||
      die "Homebrew 安装失败，网络不通的话先解决代理再来"
    if [ -x "$BREW_PREFIX/bin/brew" ]; then
      eval "$("$BREW_PREFIX/bin/brew" shellenv)"
    fi
    have brew || die "Homebrew 装完还是找不到 brew，看看 $BREW_PREFIX/bin"
    ok "Homebrew 装好了"
  fi
fi

# 把 brew shellenv 写进 zprofile，免得新开终端找不到（已写过就不重复写）
if [ "$DRY_RUN" != 1 ] && [ "$SYS" = "Darwin" ] && [ -x "$BREW_PREFIX/bin/brew" ]; then
  if ! grep -qs "brew shellenv" "$HOME/.zprofile"; then
    {
      printf '\n# Homebrew\n'
      printf 'eval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX"
    } >>"$HOME/.zprofile"
    ok "已把 brew shellenv 写进 ~/.zprofile"
  fi
fi

# ---------------------------------------------------------------- 2. 依赖

step "2/7 安装依赖（neovim / ripgrep / node …）"

# neovim   : 本体（要 0.11+，配置里用了 vim.lsp.config / vim.uv）
# git      : lazy.nvim 拉插件
# ripgrep  : telescope 全文搜索
# fd       : telescope 找文件
# lazygit  : 终端里的 git TUI（可选，平时用得上的话挺爽）
# node     : pyright / ts / prettier 这些 mason 包要 node
# python   : python3 provider + 部分 mason 工具
# tree-sitter-cli : nvim-treesitter 新分支编译解析器要用
FORMULAE="neovim git ripgrep fd lazygit node python tree-sitter-cli"

for pkg in $FORMULAE; do
  if brew list --formula "$pkg" >/dev/null 2>&1; then
    ok "$pkg 已装"
  else
    info "安装 $pkg …"
    if ! run brew install "$pkg"; then
      warn "$pkg 安装失败，先跳过（后面可能手动补）"
    fi
  fi
done

# ---------------------------------------------------------------- 3. 字体

if [ "$WITH_FONT" = 1 ]; then
  step "3/7 Nerd Font（图标要用）"
  if brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
    ok "JetBrainsMono Nerd Font 已装"
  else
    info "安装 JetBrainsMono Nerd Font …"
    run brew install --cask font-jetbrains-mono-nerd-font ||
      warn "字体没装上，图标会显示成方块；手动装也行：brew install --cask font-jetbrains-mono-nerd-font"
  fi
else
  step "3/7 跳过字体（--no-font）"
fi

# ---------------------------------------------------------------- 4. 配置

step "4/7 部署配置到 $CONFIG_DIR"

if [ -d "$CONFIG_DIR/.git" ]; then
  info "这里已经是个 git 仓库了，按更新处理"
  if [ "$DRY_RUN" != 1 ] && [ -n "$(git -C "$CONFIG_DIR" status --porcelain 2>/dev/null || true)" ]; then
    warn "本地有未提交的改动，跳过 git pull（自己 commit 或 stash 后再来）"
  else
    run git -C "$CONFIG_DIR" pull --ff-only || warn "pull 失败，先用现有版本继续"
  fi
elif [ -e "$CONFIG_DIR" ]; then
  BACKUP="$CONFIG_DIR.bak.$(date +%Y%m%d-%H%M%S)"
  info "已有旧配置，先备份到 $BACKUP"
  if [ "$DRY_RUN" = 1 ]; then
    info "[dry-run] mv $CONFIG_DIR $BACKUP"
    info "[dry-run] git clone --branch $BRANCH $REPO_URL $CONFIG_DIR"
  else
    mv "$CONFIG_DIR" "$BACKUP"
    if ! git clone --branch "$BRANCH" "$REPO_URL" "$CONFIG_DIR"; then
      warn "克隆失败，把旧配置挪回去，别让你没得用"
      mv "$BACKUP" "$CONFIG_DIR"
      die "克隆失败：$REPO_URL（私有仓库先手动 clone 一次让系统记住凭据）"
    fi
    ok "配置就位（旧配置在 $BACKUP）"
  fi
else
  run git clone --branch "$BRANCH" "$REPO_URL" "$CONFIG_DIR" || die "克隆失败：$REPO_URL"
  ok "配置就位"
fi

# ---------------------------------------------------------------- 5. 插件

step "5/7 安装插件（lazy.nvim）"

NVIM_BIN="$(command -v nvim || true)"
if [ -z "$NVIM_BIN" ] && [ -x "$BREW_PREFIX/bin/nvim" ]; then
  NVIM_BIN="$BREW_PREFIX/bin/nvim"
fi
[ -n "$NVIM_BIN" ] || die "找不到 nvim 命令"

if [ "$SKIP_PLUGINS" = 1 ]; then
  info "跳过（--skip-plugins），第一次打开 nvim 时会自己装"
else
  info "同步插件中，这一步要看网速（几分钟）…"
  # stdin 接 /dev/null，免得 headless 里卡在提示符上
  if ! run "$NVIM_BIN" --headless "+Lazy! sync" "+qa" </dev/null; then
    warn "插件同步有报错，可以稍后打开 nvim 手动 :Lazy sync"
  else
    ok "插件同步完成"
  fi
  # 预热一次：base46 的主题缓存是这次同步里才生成的，
  # 不重开一次的话，indent-blankline 会在 setup 时找不到 IblChar 高亮组而报错
  run "$NVIM_BIN" --headless "+qa" </dev/null >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------- 6. 解析器

step "6/7 编译 treesitter 解析器"

# 注意：:TSInstall 是异步的。`nvim --headless "+TSInstall! x" +qa` 会在下载
# 还没跑完时就退出 —— 看起来 exit 0，其实一个 parser 都没装上（实测踩过）。
# 所以这里用 install():wait() 阻塞到真的编译安装完。
PARSERS_LUA='{ "rust", "go", "lua", "vim", "vimdoc", "luadoc", "json", "yaml", "html", "css", "javascript", "typescript", "toml", "bash", "python", "markdown", "markdown_inline" }'

if [ "$SKIP_PLUGINS" = 1 ]; then
  info "跳过（--skip-plugins）"
elif ! run "$NVIM_BIN" --headless \
  -c "lua require('nvim-treesitter').install($PARSERS_LUA, { max_jobs = 4 }):wait(900000)" \
  -c "qa!" </dev/null; then
  warn "解析器编译有报错；打开 nvim 后 :TSInstall 可以补"
else
  ok "解析器就绪"
fi

# ---------------------------------------------------------------- 7. 工具

step "7/7 LSP / 格式化工具（mason）"

if [ "$WITH_TOOLS" = 1 ]; then
  info "同步安装 lua-ls / pyright / rust-analyzer / prettier …（慢，几分钟）"
  # 这个插件是 event = "VimEnter" 懒加载的，headless 下 `+MasonToolsInstallSync`
  # 会在命令还没定义时就被执行（E492）。先手动 load 一次，命令才在。
  # MasonToolsInstallSync 本身是阻塞的，会等到全部装完。
  if ! run "$NVIM_BIN" --headless \
    -c "lua require('lazy').load({ plugins = { 'mason-tool-installer.nvim' } })" \
    -c "MasonToolsInstallSync" \
    -c "qa!" </dev/null; then
    warn "mason 安装有报错，之后打开 nvim 会自动重试（配置里开了 run_on_start）"
  else
    ok "工具装好了"
  fi
else
  info "跳过（没加 --with-tools）"
  info "不用管：配置里开了 run_on_start，第一次打开 nvim 会自动后台装"
fi

# ---------------------------------------------------------------- 收尾

step "收尾检查"

if [ "$DRY_RUN" != 1 ] && [ -x "$NVIM_BIN" ]; then
  NVIM_VER="$("$NVIM_BIN" --version | head -1 | sed -E 's/^NVIM v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
  info "Neovim $NVIM_VER"
  # 配置用了 vim.lsp.config / vim.lsp.enable，至少要 0.11
  if version_ge "$NVIM_VER" "0.11.0"; then
    ok "版本够用"
  else
    warn "Neovim 版本偏低（$NVIM_VER < 0.11），配置会报错，执行 brew upgrade neovim"
  fi
  [ -f "$CONFIG_DIR/init.lua" ] && ok "配置文件在 $CONFIG_DIR"
fi

cat <<EOF

${C_BOLD}装好了。${C_RESET}

  ${C_BOLD}nvim${C_RESET}            打开（第一次会自动补装缺的解析器和 mason 工具）
  ${C_BOLD}:checkhealth${C_RESET}     体检
  ${C_BOLD}:StyleCheck${C_RESET}      看粗体/斜体到底生效没有
  ${C_BOLD}:Lazy${C_RESET}            插件面板：S 同步、U 更新、C 清理
  ${C_BOLD}:Mason${C_RESET}           LSP / 格式化工具面板

常用键位：
  ${C_BOLD}<空格>${C_RESET} 是 leader。 ${C_BOLD}<C-n>${C_RESET} 文件树  ${C_BOLD}<C-s>${C_RESET} 保存
  ${C_BOLD}<leader>ff${C_RESET} 找文件  ${C_BOLD}<leader>fw${C_RESET} 全文搜  ${C_BOLD}<leader>th${C_RESET} 换主题
  ${C_BOLD}<leader>ca${C_RESET} 代码动作  ${C_BOLD}<leader>rr${C_RESET} 跑当前 Rust 文件  ${C_BOLD}<leader>cs${C_RESET} 光标拖尾

终端建议：
  · 字体选 “JetBrainsMono Nerd Font” ，不然图标是方块
  · 打开 24 位真彩色（iTerm2 默认可以，Terminal.app 建议换掉）
  · 编辑区想做半透明：把终端背景不透明度调到 0.75 左右

更新配置：
  cd ${CONFIG_DIR} && git pull         然后 nvim 里 :Lazy sync
EOF
