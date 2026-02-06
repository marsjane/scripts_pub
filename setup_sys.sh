#!/bin/bash

# --- 1. 检查 sudo 是否安装 ---
if ! command -v sudo >/dev/null 2>&1; then
    echo "Error: sudo is not installed."
    exit 1
fi

echo "--- 开始系统初始化 (Oh My Zsh 完整版) ---"

# --- 2. 配置语言环境 (en_US.UTF-8) ---
echo ">>> 配置 Locale..."
sudo apt-get update
sudo apt-get install -y locales
sudo locale-gen en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# --- 3. 安装基础依赖 ---
echo ">>> 安装基础工具及 Zsh..."
sudo apt-get install -y curl wget vim git htop zsh ca-certificates

# --- 4. 安装 Oh My Zsh (无人值守模式) ---
# 使用官方脚本，但通过参数防止它自动进入 zsh 交互模式导致脚本中断
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo ">>> 正在安装 Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# --- 5. 安装核心插件 (Autosuggestions & Highlighting) ---
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
echo ">>> 安装 Oh My Zsh 扩展插件..."

[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && \
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && \
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# --- 6. 修改 .zshrc 配置 ---
echo ">>> 更新 .zshrc 配置..."
# 1. 设置语言环境
# 2. 设置主题 (ys 是一个非常适合服务器的主题，显示清晰的路径和时间)
# 3. 启用插件
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="ys"/' "$HOME/.zshrc"
sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"

# 在文件末尾添加一些常用别名和设置
cat <<EOF >> "$HOME/.zshrc"

# 个人自定义
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
alias ll='ls -alF'
alias la='ls -A'
alias ..='cd ..'
EOF

# --- 7. 配置 Vim ---
cat <<EOF > "$HOME/.vimrc"
syntax on
set number
set tabstop=4
set shiftwidth=4
set expandtab
set cursorline
EOF

# --- 8. 更改默认 Shell ---
if [ "$SHELL" != "$(which zsh)" ]; then
    echo ">>> 更改默认 Shell 为 Zsh..."
    sudo chsh -s "$(which zsh)" "$USER"
fi

echo "---"
echo "✅ 初始化完成！"
echo "💡 请执行 'exec zsh' 或重新连接 SSH 即可享受完整 Zsh 体验。"
