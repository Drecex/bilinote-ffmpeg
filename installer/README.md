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
| `-FFmpegUrl <url>` | 自定义 ffmpeg 压缩包地址（默认 gyan.dev essentials） |
| `-NoRestart` | 不重启 BiliNote |
| `-SkipHealthCheck` | 跳过 `/api/sys_health` 轮询 |

## 退出码

| 码 | 含义 |
| --- | --- |
| 0 | 成功，ffmpeg=ok |
| 1 | 失败（看 `install.log`） |
| 2 | 配置已写入，但 90 秒内后端未报告 ffmpeg=ok，手动重启 BiliNote 即可 |

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
