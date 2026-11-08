# My Toolbox

Debian/Ubuntu 单文件一键运维工具箱，仿照 kejilion.sh 的交互形态，功能按需逐个搬运/改写。

## 一键运行

```bash
# 直连 GitHub
bash <(curl -sL https://raw.githubusercontent.com/baiye4857/ToolBox/main/toolbox.sh)

# 国内加速（ghproxy 类前缀，可自行替换）
TB_MIRROR="https://ghproxy.net/" bash <(curl -sL https://raw.githubusercontent.com/baiye4857/ToolBox/main/toolbox.sh)
```

进入交互菜单时会自动检查更新（网络失败静默跳过，不阻塞使用）。安装为常驻命令可直接执行：

```bash
bash <(curl -sL https://raw.githubusercontent.com/baiye4857/ToolBox/main/toolbox.sh) install
# 之后输入 tb 即可启动
tb
```

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
2. `toolbox.sh` 顶部 `TB_RAW_URL` 已配置为 baiye4857/ToolBox 的 raw 地址；更换仓库时同步修改。
3. 以后每次改完 push 到 main，用户端进入菜单自动检查更新，也可手动 `tb update`；建议用 git tag 管理版本并同步修改 `TB_VERSION`。

## 如何添加/搬运一个功能

固定流程（脚本 `功能区` 注释里也有同样说明）：

1. 在功能区写 `tb_feat_xxx()` 函数；特权动作先 `tb_require_root`，不可逆动作先 `tb_confirm`。
2. 搬运 kejilion 代码时，函数头必须保留来源注释，写明原文件与行号：
   ```bash
   # 来源：基于 kejilion/sh（Apache-2.0，https://github.com/kejilion/sh）
   #       cn/kejilion.sh Lxxxx–Lxxxx 改写，版权归原项目所有
   ```
3. 在 `tb_main_menu` 的 `case` 注册菜单编号，在 `tb_cli_dispatch` 注册命令（支持中文别名）。
4. **不要搬运**：`send_stats` 埋点、`permission_granted` 自改脚本逻辑、自动更新 crontab（本骨架用显式 `tb update` 代替）。
5. 若功能本质是调用上游脚本（如 bench.sh、WARP、重装脚本），优先自己写薄封装指向官方上游，并在 NOTICE 登记上游许可证。
6. 测试建议：新开一台一次性 VPS 或用云厂商快照，验证菜单路径与失败回滚。

## 功能清单

### 主菜单

| 编号 | 功能 | 来源 | 说明 |
|---|---|---|---|
| 1 | 系统信息查询 | 改写自 kejilion `linux_info` | CPU/内存/磁盘/流量/网络算法/IP 归属等，在线查询失败不影响本地信息 |
| 2 | 系统清理 | 改写自 kejilion `linux_clean` | apt 无用依赖、缓存清理，journal 日志收缩需确认 |
| 3 | 测试脚本合集 | 改写自 kejilion `linux_test` | 17 项上游测试脚本的薄封装，见下表 |
| 4 | 系统工具 | 见下 | 14 项子功能 |
| TB | 高级功能 | 本工具箱自写 | 子菜单含「检查更新」与「卸载 ToolBox」，输入 TB 或 tb 均可 |

### 高级功能（菜单输入 TB）

| 编号 | 功能 | 说明 |
|---|---|---|
| 1 | 检查更新 | 从 GitHub raw 下载最新版，校验 shebang 后替换，旧版备份为 .bak；CLI 命令 `tb update` |
| 2 | 卸载 ToolBox | root 权限 + 确认后执行：删除 /usr/local/bin/tb(.bak)、sshd/resolv.conf 的 .tb.bak、/root/reinstall、/backups、/root/toolbox.sh 与当前目录 toolbox.sh，完成后退出；CLI 命令 `tb uninstall` |

启动菜单时的自动检查更新只比对版本号，发现新版本会询问是否更新；无 curl、超时或网络失败时静默跳过。

### 系统工具（菜单内 1–17 连续编号）

| 编号 | 功能 | 来源 | 本工具箱的处理方式 |
|---|---|---|---|
| 1 | 修改SSH连接端口 | kejilion 6 `new_ssh_port` | 备份配置、sshd -t 校验、先放行防火墙再重启、监听确认 |
| 2 | 优化DNS地址 | kejilion 7 `set_dns_ui` / `set_dns` | 国内外预设与手动输入；不使用 chattr 锁定 |
| 3 | 切换优先ipv4/ipv6 | kejilion 10 `prefer_ipv4` | 通过 gai.conf 调整；**不搬**第三方 jhb.ovh 修复脚本 |
| 4 | 查看端口占用状态 | kejilion 11 内联命令 | `ss -tulnape` |
| 5 | 修改虚拟内存大小 | kejilion 12 `add_swap` | fallocate（dd 回退）+ mkswap + fstab |
| 6 | 修改主机名 | kejilion 18 内联逻辑 | hostnamectl 并同步 /etc/hosts |
| 7 | 切换系统更新源 | kejilion 19 `run_linuxmirrors_manual` | 下载 linuxmirrors.cn/main.sh 到临时文件执行 |
| 8 | SSH防御程序 | kejilion 22 `fail2ban_panel` | apt 安装 fail2ban + 自写 jail.local，可查看/解封/卸载 |
| 9 | 用户密钥登录模式 | kejilion 24 `sshkey_panel` / `sshkey_on` | ed25519 生成、粘贴/GitHub/URL 导入、仅密钥模式切换 |
| 10 | 修复OpenSSH高危漏洞 | kejilion 26 第三方编译脚本 | **改为 apt 安全仓库升级** openssh，更可控 |
| 11 | Linux系统内核参数优化 | kejilion 28 `Kernel_optimize` | 自写 sysctl 模板：高性能/均衡/网站/还原 |
| 12 | 切换系统语言 | kejilion 31 `linux_language` | locales + locale-gen，英/简中/繁中 |
| 13 | 命令行美化工具 | kejilion 32 `shell_bianse` | 6 套 PS1 配色，标记行管理可干净还原 |
| 14 | 系统备份与恢复 | kejilion 34 `linux_backup` | tar.gz 备份到 /backups，恢复需二次确认 |
| 15 | 基础环境安装 | linuxbox 0 | apt 安装 sudo/curl/wget/tar/zip/ca-certificates；原脚本自安装部分由 `tb install` 承担 |
| 16 | 安装 GOST 环境 | linuxbox 5 | 架构自动识别（原版仅 amd64，现支持 amd64/armv8/armv7/386），systemd 单元改为 simple，配置占位不自动启动 |
| 17 | DD 重装系统 | linuxbox 92 | 下载 leitbogioro InstallNET（GitHub/Gitee）并校验 shebang，终端输入两次新 root 密码（输入可见），确认后执行 `bash InstallNET.sh -debian 12 -pwd 密码` |

### 未搬运 / 已替换

- **kejilion 27 红帽系内核升级（elrepo）**：RHEL 系专属，apt 系统不适用，未放入菜单。
- **测试合集里的 besttrace / Superspeed**：原 git.io 短链已停止服务，用 NextTrace、i-abc 测速、NetQuality 等存活项目替代。
- **linuxbox 其余项**：MTProto/BBRPlus/MTG/GOST 配置等未点名功能不搬；90/91 号 DD 会直接执行远程脚本且硬编码密码，不搬。
-  kejilion 的埋点 `send_stats`、静默自更新 crontab、自改脚本逻辑一律不搬；本工具箱更新只走显式 `tb update`。

## 许可证与归属

- 本项目代码：[Apache License 2.0](LICENSE)
- 搬运自 kejilion/sh 的函数遵循其 Apache-2.0 许可，在函数头与 [NOTICE](NOTICE) 中署名；Apache-2.0 允许修改和再分发，但**不得移除版权、许可与来源声明**。
- 运行时调用的第三方上游脚本各有自己的许可证，随功能上线在 NOTICE 中逐项登记。
