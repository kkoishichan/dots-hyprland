# SDDM 登录主题

`ii-lock` 将 illogical-impulse 的锁屏外观适配到 SDDM：模糊壁纸、居中数字时钟、底部三个胶囊、Material 密码形状及相同的动画曲线。用户名、紧凑的桌面选择图标和键盘布局位于左侧，电量和电源按钮位于右侧。认证、会话启动与电源操作使用 SDDM 原生接口。

尺寸与锁屏组件保持一致：密码框宽 200，胶囊高 56、内边距 8、间距 10、底边距 20；使用相同的圆角阴影、15 像素输入文字、图标填充规则和时钟/日期间距。背景分别使用工作区缩放和锁屏额外缩放，输入框叠加颜色按 `1 - contentTransparency` 计算，与锁屏的 `Appearance.qml` 一致。

主题使用 Qt 6 的 Qt Quick、Controls、Shapes、Effects 和 Qt5Compat.GraphicalEffects，不导入 Plasma 或 Quickshell 运行时。会话列表由 SDDM 按实际安装情况提供，并沿用 SDDM 记住的会话。系统 PAM 配置及服务启用由本机单独维护，主题安装不修改认证栈。

登录框使用“输入密码”提示，仅提供密码登录。已移除指纹图标和指纹请求状态；所有认证失败均恢复输入焦点，在原位置显示“密码错误”，并使用锁屏的输入框抖动动画。密码仍通过 SDDM 原生接口提交，不在主题内保存或验证。

## 构建和检查

源文件位于 `dots/.local/share/sddm/themes/ii-lock/`，由 `tools/desktop-config.py` 管理。密码形状由 `tools/export-sddm-shapes.cjs` 从已有的 Material 形状库导出，避免另画一套近似图形。生成数据保留 Apache-2.0 许可证；锁屏布局和主题遵循仓库的 GPL-3.0 许可证。

```sh
python3 tools/desktop-config.py deploy
python3 tools/sddm-theme.py build --output /tmp/ii-sddm-preview
python3 tools/check-sddm-theme.py /tmp/ii-sddm-preview/theme
QML_XHR_ALLOW_FILE_READ=1 sddm-greeter-qt6 --test-mode --theme /tmp/ii-sddm-preview/theme
```

构建目录必须是新目录。构建需要 Node.js、Python、Pillow 和 fontconfig；交互检查另外需要 PySide6。检查程序使用模拟 SDDM 后端，核对用户和会话传递、密码清除、重复提交保护、密码失败重试、空密码失败、Escape、键盘布局切换、选择菜单和电源路由；可选的第二个参数指定检查截图路径。软件渲染检查不显示全部图形效果，背景模糊、阴影和圆角遮罩应在实际图形后端中确认。真实 SDDM 测试模式用于验证渲染；它不进行真实登录，密码提交后不会收到真正的认证结果。

## 安装与回退

```sh
pkexec python3 tools/sddm-theme.py install --bundle /tmp/ii-sddm-preview --user YOUR_USER
```

安装时核对构建清单并备份既有主题和选择配置，先在 `/usr/share/sddm/themes/` 下的临时目录中组装新主题，以 `sddm` 账户运行模拟交互检查；检查通过后才替换 `/usr/share/sddm/themes/ii-lock/`，最后写入 `/etc/sddm.conf.d/zz-ii-lock.conf`。检查失败时正在使用的主题保持不变。不重启 SDDM；下次显示登录界面时使用新主题。此前手动安装的 WhiteSur 主题及重复的 KDE 主题选择配置已清理，软件包自带主题保留。安装程序输出回退目录：

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
