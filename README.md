# WVP-PRO 3.0.0 部署方案（Linux Docker + Windows 原生）

> 为 [WVP-PRO](https://github.com/648540858/wvp-GB28181-pro)（国标 GB28181 视频平台，当前 master 版本为 v3.0.0）
> 提供两套开箱即用的部署方案：**Linux 服务器用 docker-compose 四容器**、**Windows 用原生进程（无 Docker）**，
> 并配套 [`offline/`](offline/README.md) 离线安装包制作工具。官方文档：https://doc.wvp-pro.cn/#/

---

## 一、方案与环境对应

| 对比项 | `docker-compose/` 多容器 | `windows/` Windows 原生 |
|---|---|---|
| 目标环境 | **Linux** 服务器（生产推荐） | **Windows** 10/11、Server 2019+ |
| 形态 | wvp / zlm / mysql / redis 四个容器 | MySQL/Redis/ZLM/WVP 四个原生进程 |
| 依赖 | Docker + compose 插件 | **仅 PowerShell 5.1+，无 Docker/WSL** |
| 网络模式 | bridge（通用）或 host（Linux 生产，SIP/RTP 无 NAT 问题）两套编排 | 直接监听宿主机端口 |
| 运行方式 | `docker compose up -d --build` | `.\start.ps1` 一键启动（自动下载组件+初始化数据库） |
| 升级 WVP | 重建 wvp 镜像后 `up -d`，数据/其他组件不动 | 替换 `runtime\wvp\wvp.jar` 后重启 |
| 隔离性 | 容器进程/资源隔离，可分别限资源 | 独立进程，不写注册表、不注册系统服务 |
| 前置准备 | 无（镜像构建全自动，含前端编译） | 需准备 wvp.jar（官方无 3.0.0 release 包，见 windows/README.md §3.2）；ZLMediaKit 由 start.ps1 自动获取。「离线包」则全部组件已内置 |
| 离线部署 | `offline/linux/pack.sh` → 镜像 tar 包（四镜像全内置） | `offline/windows/pack.ps1` → 组件 zip 包（JRE/MySQL/Redis/ZLM/wvp.jar 全内置） |
| 说明文档 | [docker-compose/README.md](docker-compose/README.md) | [windows/README.md](windows/README.md) |

**共同特性**：

- 端口方案一致：`18080 / 5060 / 9092 / 554 / 1935 / 10000 ...`，配置与文档统一。
- 前端随 jar 内置，访问 `http://IP:18080` 即有完整 Web 页面，**无需 nginx**
  （Linux 镜像构建时自动编译前端；Windows 用从该镜像提取的 jar 即可，jar 跨平台）。
- 初始化 SQL 使用官方 3.0.0 版本（`数据库/3.0.0/初始化-mysql-3.0.0.sql`，原样收录）。
- 默认单端口收流模式（RTP 10000，SSRC 区分流），热点端口少、NAT 简单。

## 二、快速开始

### 方案一：Linux（docker-compose 四容器）

```bash
cd docker-compose
# 1. 修改 .env：把 Stream_IP / SDP_IP / SIP_ShowIP 改为服务器真实 IP，并修改各默认密码
# 2. 构建并启动（首次构建 wvp 镜像约 10~30 分钟）
docker compose up -d --build
# 3. 访问 http://<服务器IP>:18080 ，默认账号 admin / admin
```

Linux 生产环境（host 网络，SIP/RTP 无 NAT 问题）：

```bash
docker compose -f docker-compose.host.yml up -d --build
```

### 方案二：Windows 原生（不依赖 Docker）

```powershell
cd windows
# 1. 准备 wvp.jar 放入 windows\runtime\wvp\（或用 -WvpJar 参数指定；可从 Linux 构建的 wvp 镜像提取，详见 windows/README.md §3.2）
#    ZLMediaKit 无需手动准备：start.ps1 会自动获取社区编译版单文件（详见 windows/README.md §3）
#    （无网络环境可改用离线包，组件全内置：见 §三）
# 2. 一键启动：自动下载 JRE21/MySQL8/Redis（首次约 5~10 分钟）并初始化数据库
powershell -ExecutionPolicy Bypass -File .\start.ps1
# 3. 访问 http://<本机IP>:18080 ，默认账号 admin / admin；多网卡请加 -StreamIp <IP>
# 4. 停止：.\stop.ps1
```

> Windows 方案全程原生进程（无 Docker），组件/数据/日志均在 `windows\runtime\` 内，删除即完全卸载。

### 设备接入（两套方案相同）

| 参数 | 值 |
|---|---|
| SIP 服务器 ID | `34020000002000000001` |
| SIP 域 | `3402000000` |
| SIP 服务器地址 | `<服务器IP>` |
| SIP 服务器端口 | `5060` |
| 注册密码 | 默认 `12345678`（docker-compose 在 `.env` 修改；Windows 方案用 `start.ps1 -SipPassword` 指定） |

## 三、离线安装包（无网络环境）

[`offline/`](offline/README.md) 提供两个离线包的制作脚本（在**有网机器**运行，产出拷贝进隔离环境使用）：

| 离线包 | 对应方案 | 制作机 | 目标机安装 |
|---|---|---|---|
| `wvp-windows-offline-3.0.0.zip` | windows/ 原生 | Windows + 联网 | 解压 → `start.bat`（绿色版一键安装+启动；亦可先 `install.bat` 分步）→ `stop.bat`（停止） |
| `wvp-linux-offline-3.0.0.tar.gz` | docker-compose/ 四容器 | Linux + 联网 + Docker | 解压 → `./install.sh --stream-ip <IP>` → `./start.sh` → `./stop.sh` |

```bash
# Linux 离线包（在联网 Linux 制作机执行：自动构建 wvp 镜像 + 拉取依赖镜像 + docker save）
cd offline/linux && ./pack.sh

# Windows 离线包（在联网 Windows 制作机执行：自动获取 JRE21/MySQL8/Redis/ZLMediaKit + 打包）
cd offline\windows; .\pack.ps1                  # jar 已缓存时一键打包；首次可 -WvpJar <路径> 提供（自动回写缓存）
```

> 推荐工作流：先在 Linux 制作 Linux 包（同时得到 `wvp-pro:3.0.0` 镜像）→ `docker cp` 提取跨平台 jar
> → 放入 `offline\cache\wvp\wvp.jar` 后一键打包完整 Windows 包（首次也可 `-WvpJar` 提供，自动回写缓存）。详见 [`offline/README.md`](offline/README.md)。

## 四、端口总表（两套方案一致）

| 端口 | 协议 | 用途 |
|---|---|---|
| 18080 | tcp | WVP Web 页面 / 接口 |
| 5060 | tcp+udp | SIP 信令（设备注册） |
| 9092 | tcp | ZLM HTTP（播流 http-flv/ws-flv 与 API） |
| 554 | tcp | RTSP |
| 1935 | tcp | RTMP |
| 10000 | tcp+udp | RTP 单端口收流（默认模式） |
| 30000-30500 | tcp+udp | RTP 多端口收流（可选，`RTP_ENABLE=true` 时开放） |
| 8000 | udp+tcp | WebRTC |
| 9000 | udp | SRT（默认关闭） |

> ⚠️ 必须放行 udp 的 `5060` 与 `10000`，且 `Stream_IP`/`SDP_IP` 必须为服务器真实 IP，
> 否则会出现「页面能打开、视频无法播放/设备收流失败」。

## 五、目录结构

```
wvp/
├── README.md                       # 本文件（总览）
├── docker-compose/                 # Linux 方案：四容器编排
│   ├── README.md                   #   详细使用说明
│   ├── .env                        #   环境变量（部署前修改）
│   ├── docker-compose.yml          #   bridge 网络编排（通用）
│   ├── docker-compose.host.yml     #   host 网络编排（Linux 生产）
│   ├── config/                     #   WVP 与 ZLM 配置（映射进容器）
│   ├── wvp-image/                  #   wvp 镜像 Dockerfile 与 maven 加速配置
│   └── mysql/init/                 #   官方 3.0.0 初始化 SQL
├── windows/                        # Windows 方案：原生进程（无 Docker 依赖）
│   ├── README.md                   #   详细使用说明
│   ├── start.ps1 / stop.ps1        #   一键启动 / 一键停止（原生进程编排）
│   ├── config/                     #   application.yml / zlm-config.ini 模板（@占位符@）
│   ├── mysql/init/                 #   官方 3.0.0 初始化 SQL
│   └── runtime/                    #   运行时生成：组件/数据/日志（已 gitignore）
└── offline/                        # 离线安装包制作与使用
    ├── README.md                   #   两大平台离线包总说明
    ├── windows/                    #   pack / install / start / stop（对应 windows 方案）
    ├── linux/                      #   pack / install / start / stop（对应 docker-compose 方案）
    └── dist/                       #   产物：两个离线安装包（已 gitignore）
```

## 六、关键设计说明

1. **前端内置**：Linux 镜像构建流程为 `git clone → npm run build:prod（产物输出到 src/main/resources/static）→ mvn package`，
   因此运行 jar 自带完整前端（Vue）；Windows 方案使用从该镜像提取的 jar，同样自带前端。
2. **媒体地址直达**：WVP 生成的播流/下载地址均为 `http://{Stream_IP}:9092/...` 直连 ZLM 形式，
   只要 9092 映射到宿主机（docker-compose bridge）或直接监听（host/Windows 原生）即可播放，无需反向代理。
3. **密钥/ID 一致性**：
   - ZLM 的 `[api] secret` 与 WVP 的 `media.secret` 必须一致（Linux 由 `.env` 的 `ZLM_SERCERT` 统一注入；
     Windows 由 `start.ps1 -ZlmSecret` 同步写入两份配置）。
   - ZLM 的 `mediaServerId` 与 WVP 的 `media.id` 必须一致（默认 `zlmediakit-01`）。
4. **收流端口语义**：`media.rtp.enable=false`（默认）时，WVP 直接使用 `media.rtp-proxy-port=10000`
   作为收流端口，因此 ZLM 配置 `[rtp_proxy] port=10000` 与之严格对应。
5. **数据库参数**：MySQL 强制 `lower_case_table_names=1`（WVP 表名要求），且必须在数据目录初始化前设定
   （Linux 由 compose command 传入；Windows 由 start.ps1 生成的 my.ini 设定）。
6. **构建环境**：前端 Node20（官方 CI 同款）、后端 JDK21 + Maven 3.9；npm 使用 npmmirror、maven 使用阿里云镜像；
   源码默认从 gitee 拉取（`WVP_GIT_URL` 可切换为 GitHub）。
7. **ZLM 二进制来源**：Linux 取自官方镜像 `zlmediakit/zlmediakit:master`；Windows 由 `start.ps1` 自动获取
   社区编译版单文件（Gitee 免登录直链，约 4MB，已实测运行；亦可自行编译替换，见 `windows/README.md` §3.1）。
8. **离线包机制**：`offline/windows/` 与 `offline/linux/` 各含 pack / install / start / stop 四脚本，
   本质是"提前固化组件/镜像"：Windows 包把 JRE/MySQL/Redis/ZLM 预置于 `runtime\` 下
   （安装走 `-SkipDownload -InstallOnly`，启动/停止走 start/stop）；Linux 包把四个镜像 `docker save`
   为 tar（目标机 `install.sh` 加载 → `start.sh` 启动 → `stop.sh` 停止）。

## 七、交付清单

- [x] `docker-compose/`（Linux）：bridge 与 host 两套编排、wvp 镜像构建文件、WVP/ZLM 配置、官方初始化 SQL、详细 README
- [x] `windows/`（Windows）：**原生一键脚本**（start.ps1 / stop.ps1，无 Docker 依赖）：组件自动下载（JRE21 / MySQL8 / Redis Windows 版）、MySQL 自动初始化、四进程编排、配置模板、官方初始化 SQL、详细 README
- [x] `offline/`：**两大平台离线安装包工具**（`windows/` 与 `linux/` 各含 pack / install / start / stop 四脚本）：Windows 自动获取 JRE21/MySQL8/Redis/ZLMediaKit 并打包 zip；Linux 镜像构建/导出 tar.gz；总说明 README
- [x] 官方 3.0.0 初始化 SQL（`wvp-init-3.0.0.sql`，32725 字节，与上游一致）收录于两套方案

## 八、重要提示

- 本项目文件均基于官方仓库 **master（v3.0.0）** 的实际代码与配置核对编写，实测情况如下：
  ZLMediaKit 的 Windows 社区编译版（约 4MB 单文件）已完整实测：下载 → 渲染配置 → 启动 → 9092 API 返回 code 0；
  新版 ZLM 会随机化官方默认 secret，本方案全局默认值已改为自定义串以兼容（各 README 有说明）；
  wvp.jar 官方无 3.0.0 现成包（Releases 中的 2.7.x 构建与 3.0.0 库结构不兼容，勿用），
  Windows 方案未做含 jar 的端到端实跑，jar 获取方式见 `windows/README.md` §3.2；
  Linux 方案因制作环境无 Docker 未实跑，脚本已通过 bash 语法校验（组件 URL 均已逐条核实有效性）。
  首次部署请预留时间并按各 README 中的「快速开始 → 日志观察 → 验证」步骤执行；
  若构建或启动报错，请先按 README 的 FAQ 排查，并将组件日志（`docker logs` / `runtime\logs\`）附上再寻求支持。
- 所有默认密码（平台 admin/admin、MySQL、Redis、SIP、ZLM secret）仅供首次启动，部署后请立即修改。
- 升级/重建前请备份数据目录：docker-compose 的数据在 `docker-compose/data/`，Windows 方案在 `windows\runtime\data\`。