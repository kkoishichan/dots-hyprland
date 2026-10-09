# 桌面启动

Hyprland 的 `hyprland/execs.lua` 直接启动主 Quickshell 界面，由主界面创建壁纸与条栏。

- 锁屏控制器由主界面直接创建，使用 Quickshell 的 `LazyLoader` 接续已有的锁定连接；锁定状态和界面类型先通过 `PersistentProperties` 恢复，不等待设置文件或桌面面板加载。重载后重新开始认证，不保存已输入的密码；锁定期间切换 panel family 会等到正常解锁后再替换锁屏界面。
- 桌面只创建当前选中的 panel family。`IllogicalImpulseFamily.qml` 优先创建壁纸、条栏、通知、概览和授权界面；侧栏等辅助面板通过 URL 异步加载。
- 剪贴板刷新、壁纸目录预加载和更新服务的显式初始化延后到 family 创建之后。功能本身仍可按需初始化。

使用 URL 加载而不是内联 `Component`，才能将异步面板的加载与编译移到后台。[Qt Loader 文档](https://doc.qt.io/qt-6/qml-qtquick-loader.html#asynchronous-prop)说明了这一行为。这里保留了模块 import 声明，用于 Quickshell 生成虚拟 `qmldir`；删除这些声明会导致动态加载时找不到相邻类型。

左侧栏通过 Loader 的 `loaded` 信号附加内容，避免异步初始化时先访问尚未创建的窗口。通知、授权和 Win 概览的处理器保持同步创建。锁屏不属于设置就绪后才加载的桌面面板，避免重载时销毁锁屏后无法恢复交互。

## 验证

```sh
qs -c ii list
qs -c ii ipc call lock state
qs -c ii ipc call search state
hyprctl layers -j
```

每个输出应有正常的 `quickshell:background` 壁纸图层，锁屏和概览的 IPC 应能正常响应。

`lock state` 的 `locked` 表示界面的锁定请求，`secure` 表示 Wayland 锁定连接已经生效。Quickshell 0.3.2 在成功交接旧锁屏对象时也可能打印 `Session lock object was destroyed without unlocking`，需结合锁定状态、可见界面与认证是否重新开始判断，不能仅凭这条日志认定进程崩溃。

`tests/test_lock_reload.py` 需要通过 `II_LOCK_TEST_ENV` 指定拥有两台输出的独立测试合成器的环境 JSON（`XDG_RUNTIME_DIR`、`WAYLAND_DISPLAY`、`HYPRLAND_INSTANCE_SIGNATURE`），会拒绝使用当前桌面；测试连续锁定后重载、双屏界面、重新开始认证、延后界面类型切换及解锁后重载。普通测试运行跳过这项实机检查。

会话内重启测试只能比较 Quickshell 本身，不包含登录管理器交接、显示器初始化或冷缓存耗时。完整登录时间应在下一次正常登录后从登录管理器、Hyprland 和 Quickshell 日志一起确认。
