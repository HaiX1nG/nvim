#!/usr/bin/env bash
#
# sync.sh —— macOS 一键：把 Neovim 洗回干净状态，再同步本仓库的 NvChad 配置
#
#   解决的场景：机器上以前装过 LazyVim / 别的配置，插件目录里堆着半新半旧的
#   commit，换成本仓库配置之后报一堆错。这个脚本把插件、状态、缓存清干净，
#   再用 lazy-lock.json 里钉住的版本重新同步一遍。
#
#   用法：
#     bash sync.sh                 # 先问一句，再干活
#     bash sync.sh --yes           # 不问，直接干
#     bash sync.sh --dry-run       # 只打印要删什么、装什么，不动手
#     bash sync.sh --keep-config   # 不动 ~/.config/nvim，只洗插件再 git pull
#     bash sync.sh --hard          # 旧配置也不备份，直接删
#     bash sync.sh --with-tools    # 连 mason 的 LSP / 格式化工具一起装
#     bash sync.sh --skip-plugins  # 只换配置，插件留给自己 :Lazy sync
#     bash sync.sh --skip-parsers  # 不编译 treesitter 解析器
#     bash sync.sh --kill          # nvim 还开着的话，直接帮你关掉
#
#   会清掉的东西（都在 $HOME 下面）：
#     ~/.config/nvim        旧配置 → 改名备份成 nvim.bak.时间戳
#     ~/.local/share/nvim   插件、mason、site
#     ~/.local/state/nvim   shada、swap、undo、日志
#     ~/.cache/nvim         缓存
#     以及 LazyVim 留下的 ~/.config/lazyvim、~/.local/{share,state}/lazyvim、~/.cache/lazyvim
#
#   环境变量（可选）：
#     NVIM_CONFIG_REPO    换个仓库地址
#     NVIM_CONFIG_BRANCH  分支名，默认 main
#     NVIM_CONFIG_DIR     配置目录，默认 ~/.config/nvim
#     NVIM_SETUP_FORCE=1  非 macOS 也强行跑（调试用）
#
set -euo pipefail

# 有人 zsh sync.sh 直接跑的话，换回 bash 重来一遍
if [ -n "${ZSH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

REPO_URL="${NVIM_CONFIG_REPO:-https://github.com/HaiX1nG/nvim.git}"
BRANCH="${NVIM_CONFIG_BRANCH:-main}"
DEFAULT_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
CONFIG_DIR="${NVIM_CONFIG_DIR:-$DEFAULT_CONFIG}"

DRY_RUN=0
ASSUME_YES=0
KEEP_CONFIG=0
HARD=0
WITH_TOOLS=0
SKIP_PLUGINS=0
SKIP_PARSERS=0
KILL_NVIM=0

# macOS 自带 bash 只有 3.2：不用关联数组、不用 ${var,,}、不用 mapfile

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

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '    %s[dry-run] %s%s\n' "$C_DIM" "$*" "$C_RESET"
    return 0
  fi
  "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  awk 'NR > 1 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else { exit } }' "$0"
  exit 0
}

# ---------------------------------------------------------------- 参数

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage ;;
    --yes | -y) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --keep-config) KEEP_CONFIG=1 ;;
    --hard) HARD=1 ;;
    --with-tools) WITH_TOOLS=1 ;;
    --skip-plugins) SKIP_PLUGINS=1 ;;
    --skip-parsers) SKIP_PARSERS=1 ;;
    --kill) KILL_NVIM=1 ;;
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

# 删东西的路径必须是自己人：绝对路径、在 $HOME 底下、末级目录叫 nvim 或 lazyvim
safe_target() {
  local p="$1"
  case "$p" in
    "" | "/" | "$HOME" | "$HOME/") return 1 ;;
  esac
  case "$p" in
    "$HOME"/*) ;;
    *) return 1 ;;
  esac
  case "$p" in
    */nvim | */nvim/ | */lazyvim | */lazyvim/) return 0 ;;
    *) return 1 ;;
  esac
  return 1
}

exists() { [ -e "$1" ] || [ -L "$1" ]; }

dir_size() { du -sh "$1" 2>/dev/null | awk '{print $1}' || echo "?"; }

# 从 https / ssh / 本地路径里抠出 owner/repo，用来判断这个配置目录是不是本仓库
repo_slug() {
  printf '%s\n' "$1" |
    sed -E 's#^[A-Za-z+]+://##' |
    sed -E 's#^[^@/]+@[^:/]+:##' |
    sed -E 's#/+$##' |
    sed -E 's#\.git$##' |
    awk -F/ 'NF >= 2 { print $(NF - 1) "/" $NF; exit }'
}

is_our_config_repo() {
  [ -d "$CONFIG_DIR/.git" ] || return 1
  local url
  url="$(git -C "$CONFIG_DIR" remote get-url origin 2>/dev/null || true)"
  [ -n "$url" ] || return 1
  [ "$(repo_slug "$url")" = "$(repo_slug "$REPO_URL")" ]
}

# ---------------------------------------------------------------- 0. 环境

step "0/6 环境检查"

SYS="$(uname -s)"
if [ "$SYS" != "Darwin" ] && [ "${NVIM_SETUP_FORCE:-0}" != "1" ]; then
  die "这个脚本是给 macOS 用的（当前系统：$SYS）。调试的话用 NVIM_SETUP_FORCE=1"
fi
info "系统 $SYS / $(uname -m)"
info "shell：${SHELL##*/}（脚本本身用 bash，zsh 里直接跑没问题）"

if [ "$SYS" = "Darwin" ]; then
  case "$(uname -m)" in
    arm64) BREW_PREFIX="/opt/homebrew" ;;
    *) BREW_PREFIX="/usr/local" ;;
  esac
  if [ -x "$BREW_PREFIX/bin/brew" ]; then
    eval "$("$BREW_PREFIX/bin/brew" shellenv)"
  fi
else
  BREW_PREFIX="/usr/local"
fi

NVIM_BIN="$(command -v nvim || true)"
if [ -z "$NVIM_BIN" ]; then
  if have brew; then
    info "没装 neovim，先用 brew 装上"
    run brew install neovim || die "brew install neovim 失败，网络/代理解决一下再来"
    NVIM_BIN="$(command -v nvim || true)"
    [ -n "$NVIM_BIN" ] || NVIM_BIN="$BREW_PREFIX/bin/nvim"
  else
    die "没装 neovim，也没装 Homebrew。先跑 bash install.sh，或者 brew install neovim"
  fi
fi
[ -x "$NVIM_BIN" ] || die "找不到可执行的 nvim"
ok "neovim：$("$NVIM_BIN" --version | head -1)"

# 正在跑的 nvim 会一边被删一边写，先处理掉
if pgrep -x nvim >/dev/null 2>&1; then
  if [ "$KILL_NVIM" = 1 ]; then
    warn "nvim 还开着，按 --kill 关掉它"
    run pkill -x nvim || true
    sleep 1
  else
    die "nvim 还开着。先退出所有 nvim，或者加 --kill 让脚本帮你关"
  fi
fi

# ---------------------------------------------------------------- 清单

CFG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

step "1/6 要清理的目录"

TARGETS=""
TARGET_COUNT=0
add_target() {
  local p="$1"
  exists "$p" || return 0
  safe_target "$p" || die "路径看着不对，不敢删：$p"
  TARGETS="$TARGETS$p
"
  TARGET_COUNT=$((TARGET_COUNT + 1))
  info "删除  $p  （$(dir_size "$p")）"
  return 0
}

add_target "$DATA_HOME/nvim"
add_target "$STATE_HOME/nvim"
add_target "$CACHE_HOME/nvim"
add_target "$CFG_HOME/lazyvim"
add_target "$DATA_HOME/lazyvim"
add_target "$STATE_HOME/lazyvim"
add_target "$CACHE_HOME/lazyvim"

if [ "$TARGET_COUNT" = 0 ]; then
  info "（没有要删的目录，本来就挺干净）"
fi

if [ "$KEEP_CONFIG" = 1 ]; then
  info "保留配置：$CONFIG_DIR 不动（--keep-config）"
elif ! exists "$CONFIG_DIR"; then
  info "配置目录不存在，等下直接 clone"
elif is_our_config_repo; then
  info "配置已经是本仓库的 git 工作区，不用备份，等下 git pull"
elif [ "$HARD" = 1 ]; then
  info "删除  $CONFIG_DIR  （--hard，不备份）"
else
  info "备份  $CONFIG_DIR  →  $CONFIG_DIR.bak.$(date +%Y%m%d-%H%M%S)"
fi

BACKUP=""
if [ "$DRY_RUN" = 0 ] && [ "$ASSUME_YES" = 0 ]; then
  printf '\n    %s上面这些删了不回来（插件重装就有，配置有备份）。继续？[y/N] %s' "$C_BOLD" "$C_RESET"
  read -r ans || ans=""
  case "$ans" in
    y | Y | yes | YES) ;;
    *) die "行吧，什么都没动" ;;
  esac
fi

# ---------------------------------------------------------------- 2. 备份配置

step "2/6 备份旧配置"

if [ "$KEEP_CONFIG" = 1 ]; then
  info "跳过（--keep-config）"
elif ! exists "$CONFIG_DIR"; then
  info "跳过（没有旧配置）"
elif is_our_config_repo; then
  info "跳过（已经是本仓库的工作区，git pull 就够了）"
elif [ "$HARD" = 1 ]; then
  info "跳过（--hard）"
elif [ "$DRY_RUN" = 1 ]; then
  info "[dry-run] mv $CONFIG_DIR $CONFIG_DIR.bak.时间戳"
else
  BACKUP="$CONFIG_DIR.bak.$(date +%Y%m%d-%H%M%S)"
  n=1
  while exists "$BACKUP"; do
    BACKUP="$CONFIG_DIR.bak.$(date +%Y%m%d-%H%M%S)-$n"
    n=$((n + 1))
  done
  mv "$CONFIG_DIR" "$BACKUP"
  ok "旧配置在 $BACKUP"
fi

# ---------------------------------------------------------------- 3. 清理

step "3/6 清理插件 / 状态 / 缓存"

if [ "$TARGET_COUNT" = 0 ]; then
  info "没东西可删"
else
  printf '%s' "$TARGETS" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ "$DRY_RUN" = 1 ]; then
      info "[dry-run] rm -rf $p"
      continue
    fi
    rm -rf -- "$p"
    ok "删掉了 $p"
  done
fi

# ---------------------------------------------------------------- 4. 部署配置

step "4/6 部署配置到 $CONFIG_DIR"

if [ "$KEEP_CONFIG" = 1 ] && ! is_our_config_repo; then
  # --keep-config 的语义是「配置别动」，那就真的别动：不是 git 工作区就到此为止
  if exists "$CONFIG_DIR"; then
    warn "$CONFIG_DIR 不是本仓库的 git 工作区，--keep-config 下配置保持原样（插件已经洗过了）"
    warn "想换成仓库里的配置，去掉 --keep-config 再跑一次"
  else
    die "--keep-config 但 $CONFIG_DIR 根本不存在，没配置可留；去掉这个参数"
  fi
elif is_our_config_repo; then
  info "已经是本仓库的 git 工作区，按更新处理"
  if [ "$DRY_RUN" = 0 ] && [ -n "$(git -C "$CONFIG_DIR" status --porcelain 2>/dev/null || true)" ]; then
    warn "本地有未提交的改动，跳过 git pull（先 commit 或 stash 再来）"
  else
    run git -C "$CONFIG_DIR" fetch --prune origin || warn "fetch 失败，先用手上的版本继续"
    run git -C "$CONFIG_DIR" merge --ff-only "origin/$BRANCH" || warn "快进失败（本地改了东西？），先用手上的版本继续"
  fi
  ok "配置：$(git -C "$CONFIG_DIR" log -1 --oneline 2>/dev/null || echo '?')"
elif exists "$CONFIG_DIR"; then
  # 走到这里说明还留着旧配置（--hard，或者 dry-run 没提前备份）
  if [ "$DRY_RUN" = 1 ]; then
    if [ "$HARD" = 1 ]; then
      info "[dry-run] rm -rf $CONFIG_DIR（--hard）"
    else
      info "[dry-run] mv $CONFIG_DIR $CONFIG_DIR.bak.时间戳"
    fi
    info "[dry-run] git clone --branch $BRANCH $REPO_URL $CONFIG_DIR"
  elif [ "$HARD" = 1 ]; then
    rm -rf -- "$CONFIG_DIR"
    if ! git clone --branch "$BRANCH" "$REPO_URL" "$CONFIG_DIR"; then
      die "克隆失败：$REPO_URL（检查网络/代理，私有仓库先配好 git 凭据）"
    fi
    ok "配置就位（旧配置按 --hard 已删除）"
  else
    mv "$CONFIG_DIR" "$CONFIG_DIR.bak.$(date +%Y%m%d-%H%M%S)"
    ok "旧配置已备份"
    if ! git clone --branch "$BRANCH" "$REPO_URL" "$CONFIG_DIR"; then
      die "克隆失败：$REPO_URL（检查网络/代理，私有仓库先配好 git 凭据）"
    fi
    ok "配置就位"
  fi
else
  run git clone --branch "$BRANCH" "$REPO_URL" "$CONFIG_DIR" || die "克隆失败：$REPO_URL"
  [ "$DRY_RUN" = 1 ] || ok "配置就位"
fi

# ---------------------------------------------------------------- 5. 插件

step "5/6 同步插件（lazy.nvim）"

nvim_run() {
  if [ "$CONFIG_DIR" = "$DEFAULT_CONFIG" ]; then
    "$NVIM_BIN" --headless "$@" </dev/null
  else
    "$NVIM_BIN" -u "$CONFIG_DIR/init.lua" --headless "$@" </dev/null
  fi
}

if [ "$SKIP_PLUGINS" = 1 ]; then
  info "跳过（--skip-plugins），打开 nvim 时让它自己装"
elif [ "$DRY_RUN" = 1 ]; then
  info "[dry-run] nvim --headless '+Lazy! sync' '+qa'"
else
  info "按 lazy-lock.json 拉插件，看网速，几分钟……"
  if nvim_run "+Lazy! sync" "+qa"; then
    ok "插件同步完成"
  else
    warn "同步报了错，打开 nvim 手动 :Lazy sync 再试一次"
  fi
  # 预热一次：base46 的主题缓存是刚才那轮 sync 才生成的
  nvim_run "+qa" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------- 6. 解析器

step "6/6 编译 treesitter 解析器"

PARSERS_LUA='{ "rust", "go", "lua", "vim", "vimdoc", "luadoc", "json", "yaml", "html", "css", "javascript", "typescript", "toml", "bash", "python", "markdown", "markdown_inline" }'

if [ "$SKIP_PLUGINS" = 1 ] || [ "$SKIP_PARSERS" = 1 ]; then
  info "跳过，之后打开 nvim 会自动补"
elif [ "$DRY_RUN" = 1 ]; then
  info "[dry-run] nvim --headless -c \"require('nvim-treesitter').install($PARSERS_LUA):wait()\""
else
  if nvim_run -c "lua require('nvim-treesitter').install($PARSERS_LUA, { max_jobs = 4 }):wait(900000)" -c "qa!"; then
    ok "解析器就绪"
  else
    warn "解析器编译有报错；打开 nvim 后 :TSInstall 可以补"
  fi
fi

if [ "$WITH_TOOLS" = 1 ] && [ "$SKIP_PLUGINS" = 0 ] && [ "$DRY_RUN" = 0 ]; then
  step "附加：mason 的 LSP / 格式化工具"
  # mason-tool-installer 是 VimEnter 懒加载的，headless 下先手动 load 一次命令才在
  if nvim_run -c "lua require('lazy').load({ plugins = { 'mason-tool-installer.nvim' } })" \
    -c "MasonToolsInstallSync" -c "qa!"; then
    ok "工具装好了"
  else
    warn "mason 安装有报错，之后打开 nvim 会自动重试"
  fi
fi

# ---------------------------------------------------------------- 收尾

step "收尾检查"

if [ "$DRY_RUN" = 0 ]; then
  [ -f "$CONFIG_DIR/init.lua" ] && ok "配置在 $CONFIG_DIR"
  if exists "$DATA_HOME/nvim/lazy"; then
    ok "插件目录：$(ls "$DATA_HOME/nvim/lazy" | wc -l | tr -d ' ') 个"
  fi
  for bin in rg fd node; do
    have "$bin" || warn "缺 $bin（telescope / pyright 之类会用），brew install $bin 补上"
  done
  NVIM_VER="$("$NVIM_BIN" --version | head -1 | sed -E 's/^NVIM v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
  case "$NVIM_VER" in
    0.11.* | 0.12.* | 0.13.* | 1.*) ok "Neovim $NVIM_VER 版本够用" ;;
    *) warn "Neovim $NVIM_VER 偏旧，配置要 0.11+，brew upgrade neovim" ;;
  esac
fi

cat <<EOF

${C_BOLD}干净了。${C_RESET}

  打开试试：${C_BOLD}nvim${C_RESET}
  哪里不对：${C_BOLD}:checkhealth${C_RESET} / ${C_BOLD}:Lazy${C_RESET} / ${C_BOLD}:Mason${C_RESET}
EOF

if [ -n "$BACKUP" ] && [ "$DRY_RUN" = 0 ]; then
  cat <<EOF
  想回退：${C_BOLD}rm -rf $CONFIG_DIR && mv $BACKUP $CONFIG_DIR${C_RESET}
EOF
fi
