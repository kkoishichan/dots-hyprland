# 不依赖 Plasma 的桌面

本机使用 Arch Linux，以下依赖方案对应 `sdata/dist-arch`。

Hyprland 和 Quickshell 使用独立的桌面服务；Dolphin、Ark 等 KDE 应用使用 Qt、KDE Frameworks、Breeze 和 Darkly。

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

安装所需桌面依赖后，应用配置：

```sh
python3 tools/desktop-config.py deploy
python3 ~/.config/quickshell/ii/scripts/colors/apply-qt-theme.py
hyprctl reload
QT_QPA_PLATFORMTHEME=qt6ct XDG_MENU_PREFIX=arch- dbus-update-activation-environment --systemd QT_QPA_PLATFORMTHEME XDG_MENU_PREFIX
XDG_MENU_PREFIX=arch- kbuildsycoca6 --noincremental
```

生成颜色前需已存在 Matugen 的 `~/.local/state/quickshell/user/generated/colors.json`。门户配置变化后重启用户的 `xdg-desktop-portal.service`；切换主题集成后重启 Quickshell。已启动应用仍可能使用旧环境，重新登录后统一生效。

参考：[ArchWiki 门户配置](https://wiki.archlinux.org/title/XDG_Desktop_Portal)、[Dolphin 的应用列表和主题](https://wiki.archlinux.org/title/Dolphin)、[Qt QPalette](https://doc.qt.io/qt-6/qpalette.html)。

## 终端与登录主题

Hyprland 的终端候选列表将 Kitty 放在 Foot 前面，默认使用 Kitty。

SDDM 使用独立的 `ii-lock` Qt Quick 主题，与 Quickshell 锁屏同步外观；安装、预览和回退见 [SDDM 登录主题](sddm-theme.md)。
