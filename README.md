# BiliNote + FFmpeg 集成

给 [BiliNote](https://github.com/JefferyHcool/BiliNote)（本地视频/播客转笔记工具）补上 **ffmpeg 集成**，解决官方 Windows 安装包不带 ffmpeg、必须手工改 `_internal/.env` 才能生成笔记的问题。

本仓库提供两条路线，任选其一：

| 路线 | 适用场景 | 是否要重新打包 |
| --- | --- | --- |
| [一键安装脚本](installer/) | 已经装了官方 BiliNote，只想让它能跑 | 不需要 |
| [源码补丁](patch/) | 想从源码构建「装完自带 ffmpeg」的版本 | 需要 |

---

## 问题现象

官方 BiliNote 2.4.5 的 Windows 安装包**不含 ffmpeg**，而后端启动时会检查 `FFMPEG_BIN_PATH`：

```text
ffmpeg_helper - 未配置 FFMPEG_BIN_PATH，尝试从系统 PATH 查找 ffmpeg
ffmpeg_helper - 未找到 ffmpeg，请先安装 ffmpeg 并配置环境变量
```

之后点「生成笔记」就会失败：

```text
[WinError 2] 系统找不到指定的文件
```

原因是：安装目录里的 `material/ffmpeg` 或 `_internal/.env` 并没有被正确写入 ——
`.env` 里的 `FFMPEG_BIN_PATH` 是空的，程序判定「ffmpeg 未安装」。

---

## 路线一：一键安装脚本（推荐）

`installer/` 目录，双击 `Install.cmd` 即可。它会：

1. 定位 BiliNote 安装目录（注册表 → `%LOCALAPPDATA%\BiliNote`），没装则调用同目录的官方安装包；
2. 找 ffmpeg，按顺序：脚本同目录 `ffmpeg/bin` → BiliNote 安装目录里已有的 `ffmpeg/bin` → 系统 PATH →
   都没有才自动下载（优先本仓库 [Release 附件](https://github.com/Drecex/bilinote-ffmpeg/releases)，回退 gyan.dev）；
3. 对 `ffmpeg.exe` / `ffprobe.exe` 做 `-version` 自检，复制到 `<安装目录>\ffmpeg\bin`；
4. 备份 `_internal\.env`，写入 `FFMPEG_BIN_PATH`（UTF-8 无 BOM），并**回读校验**；
5. 顺带补 `HF_ENDPOINT=https://hf-mirror.com`（国内拉本地 whisper 模型必需，已存在则不改）；
6. 重启 BiliNote，轮询 `http://127.0.0.1:8483/api/sys_health` 直到 `"ffmpeg":"ok"` 才报成功。

```bat
:: 直接装
Install.cmd

:: 指定安装目录 / 自定义 ffmpeg 下载地址
Install.cmd -InstallDir "D:\Apps\BiliNote"
Install.cmd -FFmpegUrl "https://example.com/ffmpeg.zip"

:: 调试用：不重启、不健康检查
Install.cmd -NoRestart -SkipHealthCheck
```

退出码：`0` 成功 / `1` 失败 / `2` 配置已写入但健康检查超时（手动重启 BiliNote 即可）。

> **关于 ffmpeg 二进制**：单个 `ffmpeg.exe` 约 100.5 MB，超过 GitHub 单文件 100 MB 限制，
> 所以仓库里不放二进制，由脚本首次运行时自动下载。若离线使用，把解压后的 `bin` 目录
> 放到 `installer/ffmpeg/bin` 即可，脚本会优先使用本地版本。

---

## 路线二：源码补丁

`patch/ffmpeg_helper.py` 是打过补丁的完整文件，`patch/ffmpeg-helper-autodetect.patch` 是对应的 unified diff。

```bash
git clone https://github.com/JefferyHcool/BiliNote.git
cd BiliNote
git apply /path/to/ffmpeg-helper-autodetect.patch
```

补丁内容：给 `backend/ffmpeg_helper.py` 增加 `_bundled_ffmpeg_dirs()`，在检查 `FFMPEG_BIN_PATH`
之后、扫描系统 PATH 之前，先探测随包分发的 ffmpeg 目录：

| 顺序 | 目录 | 场景 |
| --- | --- | --- |
| 1 | `backend/../ffmpeg/bin` | 源码直接运行 |
| 2 | `<EXE 目录>/ffmpeg/bin` | PyInstaller onedir（推荐分发位置） |
| 3 | `<EXE 目录>/_internal/ffmpeg/bin` | PyInstaller onedir + 资源目录 |
| 4 | `<_MEIPASS>/ffmpeg/bin` | PyInstaller onefile |

命中后自动写入 `os.environ["FFMPEG_BIN_PATH"]` 并前置到 `PATH`，最后才回退到系统 PATH 扫描 ——
这样打包产物**装完即用，不需要动 `.env`**。

### 打包时把 ffmpeg 一起放进去

```bat
:: backend/build.bat（PyInstaller）追加：
pyinstaller ... --add-data "ffmpeg\bin;ffmpeg\bin" backend\main.py
```

```bash
# 或构建后手动放入产物目录
cp -r ffmpeg/bin dist/BiliNoteBackend/ffmpeg/bin
```

Tauri 侧把 `ffmpeg/bin` 放进安装包资源目录（`src-tauri/resources`），随 `BiliNoteBackend.exe` 一起分发即可。

---

## 验证

```powershell
Invoke-RestMethod http://127.0.0.1:8483/api/sys_health
# data.ffmpeg 应为 "ok"
```

日志 `%LOCALAPPDATA%\BiliNote\logs\app.log` 中应出现：

```text
ffmpeg_helper - 使用FFMPEG_BIN_PATH: .../BiliNote/ffmpeg/bin
ffmpeg_helper - ffmpeg 已安装
```

---

## 已知的相关坑（顺带记录）

- **快手 ASR 已关停**：`https://ai.kuaishou.com/api/effects/subtitle_generate` 返回
  `{"code":501,"msg":"效果subtitle_generate禁用"}`，转写器要换成 `bcut` 或本地 `fast-whisper`。
- **bcut 有风控**：先能成功，随后稳定返回
  `412 Client Error: Precondition Failed`（需要登录态 Cookie），不建议当默认方案。
- **本地 whisper 模型下载失败**：默认走 `huggingface.co`，国内常不可达；加
  `HF_ENDPOINT=https://hf-mirror.com` 即可。
- **`.md` 导出不含截图**：`note_results/<task>_markdown.md` 是后处理之前的缓存，
  `*Screenshot-[mm:ss]*` 占位符没有替换；带图的成品在 `note_results/<task>.json` 的 `markdown` 字段里。

---

## 安全说明

- 仓库内**不含任何 API Key / Token / 账号信息**，也没有使用记录、笔记内容、日志或数据库。
- 安装脚本只读写本机 BiliNote 安装目录与 `%TEMP%`，不上传任何数据。
- 若你 fork 后自行填入密钥，请务必放在 `.env` 或环境变量里，`git status` 确认后再提交。

## License

补丁基于 [JefferyHcool/BiliNote](https://github.com/JefferyHcool/BiliNote)（MIT License，Copyright (c) 2024 Jeffery Huang），
本仓库同样以 MIT 协议发布。ffmpeg 由 [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) 提供，
遵循其各自的许可（essentials build 为 GPL）。
