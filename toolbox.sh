#!/bin/bash
# =============================================================
#  My Toolbox —— Debian/Ubuntu 一键工具箱（单文件）
#  版本: 0.4.0
#  许可: Apache-2.0
#  一键运行:
#    bash <(curl -sL https://raw.githubusercontent.com/baiye4857/ToolBox/main/toolbox.sh)
#  国内加速:
#    TB_MIRROR="https://ghproxy.net/" bash <(curl -sL https://raw.githubusercontent.com/baiye4857/ToolBox/main/toolbox.sh)
# =============================================================

set -o pipefail

# ------------------------- 全局配置（按需修改） -------------------------
TB_VERSION="0.4.0"
TB_CMD="tb"                                    # 安装后的命令名，可改成你自己的品牌名
TB_RAW_URL="https://raw.githubusercontent.com/baiye4857/ToolBox/main/toolbox.sh"
TB_MIRROR="${TB_MIRROR:-}"                     # 加速前缀，如 https://ghproxy.net/ ；留空直连

# ------------------------- 颜色（非终端自动降级） -------------------------
if [[ -t 1 ]]; then
    C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'
    C_CYAN='\033[36m'; C_BOLD='\033[1m'; C_RESET='\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_BOLD=''; C_RESET=''
fi

# =============================================================
#  通用工具层
# =============================================================

tb_log()   { echo -e "${C_CYAN}[*]${C_RESET} $*"; }
tb_ok()    { echo -e "${C_GREEN}[+]${C_RESET} $*"; }
tb_warn()  { echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
tb_error() { echo -e "${C_RED}[x]${C_RESET} $*" >&2; }

tb_pause() { read -r -p "按回车键继续..."; }

# 清屏：无 clear 命令或非交互环境时静默降级
tb_clear() { clear 2>/dev/null || true; }

# 用法: tb_confirm "确定要执行吗？"  → y/Y 返回 0，其余返回 1
tb_confirm() {
    local answer
    read -r -p "$1 [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

tb_has() { command -v "$1" >/dev/null 2>&1; }

# 特权功能统一入口
tb_require_root() {
    if [[ $EUID -ne 0 ]]; then
        tb_error "该功能需要 root 权限，请加 sudo 或切换到 root 后重试"
        return 1
    fi
}

# 平台门禁：当前版本只支持 apt 系
tb_check_platform() {
    if ! tb_has apt-get; then
        tb_error "当前版本只支持 Debian/Ubuntu（apt 系），暂不支持本系统"
        exit 1
    fi
}

# 用法: tb_pkg_install curl wget git
tb_pkg_install() {
    tb_require_root || return 1
    local need=() p
    for p in "$@"; do
        tb_has "$p" || need+=("$p")
    done
    [[ ${#need[@]} -eq 0 ]] && return 0
    tb_log "安装依赖: ${need[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${need[@]}"
}

tb_self_path() { readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}"; }

# 修复中断的 dpkg 事务（不杀进程，只做 configure -a）
# 来源：基于 kejilion/sh（Apache-2.0，https://github.com/kejilion/sh）
#       cn/kejilion.sh L10710–L10714 fix_dpkg 改写，去掉了 pkill -9
tb_fix_dpkg() {
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a 2>/dev/null
}

# 重启系统服务（Debian/Ubuntu 下 ssh 服务名通常为 ssh）
# 来源：基于 kejilion/sh cn/kejilion.sh L1999–L2005 restart 改写
tb_restart_service() {
    local svc
    for svc in "$@"; do
        if systemctl restart "$svc" 2>/dev/null; then
            tb_ok "服务 $svc 已重启"
            return 0
        fi
    done
    tb_error "服务重启失败: $*"
    return 1
}

# 当前时区
# 来源：基于 kejilion/sh cn/kejilion.sh L10686 current_timezone 思路改写
tb_current_timezone() {
    if tb_has timedatectl; then
        timedatectl show -p Timezone --value 2>/dev/null && return 0
    fi
    cat /etc/timezone 2>/dev/null || date +%Z
}

# 本机主网卡 IPv4
# 来源：基于 kejilion/sh cn/kejilion.sh L1849–L1853 get_local_ip 改写
tb_local_ip() {
    ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+' \
        || hostname -I 2>/dev/null | awk '{print $1}'
}

# 网卡累计流量（自动适配任意接口名，排除 lo）
# 来源：基于 kejilion/sh cn/kejilion.sh L8906–L8934 output_status 改写
tb_traffic() {
    [[ -r /proc/net/dev ]] || { echo "? ?"; return 0; }
    awk 'BEGIN { rx=0; tx=0 }
        $1 ~ /:/ && $1 !~ /^lo:/ {
            gsub(":", "", $1); rx += $2; tx += $10
        }
        END {
            split("B K M G T", u)
            i=1; r=rx; while (r >= 1024 && i < 5) { r /= 1024; i++ }
            j=1; t=tx; while (t >= 1024 && j < 5) { t /= 1024; j++ }
            printf "%.2f%s %.2f%s\n", r, u[i], t, u[j]
        }' /proc/net/dev
}

# 防火墙放行端口（ufw 优先，未启用则回退 iptables）
# 来源：基于 kejilion/sh cn/kejilion.sh L2591 open_port 改写，增加 ufw 路径
tb_fw_allow() {
    local port="$1"
    if tb_has ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
        ufw allow "${port}/tcp" >/dev/null && ufw allow "${port}/udp" >/dev/null
        tb_ok "ufw 已放行端口 $port"
        return 0
    fi
    if tb_has iptables; then
        iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null \
            || iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
        iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null \
            || iptables -I INPUT 1 -p udp --dport "$port" -j ACCEPT
        tb_ok "iptables 已放行端口 $port"
        return 0
    fi
    tb_warn "未检测到 ufw/iptables，跳过防火墙放行（请确认云厂商安全组已放行 $port）"
}

# 防火墙关闭端口
tb_fw_deny() {
    local port="$1"
    if tb_has ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
        ufw delete allow "${port}/tcp" >/dev/null 2>&1
        ufw delete allow "${port}/udp" >/dev/null 2>&1
        tb_ok "ufw 已移除端口 $port 规则"
        return 0
    fi
    if tb_has iptables; then
        iptables -D INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -D INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
        tb_ok "iptables 已移除端口 $port 放行规则"
        return 0
    fi
    tb_warn "未检测到 ufw/iptables，跳过防火墙操作"
}

# 统一修改 sshd_config 中的键（不存在则追加）
tb_sshd_set() {
    local key="$1" val="$2" cfg="/etc/ssh/sshd_config"
    if grep -Eq "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+" "$cfg"; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+.*|${key} ${val}|" "$cfg"
    else
        echo "${key} ${val}" >> "$cfg"
    fi
}

# =============================================================
#  自安装 / 自更新
# =============================================================

# 把当前脚本安装到 /usr/local/bin/$TB_CMD
tb_self_install() {
    tb_require_root || return 1
    local src target
    src="$(tb_self_path)"
    target="/usr/local/bin/$TB_CMD"
    if [[ ! -e "$src" ]]; then
        tb_error "找不到脚本来源（$src），安装中止"
        return 1
    fi
    cp -f -- "$src" "$target"
    chmod 755 "$target"
    tb_ok "已安装: $target"
    tb_log "现在可以直接输入 ${C_BOLD}$TB_CMD${C_RESET} 启动工具箱"
}

# 从 GitHub RAW 拉取最新版并替换已安装命令
tb_self_update() {
    local url="$TB_RAW_URL" tmp target
    [[ -n "$TB_MIRROR" ]] && url="${TB_MIRROR}${TB_RAW_URL}"

    if [[ "$TB_RAW_URL" == *CHANGE_ME* ]]; then
        tb_error "请先在脚本顶部填写 TB_RAW_URL（你的 GitHub RAW 地址）"
        return 1
    fi

    tb_pkg_install curl || return 1
    tb_log "拉取最新版本: $url"
    tmp="$(mktemp)" || return 1

    if ! curl -fsSL --max-time 60 -o "$tmp" "$url"; then
        tb_error "下载失败，请检查网络或镜像后重试"
        rm -f -- "$tmp"; return 1
    fi
    if [[ ! -s "$tmp" ]] || ! head -1 "$tmp" | grep -q '^#!.*bash'; then
        tb_error "内容校验失败（要求非空且首行为 bash shebang），已拒绝替换"
        rm -f -- "$tmp"; return 1
    fi

    chmod +x "$tmp"
    target="/usr/local/bin/$TB_CMD"
    if [[ -f "$target" ]]; then
        cp -f -- "$target" "${target}.bak"
        tb_log "旧版本已备份: ${target}.bak"
    fi
    mv -f -- "$tmp" "$target"
    chmod 755 "$target"
    tb_ok "已更新到最新版本（当前文件版本以新版内 TB_VERSION 为准）"
}

# =============================================================
#  功能区
# -------------------------------------------------------------
#  下列函数改写自 kejilion/sh（Apache-2.0），归属见各函数头注释；
#  未搬运 send_stats 埋点、自改脚本、静默更新 crontab 等逻辑。
# =============================================================

# -------------------------------------------------------------
# 1. 系统信息查询
# 来源：基于 kejilion/sh cn/kejilion.sh L14301–L14396 linux_info 改写
# -------------------------------------------------------------
tb_feat_info() {
    [[ -r /etc/os-release ]] && . /etc/os-release
    tb_clear
    tb_log "正在收集系统信息……"

    local cpu_model cpu_cores cpu_usage mem disk load tz now uptime_str
    local congestion qdisc tcp_n udp_n swapline traffic_line rx tx
    local dns_list geo_line=""

    cpu_model="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
    cpu_cores="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)"
    if [[ -r /proc/stat ]]; then
        cpu_usage="$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else printf "%.0f", (($2+$4-u1)*100/(t-t1))}' \
            <(grep '^cpu ' /proc/stat) <(sleep 1; grep '^cpu ' /proc/stat))"
    fi

    if tb_has free; then
        mem="$(free -h | awk 'NR==2{print $3 "/" $2 " (" $5 " 可用)"}')"
        swapline="$(free -h | awk 'NR==3{print $3 "/" $2}')"
    fi
    if tb_has df; then
        disk="$(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')"
    fi
    if tb_has uptime; then
        load="$(uptime | sed 's/^.*load average: //')"
    fi
    tz="$(tb_current_timezone)"
    now="$(date '+%Y-%m-%d %H:%M:%S')"
    if tb_has uptime; then
        uptime_str="$(uptime -p 2>/dev/null | sed 's/^up //')"
    fi

    congestion="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    tcp_n="$(ss -t 2>/dev/null | tail -n +2 | wc -l)"
    udp_n="$(ss -u 2>/dev/null | tail -n +2 | wc -l)"

    traffic_line="$(tb_traffic)"; rx="${traffic_line%% *}"; tx="${traffic_line##* }"
    if [[ -r /etc/resolv.conf ]]; then
        dns_list="$(awk '/^nameserver/{printf "%s ", $2}' /etc/resolv.conf)"
    fi

    # 地理信息为在线查询，失败不影响其余输出
    if tb_has curl; then
        local geo
        geo="$(curl -fsS --max-time 5 ipinfo.io/json 2>/dev/null)"
        if [[ -n "$geo" ]]; then
            geo_line="$(echo "$geo" | awk -F'"' '/"country"/{c=$4} /"city"/{ci=$4} /"org"/{o=$4}
                END{printf "%s %s | %s", c, ci, o}')"
        fi
    fi

    tb_clear
    echo -e "${C_BOLD}系统信息查询${C_RESET}"
    echo "---------------------------------------------"
    echo "主机名     : $(hostname)"
    echo "系统版本   : ${PRETTY_NAME:-unknown}"
    echo "内核版本   : $(uname -r)"
    echo "架构       : $(uname -m)"
    echo "---------------------------------------------"
    echo "CPU 型号   : ${cpu_model:-未知}"
    echo "CPU 核心   : $cpu_cores"
    echo "CPU 占用   : ${cpu_usage:-?}%"
    echo "系统负载   : $load"
    echo "TCP|UDP    : $tcp_n | $udp_n"
    echo "---------------------------------------------"
    echo "物理内存   : $mem"
    echo "虚拟内存   : $swapline"
    echo "根分区     : $disk"
    echo "---------------------------------------------"
    echo "累计接收   : $rx"
    echo "累计发送   : $tx"
    echo "拥塞算法   : ${congestion:-?} / ${qdisc:-?}"
    echo "---------------------------------------------"
    [[ -n "$geo_line" ]] && echo "IP 归属   : $geo_line"
    echo "本机 IPv4  : $(tb_local_ip 2>/dev/null)"
    echo "DNS        : ${dns_list:-（未配置）}"
    echo "系统时间   : $tz  $now"
    echo "运行时长   : $uptime_str"
    echo "---------------------------------------------"
}

# -------------------------------------------------------------
# 2. 系统清理（apt 路径）
# 来源：基于 kejilion/sh cn/kejilion.sh L10744–L10805 linux_clean 改写，
#       仅保留 apt 分支，journal 收缩改为 200M 且需确认
# -------------------------------------------------------------
tb_feat_clean() {
    tb_require_root || return 1
    tb_log "开始系统清理……"
    tb_fix_dpkg

    DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
    DEBIAN_FRONTEND=noninteractive apt-get clean -y
    DEBIAN_FRONTEND=noninteractive apt-get autoclean -y
    tb_ok "无用依赖与 apt 缓存已清理"

    if tb_has journalctl; then
        if tb_confirm "是否将 systemd 日志收缩到 200M 以内？"; then
            journalctl --rotate 2>/dev/null
            journalctl --vacuum-size=200M 2>/dev/null
            tb_ok "系统日志已收缩"
        fi
    fi
    tb_ok "清理完成"
}

# -------------------------------------------------------------
# 3. 测试脚本合集（薄封装：菜单映射到各上游项目的一键命令）
# 来源：基于 kejilion/sh cn/kejilion.sh L17571–L17716 linux_test 改写；
#       已失效的 git.io 链接（besttrace/superspeed）用存活项目替代
# -------------------------------------------------------------
tb_feat_test_menu() {
    while true; do
        tb_clear
        echo -e "${C_BOLD}测试脚本合集${C_RESET}"
        echo "------------------------"
        echo "IP 及解锁状态检测"
        echo " 1. ChatGPT 解锁状态检测"
        echo " 2. Region 流媒体解锁测试"
        echo " 3. yeahwu 流媒体解锁检测"
        echo " 4. IP 质量体检（IP.Check.Place）"
        echo "------------------------"
        echo "网络线路测速"
        echo "11. mtr_trace 三网回程线路测试"
        echo "12. NextTrace 快速回程测试"
        echo "13. NextTrace 指定 IP 回程测试"
        echo "14. ludashi 三网线路测试"
        echo "15. i-abc 多功能测速"
        echo "16. NetQuality 网络质量体检"
        echo "17. TcpQuality TCP 重传探测"
        echo "------------------------"
        echo "硬件性能测试"
        echo "21. YABS 性能测试"
        echo "22. GB5 CPU 性能测试"
        echo "------------------------"
        echo "综合性测试"
        echo "31. bench 性能测试"
        echo "32. spiritLHLS 融合怪测评"
        echo "33. NodeQuality 融合怪测评"
        echo "------------------------"
        echo " 0. 返回主菜单"
        echo "------------------------"
        read -r -p "请输入选择: " c || return 0
        tb_pkg_install curl ca-certificates >/dev/null 2>&1 || true
        case "$c" in
            1)  bash <(curl -Ls https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh) ;;
            2)  bash <(curl -L -s https://check.unlock.media) ;;
            3)  wget -qO- https://raw.githubusercontent.com/yeahwu/check/main/check.sh | bash ;;
            4)  bash <(curl -Ls https://IP.Check.Place) ;;
            11) curl -s https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh | bash ;;
            12) curl -s nxtrace.org/nt | bash; nexttrace --fast-trace --tcp 2>/dev/null ;;
            13)
                echo "参考 IP：北京电信 219.141.136.12 / 上海联通 210.22.97.1 / 广州移动 120.196.165.24"
                read -r -p "输入目标 IP: " tip
                curl -s nxtrace.org/nt | bash
                nexttrace "$tip" 2>/dev/null
                ;;
            14) curl -sSf https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh | sh ;;
            15) bash <(curl -sL https://raw.githubusercontent.com/i-abc/Speedtest/main/speedtest.sh) ;;
            16) bash <(curl -sL https://Net.Check.Place) ;;
            17) bash <(curl -sL https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh) ;;
            21) curl -sL yabs.sh | bash -s -- -i -5 ;;
            22) bash <(curl -fsSL https://raw.githubusercontent.com/i-abc/GB5/main/gb5-test.sh) ;;
            31) curl -Lso- bench.sh | bash ;;
            32)
                local tmpf; tmpf="$(mktemp)"
                curl -fsSL https://raw.githubusercontent.com/spiritLHLS/ecs/main/ecs.sh -o "$tmpf" \
                    && chmod +x "$tmpf" && bash "$tmpf"; rm -f "$tmpf"
                ;;
            33) bash <(curl -sL https://run.NodeQuality.com) ;;
            0)  return 0 ;;
            *)  tb_warn "无效输入"; sleep 1 ;;
        esac
        tb_pause
    done
}

# -------------------------------------------------------------
# 系统工具 6. 修改 SSH 端口
# 来源：基于 kejilion/sh cn/kejilion.sh L11281–L11299 new_ssh_port 改写，
#       增加端口校验、sshd -t 校验与监听确认，防火墙不再删除其它工具
# -------------------------------------------------------------
tb_feat_ssh_port() {
    tb_require_root || return 1
    local cfg="/etc/ssh/sshd_config" port old_port
    [[ -f "$cfg" ]] || { tb_error "未找到 $cfg"; return 1; }

    old_port="$(grep -E '^[[:space:]]*Port[[:space:]]+' "$cfg" | awk '{print $2}' | tail -1)"
    old_port="${old_port:-22}"
    echo "当前 SSH 端口: $old_port"
    read -r -p "请输入新端口 (1-65535): " port || return 0
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) \
        || { tb_error "端口号无效"; return 1; }
    [[ "$port" == "$old_port" ]] && { tb_warn "新旧端口相同，无需修改"; return 0; }

    tb_warn "修改端口有误可能导致 SSH 失联，确认已在云厂商安全组放行 $port"
    tb_confirm "确认修改？" || return 1

    cp -f "$cfg" "${cfg}.tb.bak"
    sed -i -E '/^[[:space:]]*#?[[:space:]]*Port[[:space:]]+[0-9]+/d' "$cfg"
    sed -i "1i Port $port" "$cfg"
    if ! sshd -t 2>/dev/null; then
        tb_error "sshd 配置校验失败，已恢复备份"
        cp -f "${cfg}.tb.bak" "$cfg"; return 1
    fi

    tb_fw_allow "$port"
    tb_restart_service ssh sshd || { tb_error "SSH 重启失败，请用 ${cfg}.tb.bak 恢复"; return 1; }
    sleep 1

    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$"; then
        tb_ok "SSH 已在新端口 $port 监听，请开新会话验证后再关闭本会话"
    else
        tb_error "未检测到 $port 监听，请立即检查 sshd 状态"
        return 1
    fi
    if tb_confirm "新会话验证成功后，是否关闭旧端口 $old_port 的防火墙放行？"; then
        tb_fw_deny "$old_port"
    fi
}

# -------------------------------------------------------------
# 系统工具 7. 优化 DNS
# 来源：基于 kejilion/sh cn/kejilion.sh L11198–L11240 set_dns_ui 与
#       L10840–L10861 set_dns 改写；不使用 chattr 锁定，避免后续维护困难
# -------------------------------------------------------------
tb_feat_dns() {
    tb_require_root || return 1
    local rc="/etc/resolv.conf" d1 d2
    while true; do
        tb_clear
        echo "优化 DNS 地址"
        echo "------------------------"
        echo "当前配置:"; cat "$rc" 2>/dev/null
        echo "------------------------"
        echo "1. 国外预设: 1.1.1.1 / 8.8.8.8"
        echo "2. 国内预设: 223.5.5.5 / 119.29.29.29"
        echo "3. 手动输入两个 DNS"
        echo "0. 返回"
        read -r -p "请选择: " c || return 0
        case "$c" in
            1) d1="1.1.1.1"; d2="8.8.8.8" ;;
            2) d1="223.5.5.5"; d2="119.29.29.29" ;;
            3)
                read -r -p "主 DNS: " d1
                read -r -p "备 DNS: " d2
                ;;
            0) return 0 ;;
            *) continue ;;
        esac
        [[ -n "$d1" ]] || { tb_error "DNS 不能为空"; continue; }
        cp -f "$rc" "${rc}.tb.bak" 2>/dev/null
        {
            echo "# 由 $TB_CMD 写入，$(date '+%F %T')"
            echo "nameserver $d1"
            [[ -n "$d2" ]] && echo "nameserver $d2"
        } > "$rc"
        tb_ok "DNS 已更新"
        tb_pause
    done
}

# -------------------------------------------------------------
# 系统工具 10. IPv4/IPv6 优先级
# 来源：基于 kejilion/sh cn/kejilion.sh L3234–L3238 prefer_ipv4 改写；
#       第三方 jhb.ovh IPv6 修复分支未搬运（不可审计的外部脚本）
# -------------------------------------------------------------
tb_feat_ip_mode() {
    tb_require_root || return 1
    local gai="/etc/gai.conf"
    echo "1. IPv4 优先"
    echo "2. IPv6 优先（系统默认，删除 gai.conf 覆盖）"
    read -r -p "请选择: " c || return 0
    case "$c" in
        1)
            grep -q '^precedence ::ffff:0:0/96  100' "$gai" 2>/dev/null \
                || echo 'precedence ::ffff:0:0/96  100' >> "$gai"
            tb_ok "已切换为 IPv4 优先，重新连接生效"
            ;;
        2)
            if [[ -f "$gai" ]]; then
                sed -i '/^precedence ::ffff:0:0\/96/d' "$gai"
                tb_ok "已移除 IPv4 优先规则，恢复系统默认"
            else
                tb_warn "当前已是默认配置"
            fi
            ;;
        *) tb_warn "无效选择" ;;
    esac
}

# -------------------------------------------------------------
# 系统工具 11. 查看端口占用
# 来源：基于 kejilion/sh cn/kejilion.sh L35404–L35410 内联命令改写
# -------------------------------------------------------------
tb_feat_ports() {
    if ! tb_has ss; then
        tb_pkg_install iproute2 || return 1
    fi
    ss -tulnape
}

# -------------------------------------------------------------
# 系统工具 12. 虚拟内存
# 来源：基于 kejilion/sh cn/kejilion.sh L3067–L3096 add_swap 改写，
#       去掉对旧 swap 分区的 wipefs，增加 fallocate 失败时的 dd 回退
# -------------------------------------------------------------
tb_feat_swap() {
    tb_require_root || return 1
    local size
    read -r -p "请输入 swap 大小（MB，建议为内存的 1–2 倍）: " size || return 0
    [[ "$size" =~ ^[0-9]+$ ]] && (( size >= 512 )) \
        || { tb_error "请输入不小于 512 的数字"; return 1; }

    if swapon --show 2>/dev/null | grep -q '/swapfile'; then
        tb_log "停用并删除旧 /swapfile"
        swapoff /swapfile 2>/dev/null
    fi
    rm -f /swapfile
    if ! fallocate -l "${size}M" /swapfile 2>/dev/null; then
        tb_warn "fallocate 不可用，改用 dd（可能较慢）"
        dd if=/dev/zero of=/swapfile bs=1M count="$size" status=none
    fi
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
    echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    tb_ok "swap 已设置为 ${size}MB 并写入 /etc/fstab"
}

# -------------------------------------------------------------
# 系统工具 18. 修改主机名
# 来源：基于 kejilion/sh cn/kejilion.sh L35520–L35546 内联逻辑改写
# -------------------------------------------------------------
tb_feat_hostname() {
    tb_require_root || return 1
    local old new
    old="$(hostname)"
    echo "当前主机名: $old"
    read -r -p "新主机名: " new
    [[ "$new" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] \
        || { tb_error "主机名只能包含字母、数字、点和连字符"; return 1; }
    [[ "$new" == "$old" ]] && { tb_warn "主机名未变化"; return 0; }

    hostnamectl set-hostname "$new"
    [[ -f /etc/hostname ]] && echo "$new" > /etc/hostname
    if [[ -f /etc/hosts ]]; then
        sed -i -E "s|^(127\.0\.1\.1[[:space:]]+).*|\1${new}|" /etc/hosts
        sed -i -E "s|^(127\.0\.0\.1[[:space:]]+)${old}([[:space:]]|$)|\1${new}\2|" /etc/hosts
        sed -i -E "s|^(::1[[:space:]]+)${old}([[:space:]]|$)|\1${new}\2|" /etc/hosts
    fi
    tb_ok "主机名已改为 $new，重新连接会话生效"
}

# -------------------------------------------------------------
# 系统工具 19. 切换更新源（linuxmirrors 薄封装）
# 来源：基于 kejilion/sh cn/kejilion.sh L1650–L1660 run_linuxmirrors_manual 改写
# -------------------------------------------------------------
tb_feat_mirror() {
    tb_require_root || return 1
    tb_pkg_install curl ca-certificates || return 1
    local tmp args
    echo "1. 默认交互模式"
    echo "2. 教育网模式 (--edu)"
    echo "3. 海外模式 (--abroad)"
    read -r -p "请选择: " c || return 0
    case "$c" in
        1) args="" ;;
        2) args="--edu" ;;
        3) args="--abroad" ;;
        *) tb_warn "无效选择"; return 1 ;;
    esac
    tmp="$(mktemp)" || return 1
    if curl -fsSL --max-time 30 -o "$tmp" https://linuxmirrors.cn/main.sh; then
        chmod +x "$tmp"
        # shellcheck disable=SC2086
        bash "$tmp" $args
    else
        tb_error "下载 linuxmirrors 脚本失败"
    fi
    rm -f "$tmp"
}

# -------------------------------------------------------------
# 系统工具 22. SSH 防御（fail2ban 简化实现）
# 来源：基于 kejilion/sh cn/kejilion.sh L30158–L30213 fail2ban_panel 改写，
#       用 apt 安装 + 自写 jail.local 替代其 f2b_* 系列辅助函数
# -------------------------------------------------------------
tb_feat_f2b() {
    tb_require_root || return 1
    local jail="/etc/fail2ban/jail.local"
    while true; do
        tb_clear
        echo "SSH 防御（fail2ban）"
        echo "------------------------"
        if tb_has fail2ban-client && systemctl is-active --quiet fail2ban 2>/dev/null; then
            echo "状态: $(C_GREEN)运行中$(C_RESET)"
        else
            echo "状态: 未安装/未运行"
        fi
        echo "1. 安装并启用（默认 10 分钟内失败 5 次封禁 1 小时）"
        echo "2. 查看 SSH 拦截状态"
        echo "3. 查看拦截日志"
        echo "4. 手动解封 IP"
        echo "9. 卸载 fail2ban"
        echo "0. 返回"
        read -r -p "请选择: " c || return 0
        case "$c" in
            1)
                tb_pkg_install fail2ban || return 1
                cat > "$jail" <<'JAIL'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
JAIL
                systemctl enable --now fail2ban >/dev/null 2>&1
                systemctl restart fail2ban
                tb_ok "fail2ban 已启用"
                ;;
            2) fail2ban-client status sshd 2>/dev/null || tb_warn "fail2ban 未运行" ;;
            3) tail -n 40 /var/log/fail2ban.log 2>/dev/null || tb_warn "暂无日志" ;;
            4)
                read -r -p "输入要解封的 IP: " ip
                fail2ban-client set sshd unbanip "$ip" 2>/dev/null \
                    && tb_ok "已解封 $ip" || tb_error "解封失败"
                ;;
            9)
                tb_confirm "确认卸载 fail2ban？" || continue
                systemctl disable --now fail2ban 2>/dev/null
                DEBIAN_FRONTEND=noninteractive apt-get purge -y fail2ban
                rm -rf /etc/fail2ban
                tb_ok "已卸载"
                ;;
            0) return 0 ;;
            *) tb_warn "无效输入" ;;
        esac
        tb_pause
    done
}

# -------------------------------------------------------------
# 系统工具 24. 用户密钥登录
# 来源：基于 kejilion/sh cn/kejilion.sh L11574–L11625 sshkey_panel 与
#       L11390–L11402 sshkey_on 改写
# -------------------------------------------------------------
tb_feat_sshkey() {
    tb_require_root || return 1
    local keyfile="/root/.ssh/tb_sshkey"
    while true; do
        tb_clear
        echo "用户密钥登录"
        echo "------------------------"
        echo "1. 生成新 ed25519 密钥对并授权"
        echo "2. 粘贴已有公钥"
        echo "3. 从 GitHub 用户名导入公钥"
        echo "4. 从 URL 导入公钥"
        echo "5. 查看已授权公钥"
        echo "6. 开启仅密钥登录（关闭密码登录）"
        echo "7. 恢复密码登录"
        echo "0. 返回"
        read -r -p "请选择: " c || return 0
        case "$c" in
            1)
                mkdir -p /root/.ssh; chmod 700 /root/.ssh
                ssh-keygen -t ed25519 -f "$keyfile" -N "" -C "tb-generated"
                cat "${keyfile}.pub" >> /root/.ssh/authorized_keys
                chmod 600 /root/.ssh/authorized_keys
                echo "------------------------"
                tb_ok "密钥已生成，私钥内容如下，请立即保存并妥善保管："
                cat "$keyfile"
                ;;
            2)
                mkdir -p /root/.ssh; chmod 700 /root/.ssh; touch /root/.ssh/authorized_keys
                echo "粘贴公钥后回车，再输入空行结束："
                local line
                while read -r line; do
                    [[ -z "$line" ]] && break
                    echo "$line" >> /root/.ssh/authorized_keys
                done
                chmod 600 /root/.ssh/authorized_keys
                tb_ok "公钥已写入"
                ;;
            3)
                read -r -p "GitHub 用户名: " ghuser
                curl -fsSL --max-time 15 "https://github.com/${ghuser}.keys" \
                    >> /root/.ssh/authorized_keys 2>/dev/null \
                    && tb_ok "已导入 $ghuser 的公钥" || tb_error "导入失败"
                chmod 600 /root/.ssh/authorized_keys
                ;;
            4)
                read -r -p "公钥 URL: " u
                curl -fsSL --max-time 15 "$u" >> /root/.ssh/authorized_keys 2>/dev/null \
                    && tb_ok "已导入" || tb_error "导入失败"
                chmod 600 /root/.ssh/authorized_keys
                ;;
            5) cat /root/.ssh/authorized_keys 2>/dev/null || tb_warn "暂无授权公钥" ;;
            6)
                tb_warn "开启前请确认新密钥会话能登录，否则会被锁在门外"
                tb_confirm "确认关闭密码登录？" || continue
                cp -f /etc/ssh/sshd_config /etc/ssh/sshd_config.tb.bak
                tb_sshd_set PubkeyAuthentication yes
                tb_sshd_set PasswordAuthentication no
                tb_sshd_set PermitRootLogin prohibit-password
                if sshd -t; then tb_restart_service ssh sshd && tb_ok "已切换为仅密钥登录"
                else tb_error "sshd 校验失败，已回滚"; cp -f /etc/ssh/sshd_config.tb.bak /etc/ssh/sshd_config; fi
                ;;
            7)
                tb_sshd_set PasswordAuthentication yes
                tb_sshd_set PermitRootLogin yes
                sshd -t && tb_restart_service ssh sshd && tb_ok "已恢复密码登录"
                ;;
            0) return 0 ;;
            *) tb_warn "无效输入" ;;
        esac
        tb_pause
    done
}

# -------------------------------------------------------------
# 系统工具 26. 修复 OpenSSH 高危漏洞
# 来源：kejilion 原版下载第三方编译升级脚本（L35941–L35948）；
#       Debian/Ubuntu 下改用发行版安全仓库升级 openssh，更可控
# -------------------------------------------------------------
tb_feat_ssh_fix() {
    tb_require_root || return 1
    tb_log "当前 OpenSSH 版本:"
    ssh -V 2>&1
    tb_confirm "将通过 apt 安全仓库升级 openssh-server/client，继续？" || return 1
    tb_fix_dpkg
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y openssh-server openssh-client
    if sshd -t 2>/dev/null; then
        systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null
        tb_ok "升级完成，升级后版本:"; ssh -V 2>&1
    else
        tb_error "sshd 配置校验失败，未重启服务，请人工检查"
    fi
}

# -------------------------------------------------------------
# 系统工具 28. 内核参数优化（自写 sysctl 模板）
# 来源：基于 kejilion/sh cn/kejilion.sh L13079–L13150 Kernel_optimize 改写，
#       模板参数为自写，未搬运其网络自动调优外部脚本
# -------------------------------------------------------------
TB_SYSCTL_FILE="/etc/sysctl.d/99-tb-optimize.conf"

tb_feat_tune() {
    tb_require_root || return 1
    while true; do
        tb_clear
        echo "内核参数优化"
        echo "当前模式: $(grep '^# 模式' "$TB_SYSCTL_FILE" 2>/dev/null | sed 's/^# 模式: //' || echo '未优化')"
        echo "1. 高性能模式（激进网络/内存参数）"
        echo "2. 均衡模式（通用场景）"
        echo "3. 网站模式（高并发连接）"
        echo "4. 还原默认（删除本工具写入的配置）"
        echo "0. 返回"
        read -r -p "请选择: " c || return 0
        case "$c" in
            1)
                cat > "$TB_SYSCTL_FILE" <<'SYS'
# 模式: 高性能
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_max_tw_buckets = 144000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
SYS
                ;;
            2)
                cat > "$TB_SYSCTL_FILE" <<'SYS'
# 模式: 均衡
vm.swappiness = 30
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
SYS
                ;;
            3)
                cat > "$TB_SYSCTL_FILE" <<'SYS'
# 模式: 网站
vm.swappiness = 20
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.netfilter.nf_conntrack_max = 1048576
SYS
                ;;
            4)
                rm -f "$TB_SYSCTL_FILE"
                sysctl --system >/dev/null 2>&1
                tb_ok "已移除本工具配置并重新加载系统默认"
                tb_pause; continue
                ;;
            0) return 0 ;;
            *) tb_warn "无效输入"; continue ;;
        esac
        if sysctl -p "$TB_SYSCTL_FILE" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1; then
            tb_ok "参数已生效"
        else
            tb_warn "部分参数当前内核不支持，已跳过（不影响其余参数）"
        fi
        tb_pause
    done
}

# -------------------------------------------------------------
# 系统工具 31. 切换系统语言
# 来源：基于 kejilion/sh cn/kejilion.sh L13209–L13250 linux_language 与
#       update_locale 改写，仅保留 Debian/Ubuntu 分支
# -------------------------------------------------------------
tb_feat_lang() {
    tb_require_root || return 1
    local lang loc
    echo "1. 英文 en_US.UTF-8"
    echo "2. 简体中文 zh_CN.UTF-8"
    echo "3. 繁体中文 zh_TW.UTF-8"
    read -r -p "请选择: " c || return 0
    case "$c" in
        1) lang="en_US.UTF-8"; loc="en_US.UTF-8" ;;
        2) lang="zh_CN.UTF-8"; loc="zh_CN.UTF-8" ;;
        3) lang="zh_TW.UTF-8"; loc="zh_TW.UTF-8" ;;
        *) tb_warn "无效选择"; return 1 ;;
    esac
    tb_pkg_install locales || return 1
    sed -i -E "s|^[[:space:]]*#?[[:space:]]*${loc} UTF-8|${loc} UTF-8|" /etc/locale.gen
    locale-gen
    echo "LANG=${lang}" > /etc/default/locale
    tb_ok "系统语言已切换为 $lang，重新连接 SSH 生效"
}

# -------------------------------------------------------------
# 系统工具 32. 命令行美化
# 来源：基于 kejilion/sh cn/kejilion.sh L13264–L13380 shell_bianse 改写，
#       写入位置改为 ~/.bashrc，并用标记行管理以便干净还原
# -------------------------------------------------------------
tb_feat_ps1() {
    local rc_file="${HOME}/.bashrc"
    [[ -f "$rc_file" ]] || { touch "$rc_file"; }
    while true; do
        tb_clear
        echo "命令行美化（重新连接后生效）"
        echo "1. 绿蓝红   2. 紫青黄   3. 红绿蓝"
        echo "4. 青黄白   5. 白红绿   6. 黄蓝紫"
        echo "7. 还原默认 PS1"
        echo "0. 返回"
        read -r -p "请选择: " c || return 0
        local ps1line=""
        case "$c" in
            1) ps1line="PS1='\[\033[1;32m\]\u\[\033[0m\]@\[\033[1;34m\]\h\[\033[0m\] \[\033[1;31m\]\w\[\033[0m\] # '" ;;
            2) ps1line="PS1='\[\033[1;35m\]\u\[\033[0m\]@\[\033[1;36m\]\h\[\033[0m\] \[\033[1;33m\]\w\[\033[0m\] # '" ;;
            3) ps1line="PS1='\[\033[1;31m\]\u\[\033[0m\]@\[\033[1;32m\]\h\[\033[0m\] \[\033[1;34m\]\w\[\033[0m\] # '" ;;
            4) ps1line="PS1='\[\033[1;36m\]\u\[\033[0m\]@\[\033[1;33m\]\h\[\033[0m\] \[\033[1;37m\]\w\[\033[0m\] # '" ;;
            5) ps1line="PS1='\[\033[1;37m\]\u\[\033[0m\]@\[\033[1;31m\]\h\[\033[0m\] \[\033[1;32m\]\w\[\033[0m\] # '" ;;
            6) ps1line="PS1='\[\033[1;33m\]\u\[\033[0m\]@\[\033[1;34m\]\h\[\033[0m\] \[\033[1;35m\]\w\[\033[0m\] # '" ;;
            7)
                sed -i '/# tb-ps1-begin/,/# tb-ps1-end/d' "$rc_file"
                tb_ok "已移除自定义 PS1"
                tb_pause; continue
                ;;
            0) return 0 ;;
            *) tb_warn "无效输入"; continue ;;
        esac
        sed -i '/# tb-ps1-begin/,/# tb-ps1-end/d' "$rc_file"
        {
            echo "# tb-ps1-begin"
            echo "$ps1line"
            echo "# tb-ps1-end"
        } >> "$rc_file"
        tb_ok "配色已写入 $rc_file"
        tb_pause
    done
}

# -------------------------------------------------------------
# 系统工具 34. 系统备份与恢复
# 来源：基于 kejilion/sh cn/kejilion.sh L13509–L13530 linux_backup 及
#       create_backup/restore_backup/list_backups/delete_backup 改写
# -------------------------------------------------------------
TB_BACKUP_DIR="/backups"

tb_feat_backup() {
    tb_require_root || return 1
    mkdir -p "$TB_BACKUP_DIR"
    while true; do
        tb_clear
        echo "系统备份与恢复（备份目录 $TB_BACKUP_DIR）"
        echo "------------------------"
        ls -1 "$TB_BACKUP_DIR" 2>/dev/null | sed 's/^/  /'
        echo "------------------------"
        echo "1. 创建备份   2. 恢复备份   3. 删除备份"
        echo "0. 返回"
        read -r -p "请选择: " c || return 0
        case "$c" in
            1)
                tb_pkg_install tar || return 1
                local paths name stamp
                echo "示例：/etc /home/root ；直接回车默认备份 /etc /home /root"
                read -r -p "备份目录（空格分隔）: " paths
                if [[ -z "$paths" ]]; then
                    paths="/etc /home /root"
                fi
                stamp="$(date +%Y%m%d%H%M%S)"
                name="backup_${stamp}.tar.gz"
                tb_log "正在打包: $paths"
                # shellcheck disable=SC2086
                tar -czf "${TB_BACKUP_DIR}/${name}" $paths \
                    && tb_ok "备份完成: ${TB_BACKUP_DIR}/${name}" || tb_error "备份失败"
                ;;
            2)
                local b
                read -r -p "输入要恢复的备份文件名: " b
                [[ -f "${TB_BACKUP_DIR}/${b}" ]] || { tb_error "文件不存在"; tb_pause; continue; }
                tb_warn "恢复会按归档内路径覆盖系统文件，错误的备份可能导致系统异常"
                tb_confirm "确认恢复 ${b}？" || continue
                tar -xzvf "${TB_BACKUP_DIR}/${b}" -C /
                tb_ok "恢复完成"
                ;;
            3)
                local b
                read -r -p "输入要删除的备份文件名: " b
                if [[ -f "${TB_BACKUP_DIR}/${b}" ]]; then
                    rm -f -- "${TB_BACKUP_DIR}/${b}" && tb_ok "已删除 $b"
                else
                    tb_error "文件不存在"
                fi
                ;;
            0) return 0 ;;
            *) tb_warn "无效输入" ;;
        esac
        tb_pause
    done
}

# -------------------------------------------------------------
# 15. 基础环境安装
# 来源：基于 168.diy/linuxbox.sh（未声明许可证，https://168.diy/linuxbox.sh）
#       第 30–37 行“0) 安装环境”改写；原脚本自安装部分由 tb install 承担
# -------------------------------------------------------------
tb_feat_base_env() {
    tb_require_root || return 1
    tb_log "安装基础工具：sudo curl wget tar zip ca-certificates"
    tb_pkg_install sudo curl wget tar zip ca-certificates || return 1
    tb_ok "基础环境已就绪"
}

# -------------------------------------------------------------
# 16. 安装 GOST 环境
# 来源：基于 168.diy/linuxbox.sh 第 59–117 行“5) 安装 GOST 环境”改写，
#       增加架构自动识别（原版仅 amd64），systemd 单元改为 simple 类型
# -------------------------------------------------------------
tb_feat_gost() {
    tb_require_root || return 1
    tb_pkg_install curl tar ca-certificates || return 1

    local arch
    case "$(uname -m)" in
        x86_64)    arch="amd64" ;;
        aarch64)   arch="armv8" ;;
        armv7l)    arch="armv7" ;;
        i386|i686) arch="386" ;;
        *) tb_error "暂不支持的架构: $(uname -m)"; return 1 ;;
    esac

    echo "1) GitHub 官方源"
    echo "2) 168.diy 自建源（仅 amd64）"
    read -r -p "请选择下载源 [1-2]: " src_choice || return 1

    local url
    case "$src_choice" in
        1) url="https://github.com/ginuerzh/gost/releases/download/v2.12.0/gost_2.12.0_linux_${arch}.tar.gz" ;;
        2)
            [[ "$arch" == "amd64" ]] || { tb_error "自建源仅提供 amd64"; return 1; }
            url="https://168.diy/gost_2.12.0_linux_amd64.tar.gz"
            ;;
        *) tb_error "无效选项，取消安装"; return 1 ;;
    esac

    mkdir -p /root/gost
    local tmp
    tmp="$(mktemp)" || return 1
    tb_log "下载 GOST: $url"
    if ! curl -fsSL --max-time 120 -o "$tmp" "$url"; then
        tb_error "下载失败"; rm -f "$tmp"; return 1
    fi
    tar -xzf "$tmp" -C /root/gost
    rm -f "$tmp"
    chmod +x /root/gost/gost

    cat > /lib/systemd/system/gost.service <<'EOF'
[Unit]
Description=GOST Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/gost
ExecStart=/root/gost/gost -C /root/gost/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # 占位配置，用户后续自行编辑 ServeNodes
    if [[ ! -f /root/gost/config.json ]]; then
        cat > /root/gost/config.json <<'EOF'
{
    "Debug": false,
    "Retries": 0,
    "ServeNodes": []
}
EOF
    fi

    systemctl daemon-reload
    tb_ok "GOST 安装完成：/root/gost/gost"
    /root/gost/gost -V 2>&1
    tb_warn "config.json 为空占位，配置好节点后再执行：systemctl enable --now gost"
}

# -------------------------------------------------------------
# 17. DD 重装脚本下载（LeitboGi0ro InstallNET）
# 来源：基于 168.diy/linuxbox.sh 第 275–299 行“92) 使用 LeitboGi0ro DD”改写，
#       只下载并校验脚本，不自动执行，重装命令由用户手动发起
# -------------------------------------------------------------
tb_feat_dd_leitbo() {
    tb_require_root || return 1
    tb_pkg_install wget ca-certificates || return 1

    local url
    echo "1) GitHub 仓库"
    echo "2) Gitee 仓库（国内备用）"
    read -r -p "请选择 [1-2]: " c || return 1
    case "$c" in
        1) url="https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh" ;;
        2) url="https://gitee.com/mb9e8j2/Tools/raw/master/Linux_reinstall/InstallNET.sh" ;;
        *) tb_error "无效选项"; return 1 ;;
    esac

    mkdir -p /root/reinstall
    local target="/root/reinstall/InstallNET.sh"
    tb_log "下载 InstallNET.sh（不执行）"
    if ! wget --no-check-certificate -qO "$target" "$url"; then
        tb_error "下载失败"; return 1
    fi
    if [[ ! -s "$target" ]] || ! head -1 "$target" | grep -q '^#!'; then
        tb_error "内容校验失败（要求非空且首行为 shebang）"
        rm -f "$target"; return 1
    fi
    chmod a+x "$target"

    tb_warn "DD 会清空整块系统盘并重装，期间 SSH 会断开，错误配置可能导致失联，请先备份数据"
    tb_ok "脚本已下载：$target"
    tb_log "确认风险后，由你手动执行：bash $target -debian 12"
}

# -------------------------------------------------------------
# 系统工具总菜单
# -------------------------------------------------------------
tb_feat_settings_menu() {
    while true; do
        tb_clear
        echo -e "${C_BOLD}系统工具（Debian/Ubuntu）${C_RESET}"
        echo "------------------------"
        echo " 1. 修改 SSH 端口"
        echo " 2. 优化 DNS"
        echo " 3. IPv4/IPv6 优先级"
        echo " 4. 查看端口占用"
        echo " 5. 虚拟内存"
        echo " 6. 修改主机名"
        echo " 7. 切换更新源"
        echo " 8. SSH 防御（fail2ban）"
        echo " 9. 用户密钥登录"
        echo "10. 修复 OpenSSH 漏洞"
        echo "11. 内核参数优化"
        echo "12. 切换系统语言"
        echo "13. 命令行美化"
        echo "14. 系统备份与恢复"
        echo "15. 基础环境安装"
        echo "16. 安装 GOST 环境"
        echo "17. DD 重装脚本下载"
        echo "------------------------"
        echo " 0. 返回主菜单"
        echo "------------------------"
        read -r -p "请选择: " c || return 0
        case "$c" in
            1)  tb_feat_ssh_port ;;
            2)  tb_feat_dns ;;
            3)  tb_feat_ip_mode ;;
            4)  tb_feat_ports ;;
            5)  tb_feat_swap ;;
            6)  tb_feat_hostname ;;
            7)  tb_feat_mirror ;;
            8)  tb_feat_f2b ;;
            9)  tb_feat_sshkey ;;
            10) tb_feat_ssh_fix ;;
            11) tb_feat_tune ;;
            12) tb_feat_lang ;;
            13) tb_feat_ps1 ;;
            14) tb_feat_backup ;;
            15) tb_feat_base_env ;;
            16) tb_feat_gost ;;
            17) tb_feat_dd_leitbo ;;
            0)  return 0 ;;
            *)  tb_warn "无效输入"; sleep 1 ;;
        esac
    done
}

# =============================================================
#  交互菜单
# =============================================================

# 版本号比较：$1 大于 $2 时返回 0
tb_ver_gt() {
    local a b i
    IFS=. read -r -a a <<< "$1"
    IFS=. read -r -a b <<< "$2"
    for i in 0 1 2; do
        if (( ${a[i]:-0} > ${b[i]:-0} )); then return 0; fi
        if (( ${a[i]:-0} < ${b[i]:-0} )); then return 1; fi
    done
    return 1
}

# 启动时自动检查更新：网络失败/无 curl 一律静默跳过，不阻塞进入菜单
tb_auto_check_update() {
    tb_has curl || return 0
    local url="$TB_RAW_URL" tmp remote_ver
    [[ -n "$TB_MIRROR" ]] && url="${TB_MIRROR}${TB_RAW_URL}"
    tmp="$(mktemp)" || return 0
    if ! curl -fsSL --max-time 8 -o "$tmp" "$url" 2>/dev/null; then
        rm -f "$tmp"; return 0
    fi
    remote_ver="$(grep -m1 -oE 'TB_VERSION="[0-9.]+"' "$tmp" | grep -oE '[0-9.]+')"
    rm -f "$tmp"
    [[ -n "$remote_ver" ]] || return 0
    if tb_ver_gt "$remote_ver" "$TB_VERSION"; then
        tb_warn "发现新版本: ${remote_ver}（当前 ${TB_VERSION}）"
        if tb_confirm "是否立即更新？"; then
            tb_self_update
        fi
    fi
}

# 卸载 ToolBox：按用户指定命令执行，需 root 与确认，完成后退出
tb_feat_uninstall() {
    tb_require_root || return 1
    tb_warn "将删除已安装的 $TB_CMD 命令及相关备份/目录，此操作不可恢复"
    tb_confirm "确认卸载 ToolBox？" || return 1
    rm -f /usr/local/bin/tb /usr/local/bin/tb.bak
    rm -f /etc/ssh/sshd_config.tb.bak /etc/resolv.conf.tb.bak
    rm -rf /root/reinstall /backups
    rm -f /root/toolbox.sh ./toolbox.sh
    tb_ok "ToolBox 已卸载"
    exit 0
}

# 高级功能菜单（检查更新 + 卸载）
tb_feat_advanced_menu() {
    while true; do
        tb_clear
        echo -e "${C_BOLD}高级功能${C_RESET}"
        echo "------------------------"
        echo "1. 检查更新"
        echo "2. 卸载 ToolBox"
        echo "------------------------"
        echo "0. 返回主菜单"
        echo "------------------------"
        read -r -p "请选择: " c || return 0
        case "$c" in
            1) tb_self_update; tb_pause ;;
            2) tb_feat_uninstall ;;
            0) return 0 ;;
            *) tb_warn "无效输入"; sleep 1 ;;
        esac
    done
}

tb_main_menu() {
    tb_auto_check_update
    while true; do
        tb_clear
        echo -e "${C_BOLD}============================================"
        echo " My Toolbox v$TB_VERSION"
        echo -e "============================================${C_RESET}"
        echo " 1. 系统信息查询"
        echo " 2. 系统清理"
        echo " 3. 测试脚本合集"
        echo " 4. 系统工具"
        echo "TB. 高级功能"
        echo "--------------------------------------------"
        echo " 0.  退出"
        echo "============================================"
        read -r -p "请输入选择: " choice || exit 0
        case "$choice" in
            1)  tb_feat_info; tb_pause ;;
            2)  tb_feat_clean; tb_pause ;;
            3)  tb_feat_test_menu ;;
            4)  tb_feat_settings_menu ;;
            TB|tb) tb_feat_advanced_menu ;;
            0)  tb_log "再见"; exit 0 ;;
            *)  tb_warn "无效输入，请重新选择"; sleep 1 ;;
        esac
    done
}

# =============================================================
#  命令行分发
# =============================================================

tb_help() {
    cat <<EOF
用法:
  $TB_CMD                  打开交互菜单
  $TB_CMD info             系统信息查询
  $TB_CMD clean            系统清理
  $TB_CMD test             测试脚本合集
  $TB_CMD settings         系统工具菜单
  系统工具直达命令:
    sshport   修改 SSH 端口        dns       优化 DNS
    ipmode    IP 优先级            ports     端口占用
    swap      虚拟内存             hostname  主机名
    mirror    切换更新源           f2b       SSH 防御
    sshkey    用户密钥登录         sshfix    修复 OpenSSH
    tune      内核参数优化         lang      系统语言
    ps1       命令行美化           backup    备份与恢复
    baseenv   基础环境安装         gost      安装 GOST
    dd        DD 重装脚本下载
  $TB_CMD update           从 GitHub 更新到最新版（启动交互菜单时也会自动检查）
  $TB_CMD advanced         高级功能菜单（更新/卸载）
  $TB_CMD uninstall        卸载 ToolBox
  $TB_CMD install          安装/修复 $TB_CMD 到 /usr/local/bin
  $TB_CMD help             显示本帮助
  $TB_CMD version          显示版本号
环境变量:
  TB_MIRROR=<前缀>         为 RAW 地址加加速前缀，如 https://ghproxy.net/
EOF
}

tb_cli_dispatch() {
    case "$1" in
        info|信息)            tb_feat_info ;;
        clean|清理)           tb_feat_clean ;;
        test|测试)            tb_feat_test_menu ;;
        settings|工具|sys)    tb_feat_settings_menu ;;
        sshport|ssh端口)      tb_feat_ssh_port ;;
        dns)                  tb_feat_dns ;;
        ipmode|ip优先级)      tb_feat_ip_mode ;;
        ports|端口占用)       tb_feat_ports ;;
        swap|虚拟内存)        tb_feat_swap ;;
        hostname|主机名)      tb_feat_hostname ;;
        mirror|更新源)        tb_feat_mirror ;;
        f2b|fail2ban)         tb_feat_f2b ;;
        sshkey|密钥)          tb_feat_sshkey ;;
        sshfix|ssh修复)       tb_feat_ssh_fix ;;
        tune|内核)            tb_feat_tune ;;
        lang|语言)            tb_feat_lang ;;
        ps1|美化)             tb_feat_ps1 ;;
        backup|备份)          tb_feat_backup ;;
        baseenv|基础环境)     tb_feat_base_env ;;
        gost)                 tb_feat_gost ;;
        dd|reinstall|重装)    tb_feat_dd_leitbo ;;
        install|安装)         tb_self_install ;;
        update|更新)          tb_self_update ;;
        advanced|高级)        tb_feat_advanced_menu ;;
        uninstall|卸载)       tb_feat_uninstall ;;
        help|--help|-h)       tb_help ;;
        version|--version|-v) echo "$TB_VERSION" ;;
        '')                   tb_main_menu ;;
        *)
            tb_error "未知命令: $1"
            tb_help
            return 1 ;;
    esac
}

# =============================================================
#  入口
# =============================================================

tb_check_platform

if [[ $# -eq 0 ]]; then
    tb_main_menu
else
    tb_cli_dispatch "$@"
fi
