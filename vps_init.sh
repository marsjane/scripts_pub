#!/bin/bash
# ============================================================
# VPS 初始化配置脚本
# 适用系统: Ubuntu 22.04
# 执行身份: root
# 用法:
#   常规初始化:  bash vps_init.sh
#   开启BBR:     bash vps_init.sh --bbr
#   配置Shell:   bash vps_init.sh --shell
# ============================================================

set -e

# ─────────────────────────────────────────
# 颜色输出工具
# ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

confirm() {
    # 用法: confirm "提示信息" → 返回 0=yes 1=no
    local prompt="$1"
    local reply
    while true; do
        read -rp "$(echo -e "${YELLOW}${prompt} [y/n]: ${NC}")" reply
        case "$reply" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) warn "请输入 y 或 n" ;;
        esac
    done
}

# ─────────────────────────────────────────
# 分支模式: --bbr / --shell
# ─────────────────────────────────────────
if [[ "$1" == "--bbr" ]]; then
    # ── BBR 加速 ──────────────────────────
    echo ""
    info "====== BBR 加速配置 ======"
    info "当前内核版本:"
    uname -r
    if ! confirm "内核版本是否 >= 4.9，确认继续?"; then
        info "已取消 BBR 配置。"
        exit 0
    fi

    bbr_status=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null || true)
    if echo "$bbr_status" | grep -q "bbr"; then
        success "BBR 已经开启: $bbr_status"
        exit 0
    fi

    info "BBR 未开启，开始安装..."
    wget --no-check-certificate -O /opt/bbr.sh \
        https://github.com/teddysun/across/raw/master/bbr.sh
    chmod 755 /opt/bbr.sh
    bash /opt/bbr.sh

    info "重启后请执行以下命令验证 BBR 是否成功开启:"
    echo "  sysctl net.ipv4.tcp_congestion_control"
    echo "  (期望输出: net.ipv4.tcp_congestion_control = bbr)"
    exit 0
fi

if [[ "$1" == "--shell" ]]; then
    # ── Shell 环境配置 ─────────────────────
    echo ""
    info "====== Shell 环境配置 ======"
    curl -sSL https://raw.githubusercontent.com/marsjane/scripts_pub/refs/heads/main/setup_sys.sh | bash
    exit 0
fi

# ─────────────────────────────────────────
# 常规初始化流程
# ─────────────────────────────────────────

# 1. 确认 root 身份
echo ""
info "====== 步骤 1/9: 检查执行身份 ======"
if [[ "$(id -u)" -ne 0 ]]; then
    error "请以 root 身份执行此脚本！"
    exit 1
fi
success "当前为 root 用户。"

# 2. 修改 root 密码
echo ""
info "====== 步骤 2/9: 修改 root 密码 ======"
if confirm "是否需要修改 root 密码?"; then
    passwd root
    success "root 密码已修改。"
else
    info "跳过修改 root 密码。"
fi

# 3. 创建新用户
echo ""
info "====== 步骤 3/9: 创建新用户 ======"
while true; do
    read -rp "$(echo -e "${YELLOW}请输入要创建的用户名: ${NC}")" NEW_USER
    if [[ -z "$NEW_USER" ]]; then
        warn "用户名不能为空，请重新输入。"
    elif [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        warn "用户名格式不合法（只允许小写字母、数字、下划线、连字符，且必须以字母或下划线开头）。"
    else
        break
    fi
done

if id "$NEW_USER" &>/dev/null; then
    warn "用户 '$NEW_USER' 已存在，跳过创建。"
else
    adduser "$NEW_USER"
    success "用户 '$NEW_USER' 创建成功。"
fi

usermod -aG sudo "$NEW_USER"
success "用户 '$NEW_USER' 已加入 sudo 组。"

# 4. 更新 & 升级软件包
echo ""
info "====== 步骤 4/9: 更新系统软件包 ======"
apt update
apt upgrade -y
success "系统软件包更新完成。"

# 5. 检查并启用 SSH
echo ""
info "====== 步骤 5/9: 检查 SSH 服务 ======"
if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
    success "SSH 服务已在运行。"
else
    warn "SSH 服务未运行，正在安装并启用..."
    apt install -y openssh-server
    systemctl enable --now ssh
    success "SSH 服务已启动。"
fi
systemctl status sshd --no-pager || systemctl status ssh --no-pager || true

# 6. 配置 SSH 公钥认证
echo ""
info "====== 步骤 6/9: 配置 SSH 公钥认证 ======"
HOME_DIR="/home/$NEW_USER"
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

if [[ ! -d "$HOME_DIR" ]]; then
    error "用户家目录 $HOME_DIR 不存在，脚本退出。"
    exit 1
fi

echo -e "${YELLOW}请粘贴 SSH 公钥:${NC}"
IFS= read -r PUB_KEY
PUB_KEY=$(echo "$PUB_KEY" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if [[ -z "$PUB_KEY" ]]; then
    error "公钥不能为空，脚本退出。"
    exit 1
fi

mkdir -p "$SSH_DIR"
echo "${PUB_KEY} SSH-VPS" >> "$AUTH_KEYS"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"
chown -R "$NEW_USER":"$NEW_USER" "$SSH_DIR"
success "公钥已写入 $AUTH_KEYS"

# 7. SSH 安全配置
echo ""
info "====== 步骤 7/9: SSH 安全加固 ======"
while true; do
    read -rp "$(echo -e "${YELLOW}请输入要使用的 SSH 端口号 (如 2222): ${NC}")" SSH_PORT
    if [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && \
       [[ "$SSH_PORT" -ge 1 ]] && [[ "$SSH_PORT" -le 65535 ]]; then
        break
    else
        warn "端口号无效，请输入 1-65535 之间的数字。"
    fi
done

SSHD_CONFIG="/etc/ssh/sshd_config"

# 备份原始配置
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
info "已备份原始配置文件。"

# 删除可能冲突的旧配置行
sed -i '/^\s*Port\s/d'                  "$SSHD_CONFIG"
sed -i '/^\s*PermitRootLogin\s/d'       "$SSHD_CONFIG"
sed -i '/^\s*PasswordAuthentication\s/d' "$SSHD_CONFIG"

# 在文件末尾追加我们自己的配置
cat >> "$SSHD_CONFIG" <<EOF

# ── 自定义安全配置 (由 vps_init.sh 写入) ──
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication no
EOF

systemctl restart sshd || systemctl restart ssh
systemctl status sshd --no-pager || systemctl status ssh --no-pager || true
success "SSH 安全配置完成，端口: $SSH_PORT"

echo ""
warn "=========================================================="
warn "  重要提示: 请【新开一个终端窗口】，使用新端口 $SSH_PORT"
warn "  以及用户 '$NEW_USER' 和你的 SSH 密钥尝试登录。"
warn "  登录成功后再回到此窗口继续！"
warn "=========================================================="
if ! confirm "SSH 新窗口登录测试成功，继续下一步?"; then
    error "请先确认 SSH 登录成功后再继续，脚本退出。"
    exit 1
fi

# 8. 配置 UFW 防火墙
echo ""
info "====== 步骤 8/9: 配置 UFW 防火墙 ======"
apt install -y ufw

ufw default deny incoming
ufw default allow outgoing

# 询问用户需要额外开放的端口
echo ""
info "除 HTTP(80)、HTTPS(443) 和 SSH($SSH_PORT) 外，是否还需要开放其他端口?"
info "请以逗号分隔输入端口号，例如: 3000,8080,9000"
info "不需要则直接回车跳过。"
read -rp "$(echo -e "${YELLOW}额外端口 (留空跳过): ${NC}")" EXTRA_PORTS

# 开放 SSH 端口
ufw allow "${SSH_PORT}/tcp"

# 开放 HTTP / HTTPS
ufw allow http
ufw allow https

# 开放用户自定义端口
if [[ -n "$EXTRA_PORTS" ]]; then
    IFS=',' read -ra PORT_LIST <<< "$EXTRA_PORTS"
    for port in "${PORT_LIST[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            ufw allow "${port}/tcp"
            success "已开放端口: $port/tcp"
        else
            warn "无效端口格式，跳过: $port"
        fi
    done
fi

ufw --force enable
echo ""
ufw status verbose
echo ""
warn "请确认以上防火墙规则无误。"
if ! confirm "UFW 规则确认无误，继续?"; then
    warn "如需调整，请手动执行 ufw 相关命令后继续。"
fi

# 9. 安装并配置 Fail2ban
echo ""
info "====== 步骤 9/9: 安装 Fail2ban ======"
apt install -y fail2ban

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
EOF

systemctl restart fail2ban
systemctl enable fail2ban
success "Fail2ban 已启动并设置为开机自启。"

echo ""
fail2ban-client status
echo ""
fail2ban-client status sshd

if confirm "是否解封所有当前被封禁的 IP?"; then
    fail2ban-client unban --all
    success "已解封所有 IP。"
fi

# ─────────────────────────────────────────
# 完成
# ─────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  VPS 初始化配置完成！${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
info "后续可选操作（建议在新 Shell 会话中执行）："
echo "  开启 BBR 加速:    bash vps_init.sh --bbr"
echo "  配置 Shell 环境:  bash vps_init.sh --shell"
echo ""
success "祝使用愉快！"
