# 115Docker-Kasm

把 [dream10201/115Docker](https://github.com/dream10201/115Docker) 的 Web 访问层从 **TigerVNC + noVNC** 换成 **KasmVNC 1.5.0**：容器内跑 115 官方 Linux 浏览器 + 轻量桌面（openbox + pcmanfm + tint2），浏览器直接访问 KasmVNC 自带 Web 客户端，不再需要 noVNC 代理。

> 115 Linux 浏览器官方 .deb 只有 **amd64**，因此镜像为 amd64-only。GPL-3.0（继承上游），第三方项目，与 115 官方无关。

## 与原版的差异

| | 原版 115Docker | 本项目 |
|---|---|---|
| Web 桌面 | TigerVNC + noVNC 代理（`novnc_proxy`） | KasmVNC 自带 web 服务器（单进程） |
| 访问 | `http://host:1150/vnc.html`，可无密码 | `http://127.0.0.1:2250/vnc.html`（默认仅 loopback），HTTP Basic 登录（KasmVNC 无匿名模式） |
| 传输 | VNC/RFB over WS | KasmVNC 协议：WS + WebRTC/UDP（低延迟） |
| 编码 | Tight | 自适应矩形/视频模式，H.264 流式（1.5.0，需 GPU） |
| 基础镜像 | `xiuxiu10201/webvnc`（不可审计） | `ubuntu:24.04` + 官方 KasmVNC deb（可复现） |
| 115 下载 | `down.115.com/client/lin/`（已 404） | `down.115.com/client/115pc/lin/`（修复） |
| 密码 | VNC 密码（123456 可用） | Kasm 用户密码 **最少 6 位**，短密码启动直接报错退出 |
| 窗口管理 | 无（tint2 only） | openbox（KasmVNC 客户端缩放/最大化需要 WM） |

KasmVNC 没有 `securitytypes=None`：Web 端必须输入用户名/密码。`VNC_ENABLED=false` 时内置一个便利账号 `kasm/kasm`（生产环境请用 `VNC_ENABLED=true` + 强密码）。

## 预构建镜像（GHCR，amd64）

```bash
docker pull ghcr.io/yorkane/115docker:latest      # :latest / :<115版本> / :amd64 同指一构建
```

由 GitHub Actions 构建（`.github/workflows/build-image.yml`）：push 到 main 触发、每周日 10:00 UTC
定时检查 115 新版本重建（版本记录在 `.github/version`）、也可在 Actions 页手动触发（可指定版本）。
仅构建 `linux/amd64`（115 官方 deb 只发 amd64）。

## 快速开始

```bash
docker build -t 115-kasm:latest .
docker compose up -d
# 默认只监听 127.0.0.1:2250（loopback），通过 SSH 隧道访问：
ssh -L 2250:127.0.0.1:2250 user@<host>
# 本地打开 http://127.0.0.1:2250/vnc.html
# 浏览器弹出登录框：kasm / 123456   （KasmVNC 使用 HTTP Basic 认证）
```

默认 `KVNC_NETWORK_INTERFACE=127.0.0.1`，端口**只绑回环**，局域网/公网直接访问不通；需要暴露到网络时设 `-e KVNC_NETWORK_INTERFACE=0.0.0.0`。

KasmVNC 用 **HTTP Basic 认证**（401 + `WWW-Authenticate`），不是 noVNC 的 token 登录页：打开 URL 即弹浏览器原生登录框。`KVNC_REQUIRE_SSL=false`（默认）时 http/https 都可用；设 `true` 强制 https 并拒绝 http。自签证书以 https 访问时接受一次警告即可（Chrome 输 `thisisunsafe`）。

> 已在 Linux x86_64 + Docker 28 上验证：容器重启自动恢复（Xvnc/openbox/pcmanfm/tint2/115Browser 全链路），`docker restart` 后 18 秒内 Web 可登录，115 浏览器窗口渲染正常。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PASSWORD` | `123456` | Kasm 登录密码（≥6 位，KasmVNC 强制） |
| `VNC_ENABLED` | `true` | `false` = 固定便利账号 `kasm/kasm`（内网/测试用） |
| `VNC_USER` | `kasm` | 登录用户名 |
| `WEB_PORT` | `2250` | KasmVNC Web/WS 监听端口 |
| `KVNC_NETWORK_INTERFACE` | `127.0.0.1` | 监听地址：默认仅回环（SSH 隧道进入），`0.0.0.0` 暴露到网络 |
| `DISPLAY_WIDTH` / `DISPLAY_HEIGHT` | `1920` / `1080` | 虚拟屏幕分辨率 |
| `AUTO_START` | `false` | 启动时自动拉起 115 浏览器 |
| `COOKIE_CID/SEID/UID/KID` | 空 | 115 登录态，注入 115Cookie 扩展（同原版） |
| `KVNC_REQUIRE_SSL` | `false` | `true` 强制 https 并拒绝 http |
| `KVNC_ALLOW_RESIZE` | `true` | 客户端窗口改变虚拟屏幕大小 |
| `KVNC_MAX_FRAME_RATE` | `60` | 最大帧率 |
| `KVNC_RECT_MIN_QUALITY` / `KVNC_RECT_MAX_QUALITY` | `7` / `8` | 自适应画质区间（JPEG quality 0-9） |
| `KVNC_UDP_PUBLIC_IP` | `127.0.0.1` | WebRTC 对外宣告地址；**NAT/远程访问填宿主 LAN IP**（如 `192.168.1.13`），`127.0.0.1` = 仅本机可用 WebRTC，远端自动回落 WS。`auto` 会触发 STUN 探测，失败即退出 |
| `KVNC_FULL_FRAME_UPDATES` | `30` | 周期性整帧刷新帧数（丢包自愈），`none` 关闭 |
| `NFS_START` | `false` | `true` = 容器内自行 `mount -t nfs` 一个导出到 `DOWNLOADS_MOUNT`（宿主机无法 bind NFS 挂载点时用，如 macOS Docker Desktop） |
| `NFS_SERVER` / `NFS_EXPORT` | 空 | NFS 服务器与导出路径，`NFS_START=true` 时必填 |
| `NFS_OPTIONS` | `vers=3,nolock` | 挂载选项（QNAP 走 v3；v4.2 视服务端支持） |
| `DOWNLOADS_MOUNT` | `/root/Downloads` | NFS 挂载点（`NFS_START=true` 时生效） |
| `TZ` / `LC_ALL` | `Asia/Shanghai` / `zh_CN.UTF-8` | 时区 / 中文 |

`KVNC_*` 是 KasmVNC 1.5.0 的环境变量覆盖（`server.allow_environment_variables_to_override_config_settings: true` 已开启），规则为 `KVNC_ + 配置点路径（点换下划线）大写`，可覆盖 [kasmvnc_defaults.yaml](https://github.com/kasmtech/KasmVNC/blob/master/unix/kasmvnc_defaults.yaml) 中任意键，例如 `-e KVNC_ENCODING_VIDEO_STREAMING_MODE_CODEC=h264`。

## 数据卷

| 路径 | 说明 |
|---|---|
| `/etc/115` | 115 浏览器用户数据（登录态、历史），持久化可免重复登录 |
| `/opt/Downloads` | 下载目录 |

## 在 macOS（Apple Silicon）本机运行

见 `docker-compose.local-mac.yml`：镜像 `FROM --platform=linux/amd64`，115 浏览器只有 amd64，靠 Rosetta/binfmt 运行。要点：

- 下载盘（QNAP NFS）在 Mac 上是 automount 的 `/opt/onas/16t4`，Docker Desktop 无法 bind 这种 NFS 挂载点（`/host_mnt/opt/onas` 创建被拒），所以由**容器自己挂 NFS**：`NFS_START=true` + `NFS_SERVER/EXPORT`，容器需 `--cap-add SYS_ADMIN`。compose 里把 `/16t4` 挂到 `/root/Downloads`。
- `network_mode: host`：KasmVNC 绑 `127.0.0.1:2250`，Docker Desktop 的 host 网络与 Mac localhost 共享，所以容器内 loopback-only 即等于 Mac 上 loopback-only，同机的 host 网络 sidecar（如 authz）也能走 `127.0.0.1:2250`。
- 本机跑时记得**先停 aigc 隧道**（`launchctl bootout gui/$(id -u)/com.kate.115kasm-tunnel`）释放 2250，二者不能同时占。
- 登录态：`rsync -a root@<aigc>:/root/115data/ ~/115data/`，compose 用命名卷 `115data:/etc/115`（`/Users` 在 Docker Desktop 共享列表内，bind 可用）。

## 构建参数

| ARG | 默认 | 说明 |
|---|---|---|
| `VERSION` | 自动 | 115 浏览器版本（默认查 appversion API） |
| `KASM_VERSION` | `1.5.0` | KasmVNC 版本 |
| `KASM_DIST` | `noble` | KasmVNC deb 适配发行版（base 换 trixie 时同步改） |

## 验证

```bash
docker exec 115-kasm bash -n /opt/run.sh
docker logs 115-kasm | grep '\[115-kasm\]'
docker exec 115-kasm kasmvncserver -list
docker exec 115-kasm tail -20 "/root/.vnc/$(hostname -s):99.log"
curl -s -u kasm:123456 http://127.0.0.1:2250/vnc.html -o /dev/null -w "%{http_code}\n"   # 200 = 正常
```

WebRTC 不通时（容器网络受限/UDP 被防火墙丢弃）KasmVNC 自动回落 WS，不影响使用；要保持纯 WS 就把 `KVNC_UDP_PUBLIC_IP` 保持为 `127.0.0.1`（`none` 是非法值，`auto` 在 STUN 失败时会直接退出）。
