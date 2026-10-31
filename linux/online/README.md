# WVP-PRO 3.0.0 · Linux 在线版（docker-compose 多容器）

> 一键部署 WVP-PRO 国标 GB28181 视频平台：**Web 界面 + 后端 + ZLMediaKit + MySQL + Redis** 全部容器化，
> 目标机联网现场构建/拉取镜像。离线环境请用 [`../offline/`](../offline/README.md)（镜像 tar 内置包内）。
> 官方文档：https://doc.wvp-pro.cn/#/ 　源码：https://github.com/648540858/wvp-GB28181-pro

---

## 1. 方案简介

| 容器 | 镜像 | 作用 |
|---|---|---|
| `wvp` | 本目录源码构建（`wvp-image/Dockerfile`） | WVP-PRO 后端 + 内置 Vue 前端页面 |
| `zlm` | `zlmediakit/zlmediakit:master` | 流媒体服务器（收流/转协议/录像） |
| `mysql` | `mysql:8.0` | 业务数据库（自动导入 3.0.0 初始化 SQL） |
| `redis` | `redis:7-alpine` | 缓存与会话 |

特点：

- **前端已内置**：构建镜像时自动编译 Vue 前端并打入 jar，访问 `http://IP:18080` 即有完整页面，无需单独部署 nginx。
- **端口容器内外一致**（18080/5060/9092/554/1935/20000...），配置文件与说明中端口号统一，不易混淆。
- 提供两套编排文件，二选一：
  - `docker-compose.yml`：**bridge 网络**，全平台通用（含 Windows/macOS Docker Desktop）。
  - `docker-compose.host.yml`：**host 网络**，仅 Linux，SIP/RTP 无 NAT 困扰，生产推荐。

## 2. 目录结构

```
linux/online/
├── .env                          # 环境变量（部署前必须修改）
├── docker-compose.yml            # 方案一：bridge 网络（通用）
├── docker-compose.host.yml       # 方案二：host 网络（Linux 生产）
├── .dockerignore
├── config/
│   ├── application.yml           # WVP 配置（映射进容器 /opt/wvp/config）
│   ├── zlm-config.ini            # ZLM 配置（bridge 模式，hook 指向 wvp 服务）
│   └── zlm-config.host.ini       # ZLM 配置（host 模式，hook 指向 127.0.0.1）
├── wvp-image/
│   ├── Dockerfile                # wvp 镜像多阶段构建（git→npm→maven→jre21）
│   └── maven-settings.xml        # maven 阿里云镜像加速
├── mysql/init/
│   └── wvp-init-3.0.0.sql        # 官方 3.0.0 初始化 SQL（首次启动自动执行）
├── data/                         # 运行后自动生成：mysql/redis/record 数据
└── logs/                         # 运行后自动生成：wvp/zlm 日志
```

## 3. 前置要求

- Docker Engine 20.10+ / Docker Desktop 4.x+，`docker compose`（v2，命令为 `docker compose` 而非 `docker-compose`）
- 内存 ≥ 4GB，磁盘 ≥ 20GB（录像按需增长）
- 构建 wvp 镜像需联网拉取：源码（gitee/github）、npm 包（npmmirror）、maven 依赖（aliyun）
- 服务器具有固定 IP（下称 `<宿主机IP>`），摄像机/SIP 平台可访问该 IP

## 4. 快速开始（5 步）

### 第 1 步 修改 `.env`

用编辑器打开 `.env`，**必须修改**以下项：

```dotenv
Stream_IP=192.168.1.100     # 改成你的宿主机真实 IP（浏览器播放地址）
SDP_IP=192.168.1.100        # 改成你的宿主机真实 IP（设备收流地址）
SIP_ShowIP=192.168.1.100    # 改成你的宿主机真实 IP
SIP_Password=12345678       # 设备注册密码，建议修改
MYSQL_ROOT_PASSWORD=...     # 建议修改
MYSQL_PASSWORD=...          # 建议修改
REDIS_PWD=...               # 建议修改
```

> ⚠️ `Stream_IP`/`SDP_IP` 填 `127.0.0.1` 或 `localhost` 会导致**页面能开、但视频播放与设备收流失败**，必须是网络可达的真实 IP。

### 第 2 步 构建并启动

```bash
cd docker-compose

# 方案一：bridge 网络（通用，Windows/macOS/Linux 均可用）
docker compose up -d --build

# 方案二：host 网络（仅 Linux 生产环境）
# docker compose -f docker-compose.host.yml up -d --build
```

首次构建需编译前端与后端，约 10~30 分钟（视网络与机器性能）。构建完成后启动只需秒级。

查看启动状态与日志：

```bash
docker compose ps
docker compose logs -f wvp       # 出现 "Started ..." 即启动成功
```

### 第 3 步 验证服务

```bash
# Web 页面（应返回 200）
curl -I http://127.0.0.1:18080

# ZLM API 存活（应返回 {"code":0,...}）
curl "http://127.0.0.1:9092/index/api/getServerConfig?secret=wvppro-zlm-3.0.0-9f3a7c2e5b1d4068a1c9"
```

浏览器打开 `http://<宿主机IP>:18080`，出现登录页即为成功。

### 第 4 步 登录平台

- 默认账号：`admin`　默认密码：`admin`
- 登录后请在 【用户管理】 中立即修改密码。

### 第 5 步 接入 GB28181 设备

在摄像机/NVR/平台端配置 SIP 参数：

| 参数 | 值 |
|---|---|
| SIP 服务器 ID | `34020000002000000001`（.env 中 `SIP_Id`） |
| SIP 域 | `3402000000`（.env 中 `SIP_Domain`） |
| SIP 服务器地址 | `<宿主机IP>` |
| SIP 服务器端口 | `5060` |
| 注册密码 | `.env` 中 `SIP_Password`（默认 `12345678`） |
| 注册有效期/心跳 | 3600 / 60（按设备要求即可） |

设备注册成功后，在平台【设备管理】即可看到设备，点击通道即可点播预览。

## 5. 端口清单

| 端口 | 协议 | 用途 | 说明 |
|---|---|---|---|
| 18080 | tcp | WVP Web/API | 浏览器访问入口 |
| 5060 | tcp+udp | SIP 信令 | 设备/平台注册 |
| 9092 | tcp | ZLM HTTP | 播流（http-flv/ws-flv）与 API |
| 554 | tcp | RTSP | 播流/收流 |
| 1935 | tcp | RTMP | 收流 |
| 20000 | tcp+udp | RTP | 单端口收流模式（默认，SSRC 区分流） |
| 30000-30500 | tcp+udp | RTP | 多端口收流模式（`RTP_ENABLE=true` 时需放开；host 方案默认开启） |
| 8000 | udp+tcp | WebRTC | ZLM WebRTC 收流 |
| 9000 | udp | SRT | 默认关闭，可不通 |

> 云服务器需在安全组/防火墙放行以上端口（udp 的 5060、20000 不可遗漏）。

## 6. 环境变量表（.env）

| 变量 | 默认值 | 说明 |
|---|---|---|
| `Stream_IP` | 192.168.1.100 | 浏览器播流地址 IP（**必改**） |
| `SDP_IP` | 192.168.1.100 | 设备收流 SDP 地址 IP（**必改**） |
| `SIP_ShowIP` | 192.168.1.100 | 前端展示的 SIP 地址（**必改**） |
| `SIP_Id` | 34020000002000000001 | SIP 服务器编码（20 位） |
| `SIP_Domain` | 3402000000 | SIP 域（10 位） |
| `SIP_Password` | 12345678 | 设备注册密码（建议修改） |
| `SIP_Port` | 5060 | SIP 端口 |
| `WVP_GIT_URL` | gitee 仓库 | 构建用源码地址 |
| `WVP_GIT_REF` | master | 构建用分支/标签 |
| `WVP_IMAGE` | wvp-pro:3.0.0 | 构建产物镜像名 |
| `MYSQL_ROOT_PASSWORD` | wvp_root_123456 | MySQL root 密码（建议修改） |
| `MYSQL_DATABASE` | wvp | 数据库名 |
| `MYSQL_USER` / `MYSQL_PASSWORD` | wvp / wvp_123456 | 业务账号（建议修改密码） |
| `REDIS_PWD` | wvp_redis_123456 | Redis 密码（建议修改） |
| `ZLM_SERCERT` | wvppro-zlm-3.0.0-9f3a7c2e5b1d4068a1c9 | ZLM API 密钥，**必须与 `config/zlm-config.ini` 的 `[api] secret` 一致**（勿用官方默认值 035c73f7-...：2024+ 版 ZLM 检测到默认值会自动随机改写配置文件） |

修改 `.env` 后需重建容器：`docker compose up -d`（值变化会重建受影响容器）。

## 7. 常用运维命令

```bash
docker compose ps                     # 查看状态
docker compose logs -f wvp            # WVP 日志
docker compose logs -f zlm            # ZLM 日志
docker compose restart wvp            # 重启 WVP（改 application.yml 后执行）
docker compose down                   # 停止并删除容器（./data 数据保留）
docker compose up -d --build          # 重新构建并启动（更新版本/改 Dockerfile 后）
```

## 8. 数据、录像与备份

| 位置 | 内容 |
|---|---|
| `./data/mysql` | MySQL 数据文件（**备份重点**） |
| `./data/redis` | Redis AOF 文件 |
| `./data/record` | 录像文件（ZLM `www/record`，保留天数由 `application.yml` 的 `record-day` 控制） |
| `./logs/` | wvp 与 zlm 日志 |

备份：停服后直接打包 `./data` 目录即可；恢复时解包回原位置再启动。

录像目录也可单独设置为大容量磁盘（修改 compose 中 `./data/record` 挂载路径后 `docker compose up -d`）。

## 9. 修改配置

- **WVP**：编辑 `config/application.yml` 后 `docker compose restart wvp`。
  - 端口、SIP、媒体、录像等全部可调；环境变量优先级见文件内注释。
- **ZLM**：编辑 `config/zlm-config.ini`（bridge）或 `config/zlm-config.host.ini`（host）后 `docker compose restart zlm`。
  - 如修改 `[api] secret`，必须同步修改 `.env` 的 `ZLM_SERCERT`。
- **媒体/收流模式**：默认单端口（20000）；改为多端口：`.env`/compose 中 `RTP_ENABLE: "true"`，并开放 30000-30500 端口段，重启 wvp。

## 10. 升级 WVP

```bash
# 方式一：跟随 master 最新代码重建
docker compose up -d --build

# 方式二：指定版本（修改 .env）
WVP_GIT_REF=v3.0.0
docker compose up -d --build
```

> 升级前请先备份 `./data`。数据库结构变更请参照官方升级说明。

## 11. 常见问题（FAQ）

**Q1：构建镜像失败 / 拉取依赖超时？**
`WVP_GIT_URL` 默认用 gitee；若仍超时，可换 ghproxy 代理源或 GitHub 源。npm 已使用 npmmirror、maven 已使用阿里云镜像（`wvp-image/maven-settings.xml`）。公司内网请配置 Docker 代理。

**Q2：页面打不开 / 白屏？**
`docker compose logs wvp` 查看是否启动完成；确认 18080 已放行；强刷浏览器缓存（Ctrl+F5）。

**Q3：设备注册成功，但预览黑屏/播放失败？**
绝大多数是 `Stream_IP`/`SDP_IP` 未改成宿主机真实 IP，或防火墙未放行 20000/udp（及多端口 30000-30500）。修改 `.env` 后 `docker compose up -d` 重建 wvp。

**Q4：ZLM 与 WVP 断连（媒体节点离线）？**
检查 `config/zlm-config.ini` 的 `[api] secret` 与 `.env` 的 `ZLM_SERCERT` 是否一致；一致后重启两个容器。
注意**勿使用官方默认值**（`035c73f7-...`）：2024+ 版 ZLM 检测到该值会自动随机改写配置文件，导致两边不一致（本项目默认已用自定义串规避）。

**Q5：录像无法下载/回放？**
确认 `./data/record` 有写权限与磁盘空间；ZLM 容器内目录为 `/opt/media/bin/www/record`，与 `application.yml` 的 `record-path` 对应。

**Q6：5060 端口被占用？**
修改 `.env` 的 `SIP_Port`（如 8116），同时修改 `config/zlm-config.host.ini` 无影响；bridge 方案端口映射会自动跟随 `.env`。修改后 `docker compose up -d`。

**Q7：如何完全重置（清空数据库重新初始化）？**
```bash
docker compose down
# 删除数据目录（Windows: rd /s /q data ; Linux: rm -rf data）
docker compose up -d
```

## 12. 安全建议

1. 修改所有默认密码：`admin` 平台账号、`SIP_Password`、MySQL、Redis 密码。
2. 本方案默认不对外暴露 MySQL/Redis（不映射端口），请勿随意添加映射。
3. 如需公网访问，建议前置反向代理开启 HTTPS，并限制 18080 的访问来源。
4. 定期备份 `./data`，录像容量与 `record-day` 按需调整。
5. ZLM 的 `[api] secret` 属于接口凭证，泄露后可被调用推流接口，务必修改为随机串并与 `.env` 保持同步。