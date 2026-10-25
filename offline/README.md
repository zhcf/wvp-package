# WVP-PRO 3.0.0 · 离线安装包制作与使用

本目录按平台分为 `windows/` 与 `linux/` 两个子目录，各含四个脚本：
**pack（制作）/ install（安装）/ start（启动）/ stop（停止）**。

| 平台 | 对应方案 | 制作机要求 | 产出物 |
| --- | --- | --- | --- |
| [windows/](windows/) | `../windows/` 原生进程（无 Docker） | Windows + 可联网 | `dist/wvp-windows-offline-3.0.0.zip`（内含全部组件） |
| [linux/](linux/) | `../docker-compose/` 四容器 | Linux + 联网 + Docker | `dist/wvp-linux-offline-3.0.0.tar.gz`（镜像 tar + 编排文件） |

> 离线包只解决"**装什么**"：把组件/镜像提前取回固化；安装与运行逻辑与原方案完全一致
> （Windows 内部为 `start.ps1 -SkipDownload -InstallOnly`；Linux 为 `docker load` + `docker compose up -d`）。

---

## 一、Windows 离线包（offline/windows/）

### 1. 制作（在可联网的 Windows 机器）

```powershell
cd offline\windows
.\pack.ps1                                      # 一键打包：组件与 jar 均从 offline\cache\ 复用（推荐）
.\pack.ps1 -WvpJar D:\wvp\wvp-pro-3.0.0.jar     # 亦可用参数提供 jar（自动缓存到 offline\cache\wvp\）
.\pack.ps1 -SkipDownload                        # 纯离线：组件需已在 offline\cache\
```

| 参数 | 说明 |
| --- | --- |
| `-WvpJar <路径>` | 提供 3.0.0 的 wvp.jar（可选；缺省依次尝试 `windows\runtime\wvp\wvp.jar` 与 `offline\cache\wvp\wvp.jar`，来源非缓存时自动回写缓存供复用） |
| `-ZlmDir <路径>` | 提供完整 ZLMediaKit Windows 运行目录；**默认无需提供**（自动下载社区编译版单文件，约 4MB） |
| `-OutDir <路径>` | 产物输出目录（默认 `offline\dist`） |
| `-SkipDownload` | 不联网：组件需已手动放入 `offline\cache\`（`jre21.zip` / `mysql.zip` / `redis.zip` / `zlm\MediaServer.exe` / `wvp\wvp.jar`） |

打包时自动从仓库 `windows\` 同步 `start.ps1` / `stop.ps1` 副本到本目录，保证包内脚本与仓库方案一致。

### 2. 使用（在无网 Windows 机器）

> 绿色版：解压即用，不写注册表、不装系统服务，全部数据在包内 `runtime\`，删文件夹即卸载。
> 首次运行自动完成：组件解压（JRE/MySQL/Redis）→ 配置生成 → 数据库初始化 → 启动服务。

```
解压 wvp-windows-offline-3.0.0.zip
  1) start.bat     —— 一键：自动安装 + 启动（首次约 2~4 分钟；之后启动约 30~60 秒）
                      浏览器访问 http://<本机IP>:18080（admin / admin）
  2) stop.bat      —— 停止服务
  · 可选分步：先跑 install.bat（仅完成安装并退出，约 1~3 分钟，可先确认无误），再 start.bat
```

包内另有 `离线安装说明.txt`（步骤与常见问题）。多网卡机器：`.\start.ps1 -StreamIp <本机IP>`。

## 二、Linux 离线包（offline/linux/）

### 1. 制作（在可联网且装有 Docker 的 Linux 机器）

```bash
cd offline/linux
chmod +x pack.sh
./pack.sh                    # 构建 wvp 镜像 + 拉取依赖镜像 + docker save + 打包
./pack.sh --skip-build       # 镜像已构建过：跳过构建（加速重复打包）
./pack.sh --skip-pull        # 镜像已拉取过：跳过拉取
```

### 2. 使用（在无网 Linux 机器）

```bash
tar -xzf wvp-linux-offline-3.0.0.tar.gz
cd wvp-linux-offline-3.0.0
./install.sh --stream-ip 192.168.1.105   # docker load 全部镜像 + 替换 .env 三个 IP（不启动）
./start.sh                               # 启动（bridge）；生产推荐 ./start.sh --host
./stop.sh                                # 停止（自动识别部署模式，数据保留在 ./data）
```

## 三、两个组件的获取说明（重要）

| 组件 | 现状 | 获取方式 |
| --- | --- | --- |
| **ZLMediaKit（Windows）** | **无需自备**：可自动获取 | `start.ps1`/`pack.ps1` 自动下载社区编译版（Gitee 免登录直链，V2024.9.14 单文件 ~4MB，已实测编解码与 API 运行正常）；亦可自行编译后 `-ZlmDir` 提供 |
| **wvp.jar（3.0.0）** | 官方无 3.0.0 release 包；Releases 中的 `master-v2.7.4-*` 为 2.7.x 构建，与 3.0.0 库结构不兼容，**勿用** | ① 从 docker-compose 构建的 `wvp-pro:3.0.0` 镜像提取（**jar 跨平台**，推荐）② 自行构建：`git clone` 源码（分支 master，pom 版本 3.0.0）→ `web\` 目录 `npm run build:prod` → `mvn clean package -Dmaven.test.skip=true` |

**推荐工作流（一次备齐两个平台）**：

```bash
# ① 在 Linux 构建机制作 Linux 离线包（同时得到 wvp 镜像）
cd offline/linux && ./pack.sh
# ② 从镜像中提取 jar（含内置前端，跨平台可用）
docker create --name wvp-tmp wvp-pro:3.0.0
docker cp wvp-tmp:/opt/wvp/wvp.jar ./wvp-pro-3.0.0.jar
docker rm wvp-tmp
# ③ 把 jar 拷到 Windows 制作机的 offline\cache\wvp\wvp.jar，直接一键打包
cd offline/windows && .\pack.ps1
#    或以参数首次提供：.\pack.ps1 -WvpJar .\wvp-pro-3.0.0.jar（会自动同步到 cache，后续无需再传）
```

> Linux 离线包的镜像 tar 中已含 `wvp-pro:3.0.0`；`tar -xzf` 后同样可 `docker load` 再 `docker cp` 提取 jar。

## 四、目录结构

```
offline/
├── README.md               # 本文件
├── windows/                # Windows 离线包（对应 ../windows 原生方案）
│   ├── pack.ps1            #   制作：联网 Windows 打包为 zip
│   ├── install.ps1         #   安装入口 = start.ps1 -SkipDownload -InstallOnly（随包分发）
│   ├── start.ps1           #   启动入口：../windows/start.ps1 的同步副本（pack.ps1 自动刷新）
│   └── stop.ps1            #   停止入口：../windows/stop.ps1 的同步副本
├── linux/                  # Linux 离线包（对应 ../docker-compose 四容器方案）
│   ├── pack.sh             #   制作：联网 Linux + Docker 导出镜像并打包
│   ├── install.sh          #   安装入口：docker load + IP 替换（随包分发）
│   ├── start.sh            #   启动入口：docker compose up -d（--host 支持 host 网络）
│   └── stop.sh             #   停止入口：docker compose down（自动识别部署模式）
├── cache/                  # 组件缓存（jre21 / mysql / redis / zlm / wvp.jar；获取一次后重复打包复用；已 gitignore）
├── build/                  # 打包暂存目录（已 gitignore）
└── dist/                   # 产出：两个离线安装包（已 gitignore）
```

## 五、常见问题

**Q：Windows 制作时提示缺少 wvp.jar？**
A：仅当 `windows\runtime\wvp\wvp.jar` 与 `offline\cache\wvp\wvp.jar` 均不存在时出现。取得 3.0.0 jar 后放入 `offline\cache\wvp\wvp.jar`（或重跑 `pack.ps1 -WvpJar <jar>`，会自动回写缓存）即可生成完整包（其余组件缓存复用，无需重新下载）。

**Q：Windows 包内 ZLM 是单文件版，够用吗？**
A：够用：社区编译版为静态编译（无 dll 依赖），已实测编解码器加载与 9092 API 全部正常。如需完整目录（含静态资源），自行编译后 `-ZlmDir` 提供即可替换。

**Q：Linux 制作机磁盘/内存不够？**
A：构建 wvp 镜像约需 2 GB 磁盘（npm + maven 缓存层）+ 建议 4 GB 内存；`docker save` 四个镜像约 2~3 GB。

**Q：离线机器没装 Docker（Linux）？**
A：离线包不含 Docker 引擎本身，需另行获取 Docker 的离线安装包（rpm/deb + compose 插件）并先安装，
   `install.sh` 启动时会自动检查并给出提示。

**Q：离线包里 .env 还是示例 IP？**
A：是的（示例值 `192.168.1.100`）。`./install.sh --stream-ip <真实IP>` 可一键替换；未替换时脚本会打印警告。