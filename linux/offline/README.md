# WVP-PRO 3.0.0 · Linux 离线版（Docker 镜像内置）

把四个容器镜像（`wvp-pro:3.0.0` / `mysql:8.0` / `redis:7-alpine` / `zlmediakit/zlmediakit:master`）
连同编排与配置**直接打进 tar.gz**，目标机在**无网络**环境下 `docker load` 即用——无需构建、无需拉取。

> 在线版（现场构建/拉取镜像）见 [`../online/`](../online/README.md)；两形态对比见 [`../README.md`](../README.md)。

---

## 一、原理与包结构

制作（联网 Linux 机）：构建 wvp 镜像 → 拉取三个依赖镜像 → `docker save` 为 tar → 组装 → tar.gz。

```
wvp-linux-offline-3.0.0/          # 解压后的目录（≈ 2GB 解压态）
├── images/                       # docker save 产出的四个镜像 tar（唯一与在线版不同之处）
│   ├── wvp.tar  mysql.tar  redis.tar  zlm.tar
├── docker-compose.yml            # 编排（bridge，通用）
├── docker-compose.host.yml       # 编排（host，Linux 生产推荐）
├── .env                          # 环境变量（install.sh --stream-ip 会自动替换三个 IP）
├── config/  mysql/  wvp-image/   # 与在线版完全相同的配置与构建文件
├── install.sh                    # ① docker load 全部镜像 + 替换 .env IP
├── start.sh                      # ② docker compose up -d（--host 切换编排）
├── stop.sh                       # ③ docker compose down（自动识别部署模式）
├── README.md                     # 在线版详细说明（编排/配置/端口，离线同样适用）
└── 离线安装说明.txt              # 三步走速查
```

## 二、制作（联网 Linux 机）

前置：Docker Engine 20.10+ 与 `docker compose` 插件（v2）、磁盘 ≥ 20GB、内存 ≥ 4GB。

```bash
cd linux/offline
./pack.sh                      # 构建 wvp 镜像 + 拉三镜像 + docker save + 打包（首次 15~40 分钟）
```

| 参数 | 说明 |
| --- | --- |
| `--version <版本>` | 版本号（默认 3.0.0，仅影响包名与包内说明） |
| `--out-dir <目录>` | 产物输出目录（默认 `linux/offline/dist`） |
| `--skip-build` | 跳过 `docker compose build wvp`（本机已有 `wvp-pro:3.0.0` 镜像时） |
| `--skip-pull` | 跳过 `docker pull`（三个依赖镜像已在本机时） |

产物：`linux/offline/dist/wvp-linux-offline-3.0.0.tar.gz`（约 795MB，压缩态）。
编排与配置模板取自 `../online/`，与在线版逐字节一致（`pack.sh` 自动拷贝，无需手工同步）。

> 制作机与目标机无需同架构（同 CPU 架构即可，一般均为 x86_64）。

## 三、离线机器安装与使用

前置：目标机已装 Docker Engine + compose 插件（这是离线版唯一的系统依赖）。
**不需要**任何外网、源码、Node/Maven。

```bash
tar -xzf wvp-linux-offline-3.0.0.tar.gz
cd wvp-linux-offline-3.0.0

./install.sh --stream-ip 192.168.1.100   # ① docker load 四个镜像 + 替换 .env 三个 IP（不启动）
./start.sh                                # ② 启动（默认 bridge）
#   或 ./start.sh --host                   #    host 网络（Linux 生产推荐，SIP/RTP 端口直通）
# ③ 浏览器访问 http://192.168.1.100:18080，默认账号 admin / admin（首次启动约 1~2 分钟初始化数据库）

./stop.sh                                 # 停止（数据保留在 ./data）
```

`install.sh` 参数：

| 参数 | 说明 |
| --- | --- |
| `--stream-ip <IP>` | 替换 `.env` 中 `Stream_IP / SDP_IP / SIP_ShowIP`（强烈建议提供） |

也可不传参、安装后手工编辑 `.env` 再 `./start.sh`。`start.sh` 会把部署模式写入 `.deploy-mode`，
`stop.sh` 据此自动选择编排文件（也可用 `--host` / `--bridge` 显式覆盖）。

## 四、常见问题（FAQ）

**Q：`install.sh` 报 `docker load` 失败？**
A：确认 Docker 已运行（`docker info`）、磁盘空间充足（镜像总量约 2GB）；若目标机 Docker 过旧（< 20.10），
   请升级后重试。加载完成后 `docker images` 应能看到 `wvp-pro:3.0.0 / mysql / redis / zlmediakit` 四个镜像。

**Q：`start.sh` 报"以下镜像未加载"？**
A：先执行 `./install.sh`（或 `./install.sh --stream-ip <IP>`）。

**Q：页面能打开但设备注册不上 / 视频播放不了？**
A：① `.env` 三个 IP 必须为本机真实 IP（`./install.sh --stream-ip` 已处理，换机/换网后重跑即可）；
   ② 防火墙放行 tcp+udp 的 `5060` 与 `20000`；③ bridge 模式仍有 NAT 限制时改用 `./start.sh --host`。

**Q：如何升级 WVP 版本？**
A：在制作机更新源码后重新 `./pack.sh`（`--version` 可换包名），目标机重新解压 → `install.sh` → `start.sh`。
   数据在 `./data`，升级不丢（跨大版本升级前先备份）。

**Q：与在线版的配置是否一致？**
A：完全一致——包内 `.env / config/ / mysql/ / docker-compose*.yml` 均由 `pack.sh` 从 `../online/` 原样拷贝。

**Q：停止后数据在哪？重新启动会清空吗？**
A：数据持久化在编排目录 `./data`（MySQL 库文件、Redis 持久化、录像）；`down` 只移除容器，不动数据。