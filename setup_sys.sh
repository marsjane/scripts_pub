#!/bin/bash
set -e

#######################################
# Args / Overrides
#######################################

FORCE_DISTRO=""

for arg in "$@"; do
    case "$arg" in
        --arch)
            FORCE_DISTRO="arch"
            ;;
        --debian)
            FORCE_DISTRO="debian"
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--arch|--debian]"
            exit 1
            ;;
    esac
done

#######################################
# Detect distro family
#######################################

detect_distro_family() {
    # 1. 强制 override
    if [ -n "$FORCE_DISTRO" ]; then
        echo "$FORCE_DISTRO"
        return
    fi

    # 2. 包管理器优先（最稳）
    if command -v pacman >/dev/null 2>&1; then
        echo "arch"
        return
    fi

    if command -v apt-get >/dev/null 2>&1; then
        echo "debian"
        return
    fi

    # 3. os-release fallback
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        for v in "$ID" $ID_LIKE; do
            case "$v" in
                arch* )
                    echo "arch"
                    return
                    ;;
                debian|ubuntu )
                    echo "debian"
                    return
                    ;;
            esac
        done
    fi

    echo "unknown"
}

DISTRO_FAMILY=$(detect_distro_family)
echo ">>> 发行版家族: $DISTRO_FAMILY"

if [ "$DISTRO_FAMILY" = "unknown" ]; then
    echo "❌ 无法识别发行版，请使用 --arch 或 --debian"
    exit 1
fi

#######################################
# sudo check
#######################################

if ! command -v sudo >/dev/null 2>&1; then
    echo "❌ sudo 未安装，请先以 root 用户安装 sudo"
    exit 1
fi

#######################################
# Package install abstraction
#######################################

install_packages() {
    case "$DISTRO_FAMILY" in
        arch)
            sudo pacman -Sy --noconfirm "$@"
            ;;
        debian)
            sudo apt-get update
            sudo apt-get install -y "$@"
            ;;
    esac
}

#######################################
# Locale setup
#######################################

echo ">>> 配置 Locale (en_US.UTF-8)..."

case "$DISTRO_FAMILY" in
    arch)
        if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
            sudo sed -i 's/^#\s*en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        fi
        sudo locale-gen
        ;;
    debian)
        install_packages locales
        sudo locale-gen en_US.UTF-8
        ;;
esac

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

#######################################
# Base tools
#######################################

echo ">>> 检查/安装基础工具..."
install_packages curl wget vim git htop zsh ca-certificates ncurses

#######################################
# Oh My Zsh
#######################################

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo ">>> 安装 Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

#######################################
# Zsh plugins
#######################################

ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions \
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting \
        "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

#######################################
# .zshrc config (idempotent)
#######################################

echo ">>> 更新 .zshrc 配置..."

ZSHRC="$HOME/.zshrc"

# Theme
if grep -q 'ZSH_THEME="robbyrussell"' "$ZSHRC"; then
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' "$ZSHRC"
fi

# Plugins
if ! grep -q "zsh-autosuggestions" "$ZSHRC"; then
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC"
fi

# Custom block
if ! grep -q "# CUSTOM_CONFIG_MARKER" "$ZSHRC"; then
    cat <<EOF >> "$ZSHRC"

# CUSTOM_CONFIG_MARKER
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
alias ll='ls -alF'
alias la='ls -A'
alias ..='cd ..'
EOF
fi

#######################################
# Vim config
#######################################

if [ ! -f "$HOME/.vimrc" ] || ! grep -q "set cursorline" "$HOME/.vimrc"; then
    cat <<EOF > "$HOME/.vimrc"
syntax on
set number
set tabstop=4
set shiftwidth=4
set expandtab
set cursorline
EOF
fi

#######################################
# Default shell
#######################################

if [[ "$SHELL" != *zsh ]]; then
    echo ">>> 更改默认 Shell 为 Zsh..."
    sudo chsh -s "$(command -v zsh)" "$USER"
fi

#######################################
# Done
#######################################

echo "----------------------------------"
echo "如果是Ghostty，考虑运行infocmp -x xterm-ghostty | ssh YOUR-SERVER -- tic -x -"
echo "✅ 初始化完成（$DISTRO_FAMILY）"
echo "💡 首次运行请执行: exec zsh 或重新登录"
echo "----------------------------------"
