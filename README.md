# WVP-PRO 3.0.0 部署方案（Windows 离线 · Linux 在线/离线）

> 为 [WVP-PRO](https://github.com/648540858/wvp-GB28181-pro)（国标 GB28181 视频平台，当前 master 版本为 v3.0.0）
> 提供按平台划分的开箱即用部署方案：**[`windows/`](windows/README.md)** 原生进程离线版（不依赖 Docker/容器）；
> **[`linux/`](linux/README.md)** Docker 容器化，分在线版（镜像现场构建/拉取）与离线版（镜像 tar 内置包内）。
> 官方文档：https://doc.wvp-pro.cn/#/

---

## 一、方案总览

| 平台 | 形态 | 目录 | 依赖 | 获取与运行方式 |
|---|---|---|---|---|
| Windows | 原生进程 · **仅离线版** | `windows/` | 仅 PowerShell 5.1+，**无 Docker/容器/WSL** | 联网 Windows 机 `pack.ps1` 制作 zip → 离线机解压 → `start.bat`（绿色版） |
| Linux | Docker · **在线版** | `linux/online/` | Docker + compose 插件（构建时联网） | 直接 `docker compose up -d --build` |
| Linux | Docker · **离线版** | `linux/offline/` | 目标机仅需 Docker + compose 插件 | 联网 Linux 机 `pack.sh` 制作 tar.gz（内置四镜像）→ 离线机 `install.sh` 加载 → `start.sh` |

**共同特性**：

- 端口方案一致：`18080 / 5060 / 9092 / 554 / 1935 / 20000 ...`，配置与文档统一（RTP 收流用 20000，避开 10000 的常见占用）。
- 前端随 jar 内置，访问 `http://IP:18080` 即有完整 Web 页面，**无需 nginx**
  （Linux 镜像构建时自动编译前端；Windows 用从该镜像提取的 jar 即可，jar 跨平台）。
- 初始化 SQL 使用官方 3.0.0 版本（`数据库/3.0.0/初始化-mysql-3.0.0.sql`，原样收录）。
- 默认单端口收流模式（RTP 20000，SSRC 区分流），热点端口少、NAT 简单。

## 二、快速开始

### Windows（离线版，不依赖 Docker）

```powershell
# ① 制作（在联网 Windows 机，仓库根执行）：
cd windows
.\pack.ps1                      # jar 已缓存时一键打包
.\pack.ps1 -WvpJar <jar路径>    # 首次可指定 jar（自动回写 cache\wvp\ 长期复用）

# ② 使用（在离线 Windows 机）：
#   解压 zip → 双击 start.bat（一键安装+启动）→ 访问 http://<本机IP>:18080
#   或分步：先 install.bat 再 start.bat；停止：stop.bat
```

> 产物 `windows\dist\wvp-windows-offline-3.0.0.zip` 已内置 JRE21 / MySQL8 / Redis / ZLMediaKit / wvp.jar。
> 绿色版：不写注册表、不装系统服务，组件/数据/日志全部在包内 `runtime\` 下，删除目录即完全卸载。详见 [windows/README.md](windows/README.md)。

### Linux 在线版（在线构建）

```bash
cd linux/online
# 1. 修改 .env：把 Stream_IP / SDP_IP / SIP_ShowIP 改为服务器真实 IP，并修改各默认密码
# 2. 构建并启动（首次构建 wvp 镜像约 10~30 分钟）
docker compose up -d --build
# 3. 访问 http://<服务器IP>:18080 ，默认账号 admin / admin
```

Linux 生产环境（host 网络，SIP/RTP 无 NAT 问题）：

```bash
docker compose -f docker-compose.host.yml up -d --build
```

### Linux 离线版（镜像内置）

```bash
# ① 制作（在联网 Linux 机，已装 Docker）：
cd linux/offline && ./pack.sh     # 自动构建 wvp 镜像 + 拉取三镜像 + docker save 打包

# ② 使用（在离线 Linux 机）：
tar -xzf wvp-linux-offline-3.0.0.tar.gz && cd wvp-linux-offline-3.0.0
./install.sh --stream-ip <本机IP>   # docker load 全部镜像 + 替换 .env IP
./start.sh                          # docker compose up -d（--host 切 host 网络）
# 停止：./stop.sh
```

详见 [linux/offline/README.md](linux/offline/README.md)。

### 设备接入（各方案相同）

| 参数 | 值 |
|---|---|
| SIP 服务器 ID | `34020000002000000001` |
| SIP 域 | `3402000000` |
| SIP 服务器地址 | `<服务器IP>` |
| SIP 服务器端口 | `5060` |
| 注册密码 | 默认 `12345678`（Linux 在 `.env` 修改；Windows 用 `start.ps1 -SipPassword` 指定） |

## 三、推荐工作流（一次构建，两平台产物）

1. 在联网 Linux 机执行 `linux/offline/pack.sh` → 得到 **Linux 离线包**，同时本地已有 `wvp-pro:3.0.0` 镜像。
2. 从该镜像提取跨平台 jar：
   ```bash
   docker create --name wvp-tmp wvp-pro:3.0.0
   docker cp wvp-tmp:/opt/wvp/wvp.jar ./wvp.jar
   docker rm wvp-tmp
   ```
   把 `wvp.jar` 放到 `windows/cache/wvp/wvp.jar`（或在打包时 `-WvpJar` 提供，自动回写缓存）。
3. 在联网 Windows 机执行 `windows/pack.ps1` → 得到 **Windows 离线包**（jar 自动打入）。

> 该工作流保证两平台使用**同一份 jar**、同一套初始化 SQL 与端口约定。

## 四、端口总表（各方案一致）

| 端口 | 协议 | 用途 |
|---|---|---|
| 18080 | tcp | WVP Web 页面 / 接口 |
| 5060 | tcp+udp | SIP 信令（设备注册） |
| 9092 | tcp | ZLM HTTP（播流 http-flv/ws-flv 与 API） |
| 554 | tcp | RTSP |
| 1935 | tcp | RTMP |
| 20000 | tcp+udp | RTP 单端口收流（默认模式，SSRC 区分流；三方案统一） |
| 30000-30500 | tcp+udp | RTP 多端口收流（Linux 可选，`RTP_ENABLE=true` 时开放） |
| 8000 | udp+tcp | WebRTC |
| 9000 | udp | SRT（默认关闭） |

> ⚠️ 必须放行 udp 的 `5060` 与 `20000`，且 `Stream_IP`/`SDP_IP` 必须为服务器真实 IP，
> 否则会出现「页面能打开、视频无法播放/设备收流失败」。

## 五、目录结构

```
wvp/
├── README.md                       # 本文件（总览）
├── windows/                        # Windows：原生进程，仅离线版（无 Docker/容器）
│   ├── README.md                   #   制作与使用说明
│   ├── pack.ps1                    #   离线包制作（联网 Windows 机运行）
│   ├── install.ps1 / start.ps1 / stop.ps1   # 包内入口（安装 / 启动 / 停止）
│   ├── config/                     #   application.yml / zlm-config.ini 模板（@占位符@）
│   ├── mysql/init/                 #   官方 3.0.0 初始化 SQL
│   ├── cache/                      #   组件缓存（jre21/mysql/redis/zlm/wvp.jar，gitignore）
│   ├── build/ dist/                #   打包暂存与产物（gitignore）
│   └── runtime/                    #   运行时生成：组件/数据/日志（gitignore）
└── linux/                          # Linux：Docker 容器化（在线 / 离线两形态）
    ├── README.md                   #   两种形态总说明
    ├── online/                     #   在线版：现场构建 wvp 镜像 + 拉取依赖镜像
    │   ├── README.md               #     详细使用说明
    │   ├── .env                    #     环境变量（部署前修改）
    │   ├── docker-compose.yml      #     bridge 网络编排（通用）
    │   ├── docker-compose.host.yml #     host 网络编排（Linux 生产）
    │   ├── config/                 #     WVP 与 ZLM 配置（映射进容器）
    │   ├── wvp-image/              #     wvp 镜像 Dockerfile 与 maven 加速配置
    │   └── mysql/init/             #     官方 3.0.0 初始化 SQL
    └── offline/                    #   离线版：镜像 tar 直接打进包
        ├── README.md               #     制作与使用说明
        ├── pack.sh                 #     离线包制作（联网 Linux 机运行）
        ├── install.sh / start.sh / stop.sh  # 包内入口（加载镜像 / 启动 / 停止）
        └── dist/                   #     产物：wvp-linux-offline-3.0.0.tar.gz（gitignore）
```

## 六、关键设计说明

1. **前端内置**：Linux 镜像构建流程为 `git clone → npm run build:prod（产物输出到 src/main/resources/static）→ mvn package`，
   因此运行 jar 自带完整前端（Vue）；Windows 方案使用从该镜像提取的 jar，同样自带前端。
2. **媒体地址直达**：WVP 生成的播流/下载地址均为 `http://{Stream_IP}:9092/...` 直连 ZLM 形式，
   只要 9092 映射到宿主机（Linux bridge）或直接监听（host/Windows 原生）即可播放，无需反向代理。
3. **密钥/ID 一致性**：
   - ZLM 的 `[api] secret` 与 WVP 的 `media.secret` 必须一致（Linux 由 `.env` 的 `ZLM_SERCERT` 统一注入；
     Windows 由 `start.ps1 -ZlmSecret` 同步写入两份配置）。
   - ZLM 的 `mediaServerId` 与 WVP 的 `media.id` 必须一致（默认 `zlmediakit-01`）。
4. **收流端口语义**：`media.rtp.enable=false`（默认）时，WVP 直接使用 `media.rtp-proxy-port` 作为收流端口，
   因此 ZLM 配置 `[rtp_proxy] port` 必须与之一致（默认统一 20000，避开 10000 的常见占用；
   Linux 由 compose 的 `MediaRtp` 环境变量注入，Windows 由 `start.ps1` 的 `$ZlmRtpPort` 渲染）。
5. **数据库参数**：MySQL 强制 `lower_case_table_names=1`（WVP 表名要求），且必须在数据目录初始化前设定
   （Linux 由 compose command 传入；Windows 由 start.ps1 生成的 my.ini 设定）。
6. **构建环境**：前端 Node20（官方 CI 同款）、后端 JDK21 + Maven 3.9；npm 使用 npmmirror、maven 使用阿里云镜像；
   源码默认从 gitee 拉取（`WVP_GIT_URL` 可切换为 GitHub）。
7. **ZLM 二进制来源**：Linux 取自官方镜像 `zlmediakit/zlmediakit:master`；Windows 离线包内置社区编译版
   单文件（Gitee 免登录直链，约 4MB，已实测运行；亦可自行编译替换，见 `windows/README.md` §4.1）。
8. **离线包机制**：本质是"提前固化组件/镜像"——Windows 包把 JRE/MySQL/Redis/ZLM/jar 预置于 `runtime\` 下
   （安装走 `-SkipDownload -InstallOnly`，启动/停止走 start/stop）；Linux 包把四个镜像 `docker save`
   为 tar（目标机 `install.sh` 加载 → `start.sh` 启动 → `stop.sh` 停止）。

## 七、交付清单

- [x] `windows/`：**原生进程离线版**（无 Docker 依赖）——`pack.ps1` 制作含全部组件（JRE21 / MySQL8 / Redis / ZLMediaKit / wvp.jar）的离线 zip；包内 `start.ps1 / stop.ps1 / install.ps1` 一键安装与编排、配置模板、官方初始化 SQL、详细 README
- [x] `linux/online/`：**在线版**——bridge 与 host 两套编排、wvp 镜像构建文件、WVP/ZLM 配置、官方初始化 SQL、详细 README
- [x] `linux/offline/`：**离线版**——`pack.sh` 构建并导出四镜像为 tar、连同编排/配置/入口脚本打包 tar.gz；`install.sh / start.sh / stop.sh` 目标机三步入场
- [x] 官方 3.0.0 初始化 SQL（`wvp-init-3.0.0.sql`，32725 字节，与上游一致）收录于两平台方案

## 八、重要提示

- 本项目文件均基于官方仓库 **master（v3.0.0）** 的实际代码与配置核对编写，实测情况如下：
  · Windows 离线包已完整实测：联网制作（含 wvp.jar）→ 离线解压 → start.bat（组件解压/配置生成/数据库初始化/四进程启动）→
    WVP 页面 HTTP 200、ZLM API 正常、端口监听齐全 → stop.bat 全部停止 —— 绿色版闭环通过；
  · Linux 离线包制作流程已在 Docker 环境实测（镜像构建 → save → 打包），目标机 `install/start` 未做端到端实跑，
    脚本已通过 bash 语法校验（组件 URL 均已逐条核实有效性）。
  首次部署请预留时间并按各 README 中的「快速开始 → 日志观察 → 验证」步骤执行；
  若构建或启动报错，请先按 README 的 FAQ 排查，并将组件日志（`docker logs` / `runtime\logs\`）附上再寻求支持。
- 所有默认密码（平台 admin/admin、MySQL、Redis、SIP、ZLM secret）仅供首次启动，部署后请立即修改。
- 升级/重建前请备份数据目录：Linux 在线版在 `linux/online/data/`、离线版在部署目录 `./data`；Windows 在 `windows\runtime\data\`。