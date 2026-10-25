# WVP-PRO 3.0.0 · Windows 原生部署（不依赖 Docker）

在 Windows 上以**原生进程**方式运行 WVP-PRO 全套组件：一个 `start.ps1` 自动完成
组件准备（检测/下载/解压）、MySQL 初始化与四进程编排（MySQL / Redis / ZLMediaKit / WVP-PRO）。
**不依赖 Docker、docker-compose 或 WSL**；组件、数据、日志全部落在本目录 `runtime\` 内，删除即完全卸载。

> 仓库内另一方案：`../docker-compose/`（面向 Linux 服务器的四容器编排）；离线包制作与使用见 `../offline/`。
> 本目录适用于 Windows 原生服务器 / 个人电脑直接部署。

---

## 一、目录结构

```
windows/
├── start.ps1                     一键启动（环境检查→组件准备→初始化→编排→就绪等待）
├── stop.ps1                      一键停止（redis-cli/mysqladmin 优雅停机，失败强制回退）
├── config/
│   ├── application.yml.template  WVP 配置模板（@占位符@ 由 start.ps1 渲染）
│   └── zlm-config.ini.template   ZLMediaKit 配置模板（@占位符@ 由 start.ps1 渲染）
└── mysql/
    └── init/
        └── wvp-init-3.0.0.sql    官方 3.0.0 初始化 SQL（首次启动自动导入）
```

首次运行后自动生成（全部位于 `windows\runtime\`，已加入 .gitignore）：

```
runtime/
├── config\application.yml        渲染后的运行配置（长期调参改这里，重启生效）
├── jre21\ mysql\ redis\ zlm\ wvp\    各组件（自动下载解压，或手动放置）
├── data\                         mysql 数据 / redis 数据 / record 录像
├── logs\                         wvp-console / zlm-console / mysql-error / redis 日志
├── run\                          各进程 PID 文件（stop.ps1 依据）
└── _download\                    组件压缩包缓存（jre21.zip / mysql.zip / redis.zip）
```

## 二、前置要求

| 项目 | 要求 |
| --- | --- |
| 系统 | Windows 10/11、Windows Server 2019+（x64） |
| PowerShell | 5.1+（系统自带即可） |
| 网络 | 可访问 Adoptium / GitHub / MySQL CDN（离线部署见 §4） |
| **ZLMediaKit** | 无需手动准备：`start.ps1` 自动获取社区编译版单文件（见 §3.1） |
| **wvp.jar** | 官方 3.0.0 无 release 包，需按 §3.2 获取一次；放入 `windows\runtime\wvp\` 或 `offline\cache\wvp\` 后长期复用 |

## 三、必选件准备（ZLM 与 wvp.jar）

### 3.1 ZLMediaKit（放 `runtime\zlm\`）

`start.ps1` 在缺少 ZLM 时会**自动下载社区编译版**（Gitee 免登录直链，V2024.9.14，约 4MB 静态编译单文件、无 dll 依赖，已实测可运行）。如需替换或手动准备，任选：

1. 社区编译版（`start.ps1` 默认使用）：[gitee.com/beixiaocai/zlm](https://gitee.com/beixiaocai/zlm)，按版本目录分发（`V2024.9.14.windows` / `V2023.3.25.windows` / `V2022.5.22.windows`），直链如
   `https://gitee.com/beixiaocai/zlm/raw/master/V2024.9.14.windows/MediaServer.exe`。
2. 官方 CI 每日构建（需登录 GitHub 下载）：[issue #483「各平台二进制包下载」](https://github.com/ZLMediaKit/ZLMediaKit/issues/483) 每日期发布 `Windows_master_<日期>` 压缩包（约 85MB，含完整 dll 与静态资源，下载链接 90 天内有效）。
3. 自行编译（产物最干净）：按
   [官方 Windows 编译文档](https://docs.zlmediakit.com/zh/guide/install/compilation_instructions_for_windows_version.html)
   用 Visual Studio 2022 + cmake 编译，产物位于 `ZLMediaKit\release\windows\Release\`，把**运行目录整体**（`MediaServer.exe` + 全部 dll）复制到 `windows\runtime\zlm\`。

> 自行编译/下载完整目录替换时务必包含全部依赖 dll，缺 dll 会导致进程启动即退出（看 `runtime\logs\zlm-console.err.log` 排查）；社区单文件版无此问题，开箱即用。

### 3.2 wvp.jar（放 `runtime\wvp\wvp.jar`）

官方 master（3.0.0）**没有 3.0.0 的现成 release 包**——GitHub Releases 中的 `master-v2.7.4-日期.zip` 为 2.7.x 系列构建（jar 与 3.0.0 数据库结构不兼容，**请勿使用**）。获取 3.0.0 jar 任选一种方式：

1. 从 docker-compose 方案构建的 wvp 镜像中提取（jar 跨平台、含内置前端，最省事）：
   在 Linux 构建机执行 `docker compose build wvp` 后：
   ```bash
   docker create --name wvp-tmp wvp-pro:3.0.0
   docker cp wvp-tmp:/opt/wvp/wvp.jar ./wvp-pro-3.0.0.jar
   docker rm wvp-tmp
   ```
2. 自行构建：`git clone` 源码（gitee/github `648540858/wvp-GB28181-pro`，分支 master，pom 版本 3.0.0），
   先在 `web\` 目录 `npm run build:prod`（前端打入 jar），再 `mvn clean package -Dmaven.test.skip=true`，
   产物为 `target\wvp-pro-3.0.0-*.jar`。
3. 首次启动时用参数指定已有 jar：`.\start.ps1 -WvpJar D:\download\wvp-pro-3.0.0.jar`
   （会自动复制到 `runtime\wvp\wvp.jar`，之后无需再传）。
4. 离线包打包：jar 放入 `offline\cache\wvp\wvp.jar` 后运行 `offline\windows\pack.ps1` 即自动打入包内；
   `pack.ps1 -WvpJar <路径>` 提供时也会自动回写该缓存，后续打包无需再传。

> jar 需自带前端（构建时先 `npm run build:prod`），否则访问 18080 只有接口没有页面。

## 四、快速开始

```powershell
cd windows
powershell -ExecutionPolicy Bypass -File .\start.ps1
```

（若本机已放行脚本执行策略，可直接 `.\start.ps1`。）

> 绿色版特性：不写注册表、不装系统服务；组件/数据/日志全部位于本目录 `runtime\`，删除目录即完全卸载。
> 首次运行自动完成全部安装步骤（下载/解压组件 → 生成配置 → 初始化数据库 → 启动服务），无需先"安装"再"启动"。

首次运行自动完成：下载/解压 JRE21+MySQL8+Redis → 生成配置 → 启动 MySQL 并导入表结构（约 1 分钟）→
启动 Redis / ZLM / WVP（WVP 首次约 30~60 秒）→ 全部就绪后打印访问地址。

- 访问：`http://<本机IP>:18080`，默认账号 `admin / admin`
- 停止：`.\stop.ps1`
- 重启：`.\stop.ps1; .\start.ps1`（或 `.\start.ps1 -Force`）
- 多网卡/多 IP 机器请显式指定对外 IP：`.\start.ps1 -StreamIp 192.168.1.105`

### 组件自动下载源

| 组件 | 版本 / 来源 | 大小 |
| --- | --- | --- |
| JRE 21 | 系统已有 Java 21+ 则直接用；否则下载 Eclipse Temurin JRE 21（Adoptium 官方 API） | ~45MB |
| MySQL | 8.0.46 winx64 zip（MySQL CDN；失败自动切换 dev.mysql.com → 阿里镜像 8.0.28） | ~200MB |
| Redis | tporadowski/redis v5.0.14.1 Windows 版（GitHub Release） | ~12MB |

> 下载源定义在 `start.ps1` 顶部（`$JreUrl / $MysqlUrlCandidates / $RedisUrl` 与 4.4 节的 ZLM 社区版直链），网络受限时可替换为内网镜像。

### 离线部署（-SkipDownload）

1. 在有网机器按**固定文件名**下载三个压缩包放入 `runtime\_download\`：
   `jre21.zip`（Temurin JRE21 Windows x64 zip）、`mysql.zip`（mysql-8.x-winx64.zip）、`redis.zip`（Redis-x64-5.0.14.1.zip）
2. 准备 ZLM 与 wvp.jar：ZLM 可先在联网机器运行一次 `start.ps1` 自动下载（见 §3.1）；wvp.jar 按 §3.2 获取后放入 `runtime\wvp\wvp.jar`
   · 更省事的替代：直接使用 `offline\windows\pack.ps1` 生成的离线包，已将 JRE/MySQL/Redis/ZLM/wvp.jar 全部内置，离线机器解压后 install.bat → start.bat 即可（见 `offline\README.md`）
3. 执行 `.\start.ps1 -SkipDownload`（该模式不发起任何下载，缺失项报错并提示放置路径）

## 五、端口与默认账号

| 用途 | 端口 | 说明 |
| --- | --- | --- |
| WVP Web/API | 18080 tcp | 浏览器访问、ZLM hook 回调 |
| SIP 信令 | 5060 tcp+udp | 设备注册/信令 |
| ZLM HTTP | 9092 tcp | 播流（http-flv/ws-flv）与 API |
| RTSP / RTMP | 554 tcp / 1935 tcp | 标准流媒体 |
| RTP 收流（单端口） | 10000 tcp+udp | SSRC 区分流，默认模式 |
| RTC / SRT | 8000 tcp+udp / 9000 udp | WebRTC / SRT |

| 账号 | 默认值 |
| --- | --- |
| WVP 管理员 | `admin / admin` |
| SIP 设备接入 | 服务器 ID `34020000002000000001`，域 `3402000000`，密码 `12345678` |
| MySQL | root `wvp_root_123456`；业务库 `wvp`，账号 `wvp / wvp_123456` |
| Redis | 密码 `wvp_redis_123456`（DB 1，仅监听 127.0.0.1） |
| ZLM API 密钥 | `wvppro-zlm-3.0.0-9f3a7c2e5b1d4068a1c9` |

> MySQL/Redis 均只绑定 127.0.0.1（不对局域网开放）；WVP/SIP/ZLM 对局域网开放，生产环境请在防火墙放行 5060/10000 等端口。
> 修改端口：编辑 `start.ps1` 顶部端口变量，并**同步修改 `stop.ps1` 顶部**（两处保持一致）。

## 六、脚本参数

### start.ps1

| 参数 | 说明 |
| --- | --- |
| `-StreamIp <IP>` | 对外展示/信令使用的本机 IP（默认自动探测；多网卡建议显式指定） |
| `-WvpJar <路径>` | 已有 jar 路径（首次自动复制到 `runtime\wvp\wvp.jar`） |
| `-SipPassword <密码>` | 设备注册密码（默认 `12345678`，仅首次初始化写库） |
| `-MysqlRootPassword` / `-MysqlPassword` / `-RedisPassword` | 各密码（默认内置值，仅首次初始化写库） |
| `-ZlmSecret <密钥>` | ZLM API 密钥（同步写入 WVP 与 ZLM 配置） |
| `-SkipDownload` | 纯离线模式：不下载，组件需已就位 |
| `-InstallOnly` | 仅安装不启动：组件/配置/数据库就绪后停止临时 MySQL 并退出（离线包 install.bat 即调用此模式） |
| `-Force` | 已在运行时先停止再启动（等价先执行 `stop.ps1`） |

### stop.ps1

```powershell
.\stop.ps1               # 停止全部（顺序 wvp→zlm→redis→mysql，优先优雅停机）
.\stop.ps1 -Quiet        # 静默模式（start.ps1 -Force 内部调用）
```

## 七、数据与重置

- 数据目录：`runtime\data\`（`mysql\` 数据库、`redis\` 快照、`record\` 录像文件）
- 重建数据库：删除 `runtime\data\mysql\` 后重新 `.\start.ps1`（重新导入表结构与初始数据，可同时更换密码参数）
- 完全卸载：`.\stop.ps1` 后直接删除 `windows\runtime\` 即可（无注册表、无系统服务、无开机自启）

## 八、常见问题（FAQ）

**Q：提示"禁止运行脚本"或"无法加载文件 start.ps1"？**
A：PowerShell 执行策略限制。用 `powershell -ExecutionPolicy Bypass -File .\start.ps1` 运行，
   或先执行 `Set-ExecutionPolicy -Scope Process Bypass` 再运行。

**Q：脚本输出中文乱码？**
A：两个 ps1 均为 UTF-8 带 BOM 编码（PowerShell 5.1 识别中文脚本的要求）。请勿用工具改成 ANSI/GBK。

**Q：端口被占用？**
A：3306/6379/18080/9092 被占用为致命错误（脚本中止并提示）；5060/554/1935/10000/8000 被占用仅警告（对应功能不可用）。

**Q：ZLM 启动失败 / 端口 9092 无响应？**
A：① 确认 `runtime\zlm\MediaServer.exe` 及全部 dll 完整；② 查 `runtime\logs\zlm-console.err.log`；
   ③ 命令行为 `MediaServer.exe -c config.ini -l 0`，工作目录即 `runtime\zlm\`。

**Q：需要 ffmpeg（截图/转推）？**
A：下载 Windows 版 `ffmpeg.exe` 放入 `runtime\zlm\` 即生效（模板默认 `bin=./ffmpeg.exe`）；
   不放只影响截图/转推，不影响主流程。

**Q：想长期调整配置（如开启 HLS、多端口收流）？**
A：运行期配置位于 `runtime\config\application.yml` 与 `runtime\zlm\config.ini`（由模板渲染生成，重启生效）。
   若要改默认值（影响下次重新生成），同步修改 `windows\config\*.template`。

**Q：Java 21 系统已装，还会下载 JRE 吗？**
A：不会。脚本优先使用系统 `java`（版本 ≥21）；仅当系统无 Java 21+ 时才下载内置 JRE21。

## 九、安全性说明

- 全部组件以当前用户权限运行普通进程，不注册系统服务、不写注册表、不开机自启。
- MySQL/Redis 仅监听本机回环地址；WVP 等默认密码仅供首次启动，生产环境请立即修改全部密码与 `-ZlmSecret`。
- 生产环境建议：修改默认密码 → 用 `-StreamIp` 固定对外 IP → 防火墙放行 SIP 5060(tcp/udp) 与 RTP 10000(tcp/udp) → 视频链路使用 `http://IP:9092` 直连播放。