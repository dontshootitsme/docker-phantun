#!/bin/bash
set -e

MODE=$1
shift 1

NIC=${NIC:-eth0}
TCP_PORT=${TCP_PORT:-20001}

# ---------- 解析命令行中的 --tun ----------
ARGS=()
TUN_FROM_CMD=""
while [ $# -gt 0 ]; do
    case "$1" in
        --tun)
            if [ $# -ge 2 ]; then
                shift
                TUN_FROM_CMD="$1"
                ARGS+=("--tun" "$1")
            else
                ARGS+=("--tun")
            fi
            ;;
        --tun=*)
            TUN_FROM_CMD="${1#--tun=}"
            ARGS+=("$1")
            ;;
        *)
            ARGS+=("$1")
            ;;
    esac
    shift
done

# ---------- 确定 TUN 接口名 ----------
# 优先级: 命令行 --tun > TUN_NAME 环境变量 > 自动派生
#
# 自动派生规则: ptun<TCP_PORT><4位配置指纹>
#   - 端口号区分同主机上不同端口的实例
#   - 4 位指纹取命令行参数的 md5 前 4 位, 保证同端口不同配置
#     (如指向不同 VPS 的两个客户端) 也不会重名
#   - 名字由 (端口, 配置) 唯一决定: 容器重启后名字不变,
#     旧 iptables 规则能被下次的 cleanup 清掉, 排查时也能直接对号入座
# 注意: 不要使用 tun0/tun1 这类内核自动分配风格的名字, 避免与
# easytier 等其他 TUN 设备冲突 (历史版本写死 tun0 导致转发规则失效)。
if [ -n "$TUN_FROM_CMD" ]; then
    TUN_NAME="$TUN_FROM_CMD"
elif [ -n "${TUN_NAME:-}" ]; then
    ARGS=("--tun" "$TUN_NAME" "${ARGS[@]}")
else
    FP=$(printf '%s' "${ARGS[*]}" | md5sum | cut -c1-4)
    TUN_NAME="ptun${TCP_PORT}${FP}"
    ARGS=("--tun" "$TUN_NAME" "${ARGS[@]}")
fi

if [ "${#TUN_NAME}" -gt 15 ]; then
    echo "[Error] TUN 接口名长度不能超过 15 个字符，当前: $TUN_NAME"
    exit 1
fi

if ip link show "$TUN_NAME" >/dev/null 2>&1; then
    echo "[Error] TUN 接口 $TUN_NAME 已存在（被其他容器或进程占用）。"
    echo "        请先停掉占用它的容器，或通过 TUN_NAME 环境变量 / --tun 参数换名。"
    exit 1
fi

echo "[Info] TUN 接口名: $TUN_NAME"

cleanup_server() {
    echo "[Info] 正在清理 Server 端的 iptables 规则..."
    # 清理 NAT 和 RST 阻断
    iptables -t nat -D PREROUTING -p tcp -i $NIC --dport $TCP_PORT -j DNAT --to-destination 192.168.201.2 2>/dev/null || true
    iptables -D OUTPUT -p tcp -o $NIC --sport $TCP_PORT --tcp-flags RST RST -j DROP 2>/dev/null || true
    # 清理 FORWARD 放行规则
    iptables -D FORWARD -i $NIC -o $TUN_NAME -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i $TUN_NAME -o $NIC -j ACCEPT 2>/dev/null || true
}

cleanup_client() {
    echo "[Info] 正在清理 Client 端的 iptables 规则..."
    iptables -t nat -D POSTROUTING -o $NIC -j MASQUERADE 2>/dev/null || true
    iptables -D OUTPUT -p tcp -o $NIC --dport $TCP_PORT --tcp-flags RST RST -j DROP 2>/dev/null || true
    # 清理 FORWARD 放行规则 (对于客户端同样适用)
    iptables -D FORWARD -i $NIC -o $TUN_NAME -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i $TUN_NAME -o $NIC -j ACCEPT 2>/dev/null || true
}

if [ "$MODE" = "server" ]; then
    echo "[Info] 初始化 Phantun Server 模式..."
    cleanup_server

    iptables -t nat -A PREROUTING -p tcp -i $NIC --dport $TCP_PORT -j DNAT --to-destination 192.168.201.2
    iptables -A OUTPUT -p tcp -o $NIC --sport $TCP_PORT --tcp-flags RST RST -j DROP
    # 强制放行网卡与 TUN 设备间的双向转发
    iptables -I FORWARD -i $NIC -o $TUN_NAME -j ACCEPT
    iptables -I FORWARD -i $TUN_NAME -o $NIC -j ACCEPT

    trap cleanup_server EXIT INT TERM

    echo "[Info] 启动 phantun_server..."
    /usr/local/bin/phantun_server "${ARGS[@]}" &
    PHANTUN_PID=$!

elif [ "$MODE" = "client" ]; then
    echo "[Info] 初始化 Phantun Client 模式..."
    cleanup_client

    iptables -t nat -A POSTROUTING -o $NIC -j MASQUERADE
    iptables -A OUTPUT -p tcp -o $NIC --dport $TCP_PORT --tcp-flags RST RST -j DROP
    # 强制放行网卡与 TUN 设备间的双向转发
    iptables -I FORWARD -i $NIC -o $TUN_NAME -j ACCEPT
    iptables -I FORWARD -i $TUN_NAME -o $NIC -j ACCEPT

    trap cleanup_client EXIT INT TERM

    echo "[Info] 启动 phantun_client..."
    /usr/local/bin/phantun_client "${ARGS[@]}" &
    PHANTUN_PID=$!

else
    echo "[Error] 未知的运行模式"
    exit 1
fi

# 等待 phantun 创建 TUN 接口并确认名字符合预期
sleep 1
if ! ip link show "$TUN_NAME" >/dev/null 2>&1; then
    echo "[Error] phantun 未能创建 TUN 接口 $TUN_NAME，请查看容器日志"
    kill $PHANTUN_PID 2>/dev/null || true
    exit 1
fi
echo "[Info] TUN 接口 $TUN_NAME 已就绪"

wait $PHANTUN_PID
