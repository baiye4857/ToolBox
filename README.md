# 淘宝工具箱

Debian/Ubuntu 单文件一键运维工具箱，仿照 kejilion.sh 的交互形态。系统工具采用**逐字复制（verbatim vendoring）**：1–3、5–15 对应 kejilion v4.5.17 的全部函数与全局变量原样内嵌；16–19 对应 168.diy/linuxbox.sh 菜单 0/5/92/3 的分支体原样内嵌（其中 19 的菜单入口改为文件式守卫，内嵌库与桥接本身逐字不动）；4（禁用IPv6）为本工具箱自写。两套库均在独立 bash 子进程中运行，不与本工具箱的函数/变量空间混用。

## 一键运行

```bash
# 直连
bash <(curl -sL https://168.diy/sh/toolbox.sh)

# 国内加速（ghproxy 类前缀，可自行替换）
TB_MIRROR="https://ghproxy.net/" bash <(curl -sL https://168.diy/sh/toolbox.sh)
```

**首次运行行为**：以 root 执行上面的无参数命令时（curl|bash 管道方式），会自动完成安装并执行一遍检查更新，等效于先跑 `install` 再跑高级功能里的「检查更新」，随后进入主菜单；非 root 会跳过自动安装并提示，直接运行已安装的 `tb` 或普通 .sh 文件不重复执行。安装为常驻命令也可显式执行：

```bash
bash <(curl -sL https://168.diy/sh/toolbox.sh) install
# 之后输入 tb 即可启动
tb
```

说明：管道方式下脚本已被 bash 整体读入内存、来源 fd 到 EOF，无法复制自身，因此自动安装/更新统一从 `TB_RAW_URL`（https://168.diy/sh/toolbox.sh）下载最新版落到 `/usr/local/bin/tb`，避免写入空文件。

## 支持系统

- Debian 10+ / Ubuntu 20.04+（apt 系），x86_64 与 arm64
- 其他发行版（dnf/apk/pacman）暂不支持

## 仓库结构

```
my-toolbox/
├── toolbox.sh      # 全部逻辑的单文件脚本（菜单 + 功能 + 自安装 + 自更新）
├── README.md
├── LICENSE         # Apache-2.0
└── NOTICE          # 第三方代码归属
```

## 发布到 GitHub

1. 新建仓库（建议公开，raw 才能免登录访问），把本目录推上去：
   ```bash
   cd my-toolbox
   git init
   git add .
   git commit -m "init: toolbox skeleton"
   git branch -M main
   git remote add origin git@github.com:<你的用户名>/<仓库名>.git
   git push -u origin main
   ```
2. `toolbox.sh` 顶部 `TB_RAW_URL` 已配置为 `https://168.diy/sh/toolbox.sh`；更换分发地址时同步修改。
3. 以后每次改完发布新版本，用户端进入菜单自动检查更新，也可手动 `tb update`；建议用 git tag 管理版本并同步修改 `TB_VERSION`。

## 如何添加/搬运一个功能

固定流程（脚本 `功能区` 注释里也有同样说明）：

1. 在功能区写 `tb_feat_xxx()` 函数；特权动作先 `tb_require_root`，不可逆动作先 `tb_confirm`。
2. 搬运 kejilion 代码时，函数头必须保留来源注释，写明原文件与行号：
   ```bash
   # 来源：基于 kejilion/sh（Apache-2.0，https://github.com/kejilion/sh）
   #       cn/kejilion.sh Lxxxx–Lxxxx 改写，版权归原项目所有
   ```
3. 在 `tb_main_menu` 的 `case` 注册菜单编号，在 `tb_cli_dispatch` 注册命令（支持中文别名）。
4. 系统工具采用**逐字库**方式：kejilion 全部代码原样内嵌于 `tb_ensure_kjlib`，linuxbox 完整源与桥接内嵌于 `tb_ensure_lblib`；首次使用时释放到 `/usr/local/share/tb/`（root）或 `~/.cache/tb/`（非 root），分别由 `tb_kj`、`tb_lb` 在独立子进程调用。逐字库内的 `send_stats`、chattr 锁定、防火墙包卸载、自安装命令等均保持上游原始行为。
5. 若功能本质是调用上游脚本（如 bench.sh、WARP、重装脚本），优先自己写薄封装指向官方上游，并在 NOTICE 登记上游许可证。
6. 测试建议：新开一台一次性 VPS 或用云厂商快照，验证菜单路径与失败回滚。

## 功能清单

### 主菜单

| 编号 | 功能 | 来源 | 说明 |
|---|---|---|---|
| 1 | 系统信息查询 | 改写自 kejilion `linux_info` | CPU/内存/磁盘/流量/网络算法/IP 归属等，在线查询失败不影响本地信息 |
| 2 | 系统清理 | 改写自 kejilion `linux_clean` | apt 无用依赖、缓存清理，journal 日志收缩需确认 |
| 3 | 测试脚本合集 | 改写自 kejilion `linux_test` | 17 项上游测试脚本的薄封装，见下表 |
| 4 | 系统工具 | 见下 | 19 项子功能 |
| TB | 高级功能 | 本工具箱自写 | 子菜单含「检查更新」与「卸载 ToolBox」，输入 TB 或 tb 均可 |

### 高级功能（菜单输入 TB）

| 编号 | 功能 | 说明 |
|---|---|---|
| 1 | 检查更新 | 从 `TB_RAW_URL` 下载最新版，校验 shebang 后替换，旧版备份为 .bak；CLI 命令 `tb update` |
| 2 | 卸载 ToolBox | root 权限 + 确认后执行：删除 /usr/local/bin/tb(.bak)、sshd/resolv.conf 的 .tb.bak、/root/reinstall、/backups、/root/toolbox.sh 与当前目录 toolbox.sh，完成后退出；CLI 命令 `tb uninstall` |

启动菜单时的自动检查更新只比对版本号，发现新版本会询问是否更新；无 curl、超时或网络失败时静默跳过。curl|bash 管道首次以 root 运行时，还会先自动执行一遍完整的「检查更新」（下载最新版直接安装，等同 install + 检查更新），见上文「首次运行行为」。

### 系统工具（菜单内 1–19 连续编号）

| 编号 | 功能 | 来源 | 处理方式 |
|---|---|---|---|
| 1 | 修改SSH连接端口 | kejilion 6 `new_ssh_port` | **逐字复制**：原分支交互体 + `new_ssh_port`，含 correct_ssh_config/restart_ssh/open_port 及卸载防火墙包等原始行为 |
| 2 | 优化DNS地址 | kejilion 7 `set_dns_ui` | **逐字复制**，含 chattr 锁定 resolv.conf 等原始行为 |
| 3 | 切换优先ipv4/ipv6 | kejilion 10 `prefer_ipv4` | **逐字复制**：含 IPv4/IPv6 切换、jhb.ovh 第三方修复工具入口 |
| 4 | 禁用IPv6 | 本工具箱自写 | sysctl 写入 `/etc/sysctl.d/60-tb-disable-ipv6.conf`，同菜单可重新启用；CLI `tb ipv6` |
| 5 | 查看端口占用状态 | kejilion 11 内联命令 | 先确保 `ss` 已安装（缺失自动 apt 装 iproute2），随后在主 shell 直接执行 `clear; ss -tulnape`，并暂停显示"按回车键继续"（对应 kejilion 菜单 case 后的 break_end，避免输出被立即清屏）；CLI `tb ports` |
| 6 | 修改虚拟内存大小 | kejilion 12 `add_swap` | **逐字复制**：原分支交互体 + `add_swap` |
| 7 | 修改主机名 | kejilion 18 内联逻辑 | **逐字复制**：hostnamectl 并同步 /etc/hosts |
| 8 | 切换系统更新源 | kejilion 19 `run_linuxmirrors_manual` | **逐字复制**：linuxmirrors 与 switch_mirror 各分支 |
| 9 | SSH防御程序 | kejilion 22 `fail2ban_panel` | **逐字复制** |
| 10 | 用户密钥登录模式 | kejilion 24 `sshkey_panel` | **逐字复制** |
| 11 | 修复OpenSSH高危漏洞 | kejilion 26 | **逐字复制**：下载并执行 kejilion 官方 `upgrade_openssh9.8p1.sh` 第三方编译脚本 |
| 12 | Linux系统内核参数优化 | kejilion 28 `Kernel_optimize` | **逐字复制** |
| 13 | 切换系统语言 | kejilion 31 `linux_language` | **逐字复制** |
| 14 | 命令行美化工具 | kejilion 32 `shell_bianse` | **逐字复制** |
| 15 | 系统备份与恢复 | kejilion 34 `linux_backup` | **逐字复制** |
| 16 | 基础环境安装 | linuxbox 0 | **逐字复制**：sudo apt 安装 sudo/curl/wget/tar/zip，并把 linuxbox.sh 下载到 /usr/bin/lb 与 /usr/bin/linuxbox |
| 17 | 安装 GOST 环境 | linuxbox 5 | **逐字复制**：原版仅 amd64，下载 gost_2.12.0，写 forking 类型 systemd 单元与 start.sh（不自动启动） |
| 18 | DD 重装系统 | linuxbox 92 | 保持 linuxbox 92 的结果（下载后仅提示手动执行 `bash InstallNET.sh -debian 12`，不询问密码、不自动重装）；入口走工具层守卫，**不在菜单内做交互式选择**（避免嵌套菜单内 read 在部分环境失效），自动依次尝试 GitHub→Gitee（TB_MIRROR 优先），下载到临时目录校验非空与 shell 头后落到当前目录，失败明确报错并暂停；内嵌逐字库与桥接字节不动；CLI `tb dd` |
| 19 | 安装 BBRPlus | linuxbox 3 | 逐字库与桥接保持原样；入口改为先下载到临时文件、校验 bash 头后再 `bash 文件`（GitHub 失败自动回退 jsDelivr），避免嵌套进程替换在部分环境打不开菜单；运行的仍是同一上游脚本；CLI `tb bbrplus` |

### 未接入菜单 / 已替换

- **kejilion 27 红帽系内核升级（elrepo）**：逐字库内已包含该函数，但 RHEL 系专属、apt 系统不适用，未在菜单接线。
- **测试合集里的 besttrace / Superspeed**：原 git.io 短链已停止服务，用 NextTrace、i-abc 测速、NetQuality 等存活项目替代。
- **linuxbox 其余项**：MTProto/MTG/GOST 配置等未点名功能不搬；90/91 号 DD 会直接执行远程脚本且硬编码密码，不搬。
- 逐字库内 kejilion 的 `send_stats` 埋点、许可自改逻辑、crontab 等保持原样，仅在库子进程内生效；本工具箱自身的更新仍只走显式 `tb update`，不引入 kejilion 静默自更新。

## 许可证与归属

- 本项目代码：[Apache License 2.0](LICENSE)
- 系统工具 1–3、5–15 为 kejilion/sh（Apache-2.0）v4.5.17 代码的逐字副本，16–19 为 168.diy/linuxbox.sh（许可证未声明）的逐字副本，库块与 [NOTICE](NOTICE) 中保留来源与版本署名；Apache-2.0 允许复制和再分发，但**不得移除版权、许可与来源声明**。
- 运行时调用的第三方上游脚本各有自己的许可证，随功能上线在 NOTICE 中逐项登记。
