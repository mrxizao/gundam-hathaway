# 获取完整工程

此仓库使用 Git LFS 保存模型、贴图、音频和视频。请先安装 Git 与 Git LFS，然后执行：

```sh
git lfs install
git clone https://github.com/mrxizao/gundam-hathaway.git
cd gundam-hathaway
git lfs pull
```

使用 Godot 4.7.1 打开根目录的 `project.godot`，首次打开需要等待资源导入。
不要直接使用 GitHub 的 Download ZIP 作为完整资源包，它可能仅包含 LFS 指针。

仓库包含游戏源码、场景、资源和建模源文件；不包含 `.godot` 缓存、导出成品、历史副本和临时备份。
