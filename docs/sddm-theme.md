# SDDM 登录主题

`ii-lock` 将 illogical-impulse 的锁屏外观适配到 SDDM：模糊壁纸、居中数字时钟、底部三个胶囊、Material 密码形状及相同的动画曲线。用户和桌面选择位于左侧，电量和电源按钮位于右侧。认证、会话启动与电源操作使用 SDDM 原生接口。

主题使用 Qt 6 的 Qt Quick、Controls、Shapes、Effects 和 Qt5Compat.GraphicalEffects，不导入 Plasma 或 Quickshell 运行时。保留原有 SDDM PAM 配置及密钥环解锁流程。默认提供已安装的所有会话，包括 Hyprland、Hyprland (uwsm-managed) 和 Sway，并沿用 SDDM 记住的会话。

## 构建和检查

源文件位于 `dots/.local/share/sddm/themes/ii-lock/`，由 `tools/desktop-config.py` 管理。密码形状由 `tools/export-sddm-shapes.cjs` 从已有的 Material 形状库导出，避免另画一套近似图形。生成数据保留 Apache-2.0 许可证；锁屏布局和主题遵循仓库的 GPL-3.0 许可证。

```sh
python3 tools/desktop-config.py deploy
python3 tools/sddm-theme.py build --output /tmp/ii-sddm-preview
python3 tools/check-sddm-theme.py /tmp/ii-sddm-preview/theme
QML_XHR_ALLOW_FILE_READ=1 sddm-greeter-qt6 --test-mode --theme /tmp/ii-sddm-preview/theme
```

构建目录必须是新目录。构建需要 Node.js、Python、Pillow 和 fontconfig；交互检查另外需要 PySide6。检查程序使用模拟 SDDM 后端，核对用户和会话传递、密码清除、重复提交保护、失败重试、Escape、选择菜单和电源路由。真实 SDDM 测试模式用于验证渲染；它不进行真实登录，密码提交后不会收到真正的认证结果。

## 安装与回退

```sh
pkexec python3 tools/sddm-theme.py install --bundle /tmp/ii-sddm-preview --user YOUR_USER
```

安装时核对构建清单并备份既有主题和选择配置，然后写入 `/usr/share/sddm/themes/ii-lock/`，以 `sddm` 账户运行模拟交互检查，最后写入 `/etc/sddm.conf.d/zz-ii-lock.conf`（在 `kde_settings.conf` 之后加载）。不重启 SDDM；下次显示登录界面时使用新主题。旧 WhiteSur 主题继续保留。安装程序输出回退目录：

```sh
pkexec python3 tools/sddm-theme.py rollback --backup /var/lib/illogical-impulse/sddm-backups/TIMESTAMP
```

回退也不重启当前会话。若主题加载失败，SDDM 自带的内嵌主题仍可提供登录入口。

## 壁纸与配色同步

`sync-sddm-theme.py` 仅导出选定的壁纸、字体、锁屏参数和颜色到 `/var/lib/illogical-impulse/sddm/`。该独立资源目录由桌面用户维护，SDDM 可读取；主题代码保持 root 所有。完整的个人配置、凭据和运行状态不会复制给登录器，生成资源也不会提交到仓库。

壁纸和配色更新流程会同步这些资源。单独调整字体或时钟设置后，可运行：

```sh
python3 ~/.config/quickshell/ii/scripts/colors/sync-sddm-theme.py --if-installed
```

视频壁纸在登录界面使用其静态缩略图。电量通过读取已检测到的 `/sys/class/power_supply/` 文件更新，因此仅为 SDDM greeter 设置 `QML_XHR_ALLOW_FILE_READ=1`；未增加守护进程。

参考：[SDDM 主题接口](https://github.com/sddm/sddm/blob/v0.21.0/docs/THEMING.md)、[SDDM 多屏视图与内嵌回退](https://github.com/sddm/sddm/blob/v0.21.0/src/greeter/GreeterApp.cpp)。
