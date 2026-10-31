# WVP-PRO 3.0.0 · Linux 部署（Docker 容器化）

Linux 方案下提供两种形态，**都使用 Docker 容器**（wvp / zlm / mysql / redis 四容器），区别只在"镜像从哪里来"：

| 对比项 | 在线版 [`online/`](online/README.md) | 离线版 [`offline/`](offline/README.md) |
| --- | --- | --- |
| 镜像来源 | 目标机现场 `docker compose build` + `docker pull` | 制作机预先构建，`docker save` 为 tar **直接打进包内** |
| 目标机网络 | **需要联网**（源码/npm/maven + 镜像仓库） | **完全离线**，仅需 Docker + compose 插件 |
| 制作机要求 | 无（目标机即构建机） | 联网 Linux + Docker（磁盘 ≥ 20GB） |
| 入口命令 | `docker compose up -d --build` | `./install.sh`（加载镜像）→ `./start.sh` → `./stop.sh` |
| 包/目录 | 仓库目录直接使用 | `wvp-linux-offline-3.0.0.tar.gz`（约 795MB，内置四镜像） |
| 适用场景 | 服务器可上网、需要改源码后重建 | 内网隔离 / 无外网的生产环境 |

**共同特性**（两形态完全一致）：

- wvp 镜像同一个 Dockerfile（`online/wvp-image/`）构建，前端已打入 jar，访问 `http://IP:18080` 即有完整页面。
- 两套编排可选：`docker-compose.yml`（bridge，通用）与 `docker-compose.host.yml`（host 网络，Linux 生产推荐，SIP/RTP 无 NAT 问题）。
- 端口容器内外一致（18080 / 5060 / 9092 / 554 / 1935 / 20000 ...），配置与文档统一。
- 数据持久化在编排目录 `./data`（mysql / redis / record），`down` 不删数据。

## 一、在线版（online/）

```bash
cd linux/online
# 1. 修改 .env：Stream_IP / SDP_IP / SIP_ShowIP 改为服务器真实 IP，并修改默认密码
# 2. 构建并启动（首次构建 wvp 镜像约 10~30 分钟）
docker compose up -d --build
# 3. 访问 http://<服务器IP>:18080 ，默认账号 admin / admin
```

生产（host 网络）：`docker compose -f docker-compose.host.yml up -d --build`。详见 [online/README.md](online/README.md)。

## 二、离线版（offline/）

```bash
# ① 制作（联网 Linux 机，已装 Docker）：
cd linux/offline && ./pack.sh      # 构建 wvp 镜像 + 拉取三镜像 + docker save + 打包 tar.gz

# ② 使用（离线 Linux 机）：
tar -xzf wvp-linux-offline-3.0.0.tar.gz && cd wvp-linux-offline-3.0.0
./install.sh --stream-ip <本机IP>  # docker load 四个镜像 + 替换 .env IP
./start.sh                         # docker compose up -d；--host 切 host 网络
./stop.sh                          # 停止（数据保留在 ./data）
```

详见 [offline/README.md](offline/README.md)。

## 三、目录结构

```
linux/
├── README.md                    # 本文件（两种形态总览）
├── online/                      # 在线版（现场构建/拉取镜像）
│   ├── README.md
│   ├── .env                     # 环境变量（部署前修改）
│   ├── docker-compose.yml       # bridge 网络编排（通用）
│   ├── docker-compose.host.yml  # host 网络编排（Linux 生产）
│   ├── .dockerignore
│   ├── config/                  # WVP/ZLM 配置（映射进容器）
│   ├── wvp-image/               # wvp 镜像 Dockerfile + maven 加速配置
│   ├── mysql/init/              # 官方 3.0.0 初始化 SQL
│   ├── data/                    # 运行后生成：mysql/redis/record（gitignore）
│   └── logs/                    # 运行后生成：wvp/zlm 日志（gitignore）
└── offline/                     # 离线版（镜像 tar 打进包）
    ├── README.md
    ├── pack.sh                  # 离线包制作（联网 Linux 机运行）
    ├── install.sh               # 包内：docker load 四镜像 + 改 .env IP
    ├── start.sh                 # 包内：docker compose up -d
    ├── stop.sh                  # 包内：docker compose down
    ├── build/                   # 打包暂存（gitignore）
    └── dist/                    # 产物 tar.gz（gitignore）
```

## 四、端口与账号（两形态一致）

| 端口 | 协议 | 用途 |
| --- | --- | --- |
| 18080 | tcp | WVP Web 页面 / 接口 |
| 5060 | tcp+udp | SIP 信令（设备注册，**必须放行 udp**） |
| 9092 | tcp | ZLM HTTP（播流 http-flv/ws-flv 与 API） |
| 554 / 1935 | tcp | RTSP / RTMP |
| 20000 | tcp+udp | RTP 单端口收流（默认模式，**必须放行 udp**） |
| 8000 | tcp+udp | WebRTC |

| 账号 | 默认值 |
| --- | --- |
| WVP 管理员 | `admin / admin` |
| SIP 设备接入 | 服务器 ID `34020000002000000001`，域 `3402000000`，密码 `12345678` |
| MySQL | root `wvp_root_123456`；业务库 `wvp`，账号 `wvp / wvp_123456` |
| Redis | 密码 `wvp_redis_123456` |
| ZLM API 密钥 | `wvppro-zlm-3.0.0-9f3a7c2e5b1d4068a1c9` |

> `.env` 中 `Stream_IP / SDP_IP / SIP_ShowIP` 必须是设备可访问的本机真实 IP，
> 否则会出现「页面能打开、视频无法播放/设备收流失败」。