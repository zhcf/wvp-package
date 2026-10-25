#!/usr/bin/env bash
# ==============================================================================
# WVP-PRO 3.0.0 · Linux 离线包制作（在【可联网】且已安装 Docker 的 Linux 机器运行）
# ------------------------------------------------------------------------------
# 流程：
#   1) docker compose build 构建 wvp 镜像（源码 npm+maven 多阶段构建）
#   2) docker pull mysql:8.0 / redis:7-alpine / zlmediakit/zlmediakit:master
#   3) docker save 四个镜像 + docker-compose 方案文件 + 三个入口脚本（install/start/stop）
#      → 打包为：offline/dist/wvp-linux-offline-<版本>.tar.gz
# 用法：
#   ./pack.sh [--version 3.0.0] [--out-dir DIR] [--skip-build] [--skip-pull]
# ==============================================================================
set -euo pipefail

VERSION="3.0.0"
OUT_DIR=""
SKIP_BUILD=0
SKIP_PULL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --version)   VERSION="$2"; shift 2 ;;
    --out-dir)   OUT_DIR="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --skip-pull)  SKIP_PULL=1; shift ;;
    -h|--help)
      echo "用法: $0 [--version 3.0.0] [--out-dir DIR] [--skip-build] [--skip-pull]"
      exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # offline/linux/
OFFLINE="$(dirname "$BASE")"                            # offline/
REPO="$(dirname "$OFFLINE")"                            # 仓库根
COMPOSE_DIR="$REPO/docker-compose"
BUILD="$OFFLINE/build"
STAGE="$BUILD/wvp-linux-offline-$VERSION"
DIST="${OUT_DIR:-$OFFLINE/dist}"
PKG="wvp-linux-offline-$VERSION.tar.gz"

MYSQL_IMG="mysql:8.0"
REDIS_IMG="redis:7-alpine"
ZLM_IMG="zlmediakit/zlmediakit:master"

log()  { echo -e "\033[36m[pack]\033[0m $*"; }
warn() { echo -e "\033[33m[警告]\033[0m $*"; }
fail() { echo -e "\033[31m[错误]\033[0m $*"; exit 1; }

echo "========== WVP-PRO Linux 离线包制作 =========="

# ---- 0. 环境与来源检查 ----
command -v docker >/dev/null 2>&1 || fail "未找到 docker，请先安装 Docker"
docker info >/dev/null 2>&1 || fail "Docker 未运行（docker info 失败）"
docker compose version >/dev/null 2>&1 || fail "缺少 docker compose 插件（docker compose version 失败）"
[ -f "$COMPOSE_DIR/docker-compose.yml" ] || fail "缺少 $COMPOSE_DIR/docker-compose.yml"
for s in "$BASE/install.sh" "$BASE/start.sh" "$BASE/stop.sh"; do
  [ -f "$s" ] || fail "缺少入口脚本：$s"
done

# WVP 镜像名取自 .env（默认 wvp-pro:3.0.0）
WVP_IMG="$(grep -E '^WVP_IMAGE=' "$COMPOSE_DIR/.env" | head -1 | cut -d= -f2- | tr -d ' \r' || true)"
WVP_IMG="${WVP_IMG:-wvp-pro:3.0.0}"
log "WVP 镜像: $WVP_IMG"

# ---- 1. 构建 wvp 镜像 ----
if [ "$SKIP_BUILD" = "0" ]; then
  log "构建 wvp 镜像（前端 npm + 后端 maven 多阶段构建，首次约 10~30 分钟）..."
  (cd "$COMPOSE_DIR" && docker compose build wvp)
else
  log "跳过构建（--skip-build）"
fi
docker image inspect "$WVP_IMG" >/dev/null 2>&1 || fail "本地不存在镜像 $WVP_IMG（请去掉 --skip-build 重新运行）"

# ---- 2. 拉取依赖镜像 ----
if [ "$SKIP_PULL" = "0" ]; then
  for img in "$MYSQL_IMG" "$REDIS_IMG" "$ZLM_IMG"; do
    log "docker pull $img ..."
    docker pull "$img"
  done
else
  log "跳过拉取（--skip-pull）"
fi
for img in "$MYSQL_IMG" "$REDIS_IMG" "$ZLM_IMG"; do
  docker image inspect "$img" >/dev/null 2>&1 || fail "本地不存在镜像 $img（请去掉 --skip-pull 重新运行）"
done

# ---- 3. 组装包目录 ----
log "组装目录：$STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/images"

# 3.1 docker-compose 方案文件（保留目录结构；.env 为默认配置模板）
for f in .env docker-compose.yml docker-compose.host.yml README.md .dockerignore; do
  [ -f "$COMPOSE_DIR/$f" ] && cp -a "$COMPOSE_DIR/$f" "$STAGE/"
done
cp -a "$COMPOSE_DIR/config"    "$STAGE/config"
cp -a "$COMPOSE_DIR/mysql"     "$STAGE/mysql"
cp -a "$COMPOSE_DIR/wvp-image" "$STAGE/wvp-image"

# 3.2 导出镜像（总计数 GB，耗时数分钟）
log "docker save 镜像 ..."
docker save -o "$STAGE/images/wvp.tar"   "$WVP_IMG"
docker save -o "$STAGE/images/mysql.tar" "$MYSQL_IMG"
docker save -o "$STAGE/images/redis.tar" "$REDIS_IMG"
docker save -o "$STAGE/images/zlm.tar"   "$ZLM_IMG"

# 3.3 三个入口脚本（install / start / stop）
for s in install.sh start.sh stop.sh; do
  cp "$BASE/$s" "$STAGE/$s"
  chmod +x "$STAGE/$s"
done

# 3.4 离线安装说明（UTF-8）
cat > "$STAGE/离线安装说明.txt" <<EOF
WVP-PRO $VERSION · Linux 离线安装包（Docker 多容器方案）
====================================================================
一、安装（在无网络的 Linux 机器上，需已装好 Docker Engine + compose 插件）
  1. tar -xzf wvp-linux-offline-$VERSION.tar.gz
  2. cd wvp-linux-offline-$VERSION
  3. ./install.sh --stream-ip <本机真实IP>
     完成：docker load 加载全部镜像 + 替换 .env 中的 IP（不启动服务）
  4. ./start.sh              # 启动（默认 bridge 网络）
     或 ./start.sh --host     # host 网络（Linux 生产推荐，SIP/RTP 端口直通）
  5. 浏览器访问 http://<本机IP>:18080 ，默认账号 admin / admin

二、三个脚本分工
  · install.sh  docker load 加载 images/ 下全部镜像（wvp / mysql / redis / zlm）
                --stream-ip 一键替换 .env 中 Stream_IP / SDP_IP / SIP_ShowIP
  · start.sh    docker compose up -d 启动四个容器（首次自动初始化数据库，约 1~2 分钟）
                --host 使用 docker-compose.host.yml；部署模式记入 .deploy-mode
  · stop.sh     docker compose down 停止并移除容器（数据保留在 ./data）
                自动读取 .deploy-mode 选择编排文件，也可用 --host / --bridge 覆盖

三、常用命令
  · 查看日志：docker compose logs -f wvp
  · 状态    ：docker compose ps
  · 重启    ：./stop.sh && ./start.sh

四、注意事项
  · 部署前必须把 .env 的 Stream_IP/SDP_IP/SIP_ShowIP 改成设备可访问的真实 IP
  · 防火墙需放行 tcp+udp 的 5060 与 10000（SIP 信令与 RTP 收流）
  · 详细文档：包内 README.md
====================================================================
EOF

# ---- 4. 打包 ----
mkdir -p "$DIST"
log "压缩 tar.gz（数 GB，耗时数分钟）..."
tar -czf "$DIST/$PKG" -C "$BUILD" "wvp-linux-offline-$VERSION"

SIZE="$(du -h "$DIST/$PKG" | cut -f1)"
echo
echo "================= 离线包制作完成 ================="
echo "  产物 : $DIST/$PKG（$SIZE）"
echo "  使用 : 拷贝到离线 Linux 机器 → tar -xzf 解压 → ./install.sh --stream-ip <IP> → ./start.sh"
echo "=================================================="