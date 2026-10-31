#!/usr/bin/env bash
# ==============================================================================
# WVP-PRO 3.0.0 · Linux 服务停止（随离线包分发）
# ------------------------------------------------------------------------------
# 流程：按部署模式选择编排文件 → docker compose down（容器移除，数据保留在 ./data）
# 部署模式优先取 --host/--bridge 参数，其次读 .deploy-mode（由 start.sh 写入），默认 bridge
# 用法：
#   ./stop.sh [--host | --bridge]
# ==============================================================================
set -euo pipefail

USE_HOST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host)   USE_HOST=1; shift ;;
    --bridge) USE_HOST=0; shift ;;
    -h|--help)
      echo "用法: $0 [--host | --bridge]"
      echo "无参数时自动读取 .deploy-mode（start.sh 启动时写入）"
      exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE"

log()  { echo -e "\033[36m[stop]\033[0m $*"; }
fail() { echo -e "\033[31m[错误]\033[0m $*"; exit 1; }

echo "========== WVP-PRO Linux 服务停止 =========="

command -v docker >/dev/null 2>&1 || fail "未找到 docker"
docker info >/dev/null 2>&1 || fail "Docker 未运行（docker info 失败）"

# ---- 1. 判定部署模式 ----
if [ -n "$USE_HOST" ]; then
  MODE="$([ "$USE_HOST" = "1" ] && echo host || echo bridge)"
else
  MODE="bridge"
  if [ -f ".deploy-mode" ]; then
    MODE="$(tr -d ' \r' < .deploy-mode)"
  fi
fi

# ---- 2. 停止 ----
if [ "$MODE" = "host" ]; then
  log "以 host 网络停止（docker-compose.host.yml）..."
  docker compose -f docker-compose.host.yml down
else
  log "以 bridge 网络停止（docker-compose.yml）..."
  docker compose down
fi

# ---- 3. 结果 ----
echo
echo "================= 停止完成 ================="
echo "  数据保留在 ./data（MySQL 库文件与 Redis 持久化、录像都在其中）"
echo "  重新启动：./start.sh$( [ "$MODE" = "host" ] && echo ' --host' )"
echo "============================================"