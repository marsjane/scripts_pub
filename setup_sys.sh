#!/bin/bash

# --- 1. 检查并获取 sudo 权限 ---
if ! command -v sudo >/dev/null 2>&1; then
    echo "Error: sudo is not installed."
    exit 1
fi

echo "--- 正在初始化系统 (幂等支持版) ---"

# --- 2. 配置语言环境 (en_US.UTF-8) ---
if ! locale -a | grep -q "en_US.utf8"; then
    echo ">>> 配置 Locale..."
    sudo apt-get update
    sudo apt-get install -y locales
    sudo locale-gen en_US.UTF-8
fi
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# --- 3. 安装基础工具 ---
echo ">>> 检查/安装基础工具..."
sudo apt-get update
sudo apt-get install -y curl wget vim git htop zsh ca-certificates ncurses-bin

# --- 4. 配置 Ghostty Terminfo ---
if ! infocmp xterm-ghostty >/dev/null 2>&1; then
    echo ">>> 安装 Ghostty Terminfo..."
    curl -sSL https://raw.githubusercontent.com/ghostty-org/ghostty/main/terminals/ghostty.terminfo -o /tmp/ghostty.terminfo
    tic -x /tmp/ghostty.terminfo
    rm /tmp/ghostty.terminfo
fi

# --- 5. 安装 Oh My Zsh ---
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo ">>> 安装 Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# --- 6. 安装 Zsh 插件 ---
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
# 自动建议
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi
# 语法高亮
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# --- 7. 更新 .zshrc ---
echo ">>> 更新 .zshrc 配置..."
# 修改主题 (仅当是默认主题时修改)
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' "$HOME/.zshrc"

# 修改插件列表 (仅当列表中还没有新增插件时修改)
if ! grep -q "zsh-autosuggestions" "$HOME/.zshrc"; then
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"
fi

# 追加自定义别名和环境变量 (检查标记是否存在)
if ! grep -q "# CUSTOM_CONFIG_MARKER" "$HOME/.zshrc"; then
    cat <<EOF >> "$HOME/.zshrc"

# CUSTOM_CONFIG_MARKER
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
alias ll='ls -alF'
alias la='ls -A'
alias ..='cd ..'
EOF
fi

# --- 8. 配置 Vim ---
# Vim 配置通常直接覆盖即可，如果想保留手动修改，可以加判断
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

# --- 9. 更改默认 Shell ---
if [[ "$SHELL" != *zsh ]]; then
    echo ">>> 更改默认 Shell 为 Zsh..."
    sudo chsh -s "$(which zsh)" "$USER"
fi

echo "---"
echo "✅ 初始化/检查完成！"
echo "💡 如果是首次运行，请执行 'exec zsh' 或重新连接 SSH。"
