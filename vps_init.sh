#!/bin/bash
# ============================================================
# VPS 初始化配置脚本
# 适用系统: Ubuntu 22.04
# 执行身份: root
# 用法:
#   常规初始化:        bash vps_init.sh
#   开启BBR:           bash vps_init.sh --bbr
#   配置Shell:         bash vps_init.sh --shell
#   Fail2ban状态检查:  bash vps_init.sh --fail2ban
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
# 分支模式: --bbr / --shell / --fail2ban
# ─────────────────────────────────────────
if [[ "$1" == "--fail2ban" ]]; then
    # ── Fail2ban 状态检查 ──────────────────
    echo ""
    info "====== Fail2ban 状态检查 ======"
    echo ""
    fail2ban-client status
    echo ""
    fail2ban-client status sshd

    if confirm "是否解封所有当前被封禁的 IP?"; then
        fail2ban-client unban --all
        success "已解封所有 IP。"
    fi
    exit 0
fi

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
if ! confirm "是否需要创建新用户?"; then
    info "跳过创建新用户。"
    while true; do
        read -rp "$(echo -e "${YELLOW}请输入用于后续配置的已有用户名: ${NC}")" NEW_USER
        if [[ -z "$NEW_USER" ]]; then
            warn "用户名不能为空，请重新输入。"
        elif [[ ! -d "/home/$NEW_USER" ]]; then
            warn "用户家目录 /home/$NEW_USER 不存在，请输入有效的用户名。"
        else
            success "将使用用户 '$NEW_USER' 进行后续配置。"
            break
        fi
    done
else
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
fi

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

sudo -u "$NEW_USER" mkdir -p "$SSH_DIR"
sudo -u "$NEW_USER" bash -c "echo '${PUB_KEY} SSH-VPS' >> '$AUTH_KEYS'"
chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"
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

# ─────────────────────────────────────────────────────────────
# 8. 配置防火墙
# ─────────────────────────────────────────────────────────────
echo ""
info "====== 步骤 8/9: 配置防火墙 ======"
echo ""
info "请选择防火墙管理方式:"
echo "  1) iptables  (推荐用于 Oracle Cloud，保留 InstanceServices 链)"
echo "  2) ufw       (适合普通 VPS，管理更简单)"
echo ""

FIREWALL_CHOICE=""
while true; do
    read -rp "$(echo -e "${YELLOW}请输入选项 [1/2]: ${NC}")" FIREWALL_CHOICE
    case "$FIREWALL_CHOICE" in
        1|2) break ;;
        *) warn "请输入 1 或 2" ;;
    esac
done

# ── 收集需要开放的端口（两种模式都需要）──────────────────────
echo ""
info "默认开放：SSH($SSH_PORT/tcp)、HTTP(80/tcp)、HTTPS(443/tcp)"
info "是否还需要开放其他端口？格式：端口号或端口/协议，逗号分隔"
info "例如: 3000,8080,53/udp，不需要则直接回车跳过。"
read -rp "$(echo -e "${YELLOW}额外端口 (留空跳过): ${NC}")" EXTRA_PORTS

# 把默认端口 + 用户自定义端口合并成一个数组
ALL_PORTS=("${SSH_PORT}/tcp" "80/tcp" "443/tcp")
if [[ -n "$EXTRA_PORTS" ]]; then
    IFS=',' read -ra EXTRA_LIST <<< "$EXTRA_PORTS"
    for p in "${EXTRA_LIST[@]}"; do
        p=$(echo "$p" | tr -d ' ')
        if [[ "$p" =~ ^[0-9]+(\/[a-z]+)?$ ]]; then
            ALL_PORTS+=("$p")
        else
            warn "无效端口格式，跳过: $p"
        fi
    done
fi

# ────────────────────────────────────────
# 模式一：iptables
# ────────────────────────────────────────
if [[ "$FIREWALL_CHOICE" == "1" ]]; then
    RULES_FILE="/etc/iptables/rules.v4"
    BACKUP_DIR="/etc/iptables/backups"

    if [[ ! -f "$RULES_FILE" ]]; then
        error "找不到 $RULES_FILE，请确认系统已有 iptables 规则文件。"
        exit 1
    fi

    # 备份
    mkdir -p "$BACKUP_DIR"
    cp "$RULES_FILE" "$BACKUP_DIR/rules.v4.$(date +%Y%m%d_%H%M%S)"
    info "已备份 iptables 规则到 $BACKUP_DIR"

    # 逐个端口写入（插到 REJECT 行之前）
    for entry in "${ALL_PORTS[@]}"; do
        # 解析 port 和 proto
        if [[ "$entry" =~ ^([0-9]+)\/([a-z]+)$ ]]; then
            PORT="${BASH_REMATCH[1]}"
            PROTO="${BASH_REMATCH[2]}"
        else
            PORT="$entry"
            PROTO="tcp"
        fi

        RULE="-A INPUT -p ${PROTO} -m state --state NEW -m ${PROTO} --dport ${PORT} -j ACCEPT"

        # 检查是否已存在该端口的规则
        if grep -qP "\-\-dport ${PORT}(?=\s|$)" "$RULES_FILE"; then
            # 已存在且是 ACCEPT → 跳过
            if grep -P "\-\-dport ${PORT}(?=\s|$)" "$RULES_FILE" | grep -q "ACCEPT"; then
                warn "端口 ${PORT}/${PROTO} 已是 ACCEPT，跳过"
                continue
            else
                # 存在但不是 ACCEPT（如 REJECT/DROP）→ 删除旧的再插入
                warn "端口 ${PORT}/${PROTO} 存在但非 ACCEPT，替换..."
                sed -i "/--dport ${PORT}\b/d" "$RULES_FILE"
            fi
        fi

        # 插入到 REJECT 兜底行之前
        if grep -q "^-A INPUT -j REJECT" "$RULES_FILE"; then
            sed -i "/^-A INPUT -j REJECT/i ${RULE}" "$RULES_FILE"
            success "已添加端口: ${PORT}/${PROTO}"
        else
            error "找不到 '-A INPUT -j REJECT' 行，无法插入端口 ${PORT}，请手动检查 $RULES_FILE"
        fi
    done

    # 加载规则
    info "正在加载 iptables 规则..."
    iptables-restore < "$RULES_FILE"
    success "iptables 规则加载完成。"

    # 打印当前 INPUT 链供用户确认
    echo ""
    info "当前 INPUT 链规则："
    echo "──────────────────────────────────────────────────────"
    iptables -L INPUT -n --line-numbers
    echo "──────────────────────────────────────────────────────"
    echo ""
    warn "请确认以上防火墙规则无误。"
    if ! confirm "iptables 规则确认无误，继续（将重启 sshd 服务）?"; then
        warn "如需调整，请手动编辑 $RULES_FILE 后执行 iptables-restore < $RULES_FILE"
    fi

# ────────────────────────────────────────
# 模式二：ufw
# ────────────────────────────────────────
elif [[ "$FIREWALL_CHOICE" == "2" ]]; then
    apt install -y ufw

    ufw default deny incoming
    ufw default allow outgoing

    for entry in "${ALL_PORTS[@]}"; do
        ufw allow "$entry"
        success "已开放端口: $entry"
    done

    ufw --force enable
    echo ""
    ufw status verbose
    echo ""
    warn "请确认以上防火墙规则无误。"
    if ! confirm "UFW 规则确认无误，继续（将重启 sshd 服务）?"; then
        warn "如需调整，请手动执行 ufw 相关命令后继续。"
    fi
fi

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
backend = systemd
EOF

systemctl restart fail2ban
systemctl enable fail2ban
success "Fail2ban 已安装并设置为开机自启。"

# ─────────────────────────────────────────
# 完成
# ─────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  VPS 初始化配置完成！${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
info "后续可选操作（建议在新 Shell 会话中执行）："
echo "  Fail2ban 状态检查: bash vps_init.sh --fail2ban"
echo "  开启 BBR 加速:     bash vps_init.sh --bbr"
echo "  配置 Shell 环境:   bash vps_init.sh --shell"
echo ""
if confirm "是否现在重启系统? (重启后请执行 --fail2ban 做状态检查)"; then
    info "系统将在 5 秒后重启..."
    sleep 5
    reboot
else
    info "跳过重启。可稍后手动执行 reboot，再运行 bash vps_init.sh --fail2ban 做检查。"
fi
echo ""
success "祝使用愉快！"
