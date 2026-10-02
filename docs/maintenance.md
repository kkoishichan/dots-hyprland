# 维护这套配置

`origin` 指向 `kkoishichan/dots-hyprland`，`upstream` 指向 `end-4/dots-hyprland`，定制保存在 `main` 分支。初始上游版本记录在 `config/upstream-base.json`。

从 GitHub fork 新克隆的工作副本需要先添加上游远端：

```sh
git remote add upstream https://github.com/end-4/dots-hyprland.git
```

## 日常修改

以仓库的 `dots/` 为配置来源，修改后运行检查，再应用到本机：

```sh
node tests/scrolling-workspaces.cjs
python3 -m unittest discover -s tests -p 'test_*.py'
git diff --check
python3 tools/desktop-config.py deploy --dry-run
python3 tools/desktop-config.py deploy
hyprctl reload
```

维护脚本只操作 `config/managed-files.txt` 中的文件和界面偏好。新增定制文件时，将相对主目录的路径加入清单，例如 `.config/quickshell/ii/services/NewService.qml`。其他上游文件通过上游安装器部署。

如果先在 `~/.config` 中调试了已列入清单的文件，把变更收录回仓库：

```sh
python3 tools/desktop-config.py status
python3 tools/desktop-config.py capture --dry-run
python3 tools/desktop-config.py capture
git diff
```

`status` 返回 0 表示同步，1 表示有差异，2 表示配置或路径错误。`capture` 只收录已列出的文件，并按共享 profile 中现有的键提取界面偏好。

确认改动后正常提交和推送：

```sh
git add <本次修改的文件>
git commit -m "Describe the resulting desktop behavior"
git push origin main
```

## 合并上游

先提交本地修改，然后合并上游历史：

```sh
git fetch upstream
git merge upstream/main
node tests/scrolling-workspaces.cjs
python3 -m unittest discover -s tests -p 'test_*.py'
git diff --check
```

有冲突时，保留滚动布局、动态工作区和简洁概览的行为，并结合上游的新接口修正代码。需要同步上游基础文件时，使用本仓库的安装器：

```sh
./setup install --skip-alldeps --skip-allsetups --core
python3 tools/desktop-config.py deploy
hyprctl reload
git push origin main
```

安装器会更新上游基础文件；最后的 `deploy` 会应用定制的 `custom/` 配置、界面文件与偏好。更新上游不会自动在当前桌面应用代码，也不会覆盖 Git 提交历史。

## 本机文件与备份

显示器排列 `~/.config/hypr/monitors.lua`、壁纸生成的颜色、工作区顺序、剪贴板、通知、API 凭据和测试截图留在本机。界面 profile 只合并公开的偏好键，已有配置中的其他设置会保留。

维护脚本在写入前准备完整变更列表，并备份原文件。备份目录权限为 0700，`manifest.json` 记录目标目录、路径和原文件是否存在。需要回退时，根据该清单把备份文件复制回原位置；清单中 `existed: false` 的路径表示本次新增文件。回退后执行 `hyprctl reload`，Quickshell 会自动加载文件变更。

原先设计过程的备份和截图继续保存在本机 `~/work/hypr-scroll-design/`；后续源码维护使用此 fork。
