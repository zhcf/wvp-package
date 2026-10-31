#!/usr/bin/env bash
# ==============================================================================
# WVP-PRO 3.0.0 · Linux 离线安装器（随离线包分发，在【无网络】Linux 机器运行）
# ------------------------------------------------------------------------------
# 流程：docker load 加载全部镜像 → 可选替换 IP →（不启动；启动用 ./start.sh）
# 用法：
#   ./install.sh [--stream-ip <IP>]
#     --stream-ip <IP>   一键替换 .env 中 Stream_IP / SDP_IP / SIP_ShowIP
# 依赖：Docker Engine + docker compose 插件（离线机器需已装好）
# ==============================================================================
set -euo pipefail

STREAM_IP=""

while [ $# -gt 0 ]; do
  case "$1" in
    --stream-ip) STREAM_IP="$2"; shift 2 ;;
    -h|--help)
      echo "用法: $0 [--stream-ip <IP>]"
      echo "完成后执行 ./start.sh 启动服务（host 网络加 --host）"
      exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE"

log()  { echo -e "\033[36m[install]\033[0m $*"; }
warn() { echo -e "\033[33m[警告]\033[0m $*"; }
fail() { echo -e "\033[31m[错误]\033[0m $*"; exit 1; }

echo "========== WVP-PRO Linux 离线安装 =========="

# ---- 1. 环境检查 ----
command -v docker >/dev/null 2>&1 || fail "未找到 docker，请先在离线机器安装 Docker Engine 与 compose 插件"
docker info >/dev/null 2>&1 || fail "Docker 未运行（docker info 失败），请先启动 dockerd"
docker compose version >/dev/null 2>&1 || fail "缺少 docker compose 插件（docker compose version 失败）"
[ -f ".env" ] || fail "缺少 .env（请确认在离线包解压目录内运行）"

# ---- 2. 加载镜像 ----
shopt -s nullglob
tars=(images/*.tar)
if [ ${#tars[@]} -eq 0 ]; then fail "images/ 下没有镜像 tar 包"; fi
for f in "${tars[@]}"; do
  log "docker load -i $f ..."
  docker load -i "$f"
done

# ---- 3. IP 配置 ----
if [ -n "$STREAM_IP" ]; then
  log "替换 .env 中的 IP 为 $STREAM_IP"
  sed -i "s/^Stream_IP=.*/Stream_IP=$STREAM_IP/; s/^SDP_IP=.*/SDP_IP=$STREAM_IP/; s/^SIP_ShowIP=.*/SIP_ShowIP=$STREAM_IP/" .env
fi
CUR_IP="$(grep -E '^Stream_IP=' .env | head -1 | cut -d= -f2- | tr -d ' \r')"
if [ -z "$CUR_IP" ] || [ "$CUR_IP" = "192.168.1.100" ]; then
  warn ".env 中 Stream_IP 仍为示例值（$CUR_IP）：启动前请改为设备可访问的真实 IP"
  warn "  修改方法：./install.sh --stream-ip <本机真实IP>"
fi

# ---- 4. 结果 ----
echo
echo "================= 安装完成（镜像已加载） ================="
echo "  启动   : ./start.sh           （默认 bridge 网络）"
echo "            ./start.sh --host    （host 网络，Linux 生产推荐）"
echo "  访问   : http://$CUR_IP:18080   默认账号 admin / admin"
echo "  停止   : ./stop.sh"
echo "  注意   : 防火墙放行 tcp+udp 5060 与 20000 端口"
echo "=========================================================="