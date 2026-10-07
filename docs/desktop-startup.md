# 桌面启动

Hyprland 的 `hyprland/execs.lua` 直接启动主 Quickshell 界面，由主界面创建壁纸与条栏。

- 主界面只创建当前选中的 panel family。`IllogicalImpulseFamily.qml` 优先创建壁纸、条栏、锁屏、通知、概览和授权界面；侧栏等辅助面板通过 URL 异步加载。
- 剪贴板刷新、壁纸目录预加载和更新服务的显式初始化延后到 family 创建之后。功能本身仍可按需初始化。

使用 URL 加载而不是内联 `Component`，才能将异步面板的加载与编译移到后台。[Qt Loader 文档](https://doc.qt.io/qt-6/qml-qtquick-loader.html#asynchronous-prop)说明了这一行为。这里保留了模块 import 声明，用于 Quickshell 生成虚拟 `qmldir`；删除这些声明会导致动态加载时找不到相邻类型。

左侧栏通过 Loader 的 `loaded` 信号附加内容，避免异步初始化时先访问尚未创建的窗口。锁屏、通知、授权和 Win 概览的处理器保持同步创建。

## 验证

```sh
qs -c ii list
qs -c ii ipc call lock state
qs -c ii ipc call search state
hyprctl layers -j
```

每个输出应有正常的 `quickshell:background` 壁纸图层，锁屏和概览的 IPC 应能正常响应。

会话内重启测试只能比较 Quickshell 本身，不包含登录管理器交接、显示器初始化或冷缓存耗时。完整登录时间应在下一次正常登录后从登录管理器、Hyprland 和 Quickshell 日志一起确认。
