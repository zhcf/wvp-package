#!/usr/bin/env bash
# ==============================================================================
# WVP-PRO 3.0.0 · Linux 服务启动（随离线包分发，先运行过 ./install.sh）
# ------------------------------------------------------------------------------
# 流程：检查镜像已加载 → docker compose up -d 启动四个容器
#       （首次启动自动初始化数据库，约 1~2 分钟）
# 用法：
#   ./start.sh [--host]
#     --host   使用 host 网络编排（docker-compose.host.yml，Linux 生产推荐）
#              部署模式写入 .deploy-mode，供 ./stop.sh 自动识别
# ==============================================================================
set -euo pipefail

USE_HOST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --host) USE_HOST=1; shift ;;
    -h|--help)
      echo "用法: $0 [--host]"
      exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE"

log()  { echo -e "\033[36m[start]\033[0m $*"; }
warn() { echo -e "\033[33m[警告]\033[0m $*"; }
fail() { echo -e "\033[31m[错误]\033[0m $*"; exit 1; }

echo "========== WVP-PRO Linux 服务启动 =========="

# ---- 1. 环境检查 ----
command -v docker >/dev/null 2>&1 || fail "未找到 docker，请先安装 Docker Engine 与 compose 插件"
docker info >/dev/null 2>&1 || fail "Docker 未运行（docker info 失败），请先启动 dockerd"
docker compose version >/dev/null 2>&1 || fail "缺少 docker compose 插件（docker compose version 失败）"
[ -f ".env" ] || fail "缺少 .env（请确认在离线包解压目录内运行）"

# ---- 2. 检查镜像已加载（由 install.sh 完成） ----
WVP_IMG="$(grep -E '^WVP_IMAGE=' .env | head -1 | cut -d= -f2- | tr -d ' \r' || true)"
WVP_IMG="${WVP_IMG:-wvp-pro:3.0.0}"
MISSING=""
for img in "$WVP_IMG" mysql:8.0 redis:7-alpine zlmediakit/zlmediakit:master; do
  docker image inspect "$img" >/dev/null 2>&1 || MISSING="$MISSING $img"
done
if [ -n "$MISSING" ]; then
  fail "以下镜像未加载：$MISSING
请先运行安装：./install.sh（首次）或 ./install.sh --stream-ip <本机IP>"
fi
log "镜像检查通过（wvp / mysql / redis / zlm）"

# ---- 3. 选择编排文件并记录部署模式 ----
if [ "$USE_HOST" = "1" ]; then
  [ -f "docker-compose.host.yml" ] || fail "缺少 docker-compose.host.yml（--host 模式）"
  echo "host" > .deploy-mode
  log "以 host 网络启动（docker-compose.host.yml）..."
  docker compose -f docker-compose.host.yml up -d
else
  echo "bridge" > .deploy-mode
  log "以 bridge 网络启动（docker-compose.yml）..."
  docker compose up -d
fi

# ---- 4. 结果 ----
CUR_IP="$(grep -E '^Stream_IP=' .env | head -1 | cut -d= -f2- | tr -d ' \r')"
echo
echo "================= 启动完成 ================="
echo "  访问 : http://${CUR_IP:-<本机IP>}:18080   默认账号 admin / admin"
echo "  日志 : docker compose logs -f wvp"
echo "  停止 : ./stop.sh"
echo "  注意 : 首次启动需 1~2 分钟初始化数据库；防火墙放行 tcp+udp 5060 与 20000"
echo "============================================"