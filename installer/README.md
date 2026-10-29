# 一键安装：把 ffmpeg 接进 BiliNote

双击 `Install.cmd`（或右键「使用 PowerShell 运行」`Install.ps1`）。

## 做什么

```
[1] 定位 BiliNote 安装目录（注册表 / %LOCALAPPDATA%\BiliNote）
[2] 准备 ffmpeg：本地 ffmpeg\bin 优先，否则自动下载官方 essentials build
[3] 自检 ffmpeg.exe / ffprobe.exe，复制到 <安装目录>\ffmpeg\bin
[4] 备份并写入 _internal\.env：
      FFMPEG_BIN_PATH=<安装目录>/ffmpeg/bin
      HF_ENDPOINT=https://hf-mirror.com   （已存在则保留原值）
    UTF-8 无 BOM，写入后回读校验
[5] 关闭并重启 BiliNote
[6] 轮询 /api/sys_health，直到 ffmpeg = ok
```

## 参数

| 参数 | 说明 |
| --- | --- |
| `-InstallDir <path>` | 指定 BiliNote 安装目录（默认自动探测） |
| `-FFmpegUrl <url[]> ` | 自定义下载地址，可传多个按顺序重试。默认先试本仓库的 Release 附件，失败再回退 gyan.dev |
| `-NoRestart` | 不重启 BiliNote |
| `-SkipHealthCheck` | 跳过 `/api/sys_health` 轮询 |

## 退出码

| 码 | 含义 |
| --- | --- |
| 0 | 成功，ffmpeg=ok |
| 1 | 失败（看 `install.log`） |
| 2 | 配置已写入，但 90 秒内后端未报告 ffmpeg=ok，手动重启 BiliNote 即可 |

## ffmpeg 从哪来

按优先级取第一个可用的，全部命中才联网下载：

1. `installer\ffmpeg\bin`（离线包，放进去就不会联网）
2. BiliNote 安装目录里的 `ffmpeg\bin`（重复运行脚本时直接复用）
3. 系统 `PATH` 里的 `ffmpeg.exe`
4. 下载：先试本仓库 [Release 附件](https://github.com/Drecex/bilinote-ffmpeg/releases)（74 MB），
   失败再回退 gyan.dev 官方包（约 115 MB），解压后取 `bin`

> 下载慢或断网时，手动把 ffmpeg 解压到 `installer\ffmpeg\bin`（含 `ffmpeg.exe`、`ffprobe.exe`）再运行即可。

## 离线使用

把解压后的 ffmpeg 目录放成：

```
installer\
  Install.cmd
  Install.ps1
  ffmpeg\bin\ffmpeg.exe
  ffmpeg\bin\ffprobe.exe
```

脚本检测到 `ffmpeg\bin\ffmpeg.exe` 就不再联网下载。

## 排错

- `找不到配置文件: ...\_internal\.env` → BiliNote 没装或装在非默认位置，用 `-InstallDir` 指定。
- `配置文件不是有效的 UTF-8` → 原 `.env` 被别的编辑器存成了 GBK，脚本会拒绝写入以免损坏；先用 UTF-8 重存。
- 健康检查一直是超时 → 手动打开 BiliNote，看 `%LOCALAPPDATA%\BiliNote\logs\app.log` 里 `ffmpeg_helper` 的输出。
