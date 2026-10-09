# Hyprland desktop

这是 [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) 的个人 fork，以本机实际使用的 Hyprland 与 Quickshell 配置为准。

定制范围限于桌面和相关组件的配置，以及直接服务于这些配置的维护工具、测试与说明。系统引导、磁盘、账户认证、软件包清理和其他桌面环境的维护记录保存在本机。

在 **设置 → 界面 → 桌面布局** 中选择滚动布局或原版布局（dwindle），即时切换布局、工作区管理、条栏、概览、快捷键和手势。默认使用滚动布局，选择保存在 `~/.config/illogical-impulse/config.json` 的 `desktopLayout` 字段，部署不会覆盖。

滚动模式下，窗口按列横向滚动，每台显示器独立维护纵向动态工作区。Win 与 Win＋Space 打开同一个简洁概览和搜索界面，条栏中间显示带滚动动画的窗口图标，鼠标点击图标时保持原地。原版模式恢复 dwindle 平铺、编号工作区、工作区圆点和网格概览。当前使用 Hyprland **0.56.2（Lua 配置）**。

同时保留中文输入、字体、搜索索引、KDE 托盘共存、锁屏与休眠、飞书会议浮动窗口等现有修正。上游历史、安装器、许可证和署名均保留；上游项目介绍见 [.github/README.md](.github/README.md)。

## 配置与维护

- [`dots/.config/hypr/`](dots/.config/hypr/)：Hyprland 配置和快捷键。
- [`dots/.config/quickshell/ii/`](dots/.config/quickshell/ii/)：Quickshell 组件与服务。
- [`config/managed-files.txt`](config/managed-files.txt)：此 fork 维护的定制文件清单。
- [`config/scrolling-profile.json`](config/scrolling-profile.json)：条栏、概览、字体和语言等界面偏好，应用时合并到已有设置。
- [布局、快捷键和手势说明](docs/scrolling-layout.md)。
- [本机同步、备份和更新上游](docs/maintenance.md)。
- [配套桌面组件与依赖](docs/desktop-dependencies.md)。

当前桌面已安装依赖时，查看或应用定制：

```sh
python3 tools/desktop-config.py status
python3 tools/desktop-config.py deploy --dry-run
python3 tools/desktop-config.py deploy
hyprctl reload
```

应用前会备份实际变更的文件到 `~/.local/state/dots-hyprland/backups/`。Quickshell 会自动加载改动。

新机器先按上游安装说明安装依赖与基础配置，再运行本 fork 的 `deploy`。需要 Python 3、Node.js（模型测试）、Fcitx5 和中文输入扩展；飞书窗口修复使用 `python-xlib`。克隆时初始化子模块：

```sh
git clone --recurse-submodules https://github.com/kkoishichan/dots-hyprland.git
```

## 检查

```sh
node tests/scrolling-workspaces.cjs
python3 -m unittest discover -s tests -p 'test_*.py'
git diff --check
```

GitHub Actions 执行同样的模型和维护工具检查。实际窗口焦点、触摸板、输入法和截图仍需在 Hyprland 会话中验证。
