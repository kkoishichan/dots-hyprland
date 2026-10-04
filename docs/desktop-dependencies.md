# 不依赖 Plasma 的桌面

本机使用 Arch Linux，以下依赖方案对应 `sdata/dist-arch`。

Hyprland 和 Quickshell 使用独立的桌面服务；Dolphin、Ark 等 KDE 应用可以继续使用。保留这些应用需要的 Qt、KDE Frameworks、Breeze 和 Darkly，不按名称批量删除 KDE 库。

| 功能 | 使用的组件 |
| --- | --- |
| 登录 | SDDM，保留现有主题 |
| 文件管理 | Dolphin、`archlinux-xdg-menu`，`XDG_MENU_PREFIX=arch-` |
| Qt 应用主题 | `qt6ct`，保留现有样式、字体和图标 |
| 屏幕共享和截图门户 | `xdg-desktop-portal-hyprland` |
| 文件选择及其他通用门户 | `xdg-desktop-portal-gtk` |
| 网络设置 | NetworkManager、`nm-connection-editor` |
| 蓝牙设置 | BlueZ、`blueman-manager` |
| 用户资料 | Mugshot |
| 任务管理器 | `gnome-system-monitor` |

`sdata/dist-arch/illogical-impulse-kde` 保留原包名以便升级，但其依赖改为独立工具和 KDE 应用，不再安装 Plasma 设置模块。`illogical-impulse-portal` 使用 Hyprland 与 GTK 门户。

壁纸取色后，`switchwall.sh` 调用 `apply-qt-theme.py`，从 Matugen 的 `colors.json` 生成 qt6ct 调色板，并同步 KDE 应用的颜色设置。生成的调色板、`qt6ct.conf` 和 `kdeglobals` 留在本机。它不再调用 `plasma-apply-colorscheme`。关闭设置中的 Qt 壁纸取色后，这一步仍会跳过。

迁移已有桌面时，先保存系统和主目录快照，安装独立工具与更新后的两个依赖包，再应用配置：

```sh
python3 tools/desktop-config.py deploy
python3 ~/.config/quickshell/ii/scripts/colors/apply-qt-theme.py
hyprctl reload
QT_QPA_PLATFORMTHEME=qt6ct XDG_MENU_PREFIX=arch- dbus-update-activation-environment --systemd QT_QPA_PLATFORMTHEME XDG_MENU_PREFIX
XDG_MENU_PREFIX=arch- kbuildsycoca6 --noincremental
```

生成颜色前需已存在 Matugen 的 `~/.local/state/quickshell/user/generated/colors.json`。门户配置变化后重启用户的 `xdg-desktop-portal.service`；切换主题集成后重启 Quickshell。已启动应用仍可能使用旧环境，重新登录后统一生效。

删除 Plasma 时，根据本机反向依赖生成并审查明确的卸载列表，保留用户应用、登录组件和个人配置。不直接运行全系统孤儿包清理，也不删除整个 KDE/Qt 软件包组。

参考：[ArchWiki 门户配置](https://wiki.archlinux.org/title/XDG_Desktop_Portal)、[Dolphin 的应用列表和主题](https://wiki.archlinux.org/title/Dolphin)、[Qt QPalette](https://doc.qt.io/qt-6/qpalette.html)。

## Sway 备用会话

备用桌面采用 Arch 软件包提供的 `/etc/sway/config` 和 `/etc/sway/config.d/`，使用原生平铺布局、Swaybar、Foot 和 wmenu；不创建用户配置副本，便于继续使用发行版的基础配置。

```sh
sudo pacman -S --needed sway swaybg swayidle swaylock foot wmenu xdg-desktop-portal-wlr
```

注销后在 SDDM 会话菜单选择 Sway。`Win+Enter` 打开 Foot，`Win+D` 打开启动器，`Win+Shift+E` 确认退出。锁屏和闲置管理工具已安装，是否自动运行由基础配置决定。

Hyprland 的终端候选列表将 Kitty 放在 Foot 前面，安装备用桌面的依赖后仍沿用原来的终端。Hyprland 与 Sway 分别使用各自的门户配置。

SDDM 使用独立的 `ii-lock` Qt Quick 主题，与 Quickshell 锁屏同步外观；安装、预览和回退见 [SDDM 登录主题](sddm-theme.md)。

## 密钥环密码同步

使用 GNOME Keyring 保存桌面应用的凭据。SDDM 的 PAM 配置负责使用登录密码解锁 `login` 密钥环；Hyprland 启动密钥环进程本身不会解锁它。

在 Arch Linux 上，备份 `/etc/pam.d/passwd`，确认已安装 `gnome-keyring`，再在现有 `password include system-auth` 后添加：

```pam
password optional pam_gnome_keyring.so use_authtok
```

这样用户通过 `passwd` 修改自己的登录密码时，PAM 会使用旧密码解锁 `login` 密钥环，并将其密码同步为新密码。配置在下次运行 `passwd` 时生效，无需重启。它不会立即修正已经不一致的密码；已有不一致时，在 Seahorse（密码和密钥）中单独修改密钥环密码。由 root 重置用户密码时缺少旧密码，不能按此方式同步。

该行仅处理密码修改；TTY 登录时自动解锁仍需另行配置 `/etc/pam.d/login`。系统 PAM 文件不由用户目录部署工具覆盖，升级时应保留并检查此项。

参考：[GNOME Keyring 的 PAM 集成](https://wiki.gnome.org/Projects/GnomeKeyring/Pam)。
