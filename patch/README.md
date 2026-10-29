# 源码补丁：让 BiliNote 自动发现随包 ffmpeg

| 文件 | 说明 |
| --- | --- |
| `ffmpeg_helper.py` | 打过补丁的完整文件，可直接覆盖 `backend/ffmpeg_helper.py` |
| `ffmpeg-helper-autodetect.patch` | 对应 unified diff，`git apply` 用 |
| `note-md-export.patch` | 修 `note_results/<task>_markdown.md` 只留截图占位符的问题 |

## 应用

```bash
git clone https://github.com/JefferyHcool/BiliNote.git
cd BiliNote
git apply /path/to/ffmpeg-helper-autodetect.patch
git apply /path/to/note-md-export.patch
# 或直接覆盖：
# cp /path/to/ffmpeg_helper.py backend/ffmpeg_helper.py
python -m py_compile backend/ffmpeg_helper.py backend/app/services/note.py
```

## 改动内容

新增 `_bundled_ffmpeg_dirs()`，在 `check_ffmpeg_exists()` 中插入一段探测逻辑：

```python
def _bundled_ffmpeg_dirs():
    dirs = []
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dirs.append(os.path.normpath(os.path.join(script_dir, '..', 'ffmpeg', 'bin')))
    if getattr(sys, 'frozen', False):
        exe_dir = os.path.dirname(sys.executable)
        dirs.append(os.path.join(exe_dir, 'ffmpeg', 'bin'))
        dirs.append(os.path.join(exe_dir, '_internal', 'ffmpeg', 'bin'))
    meipass = getattr(sys, '_MEIPASS', None)
    if meipass:
        dirs.append(os.path.join(meipass, 'ffmpeg', 'bin'))
    return dirs
```

优先级：`FFMPEG_BIN_PATH` → 随包目录 → 系统 PATH。

命中随包目录时：

```python
os.environ["FFMPEG_BIN_PATH"] = bundled
os.environ["PATH"] = bundled + os.pathsep + os.environ.get("PATH", "")
logger.info(f"使用随包分发的 ffmpeg: {bundled}")
```

## 补丁二：markdown 导出缺截图

`note-md-export.patch` 修改 `backend/app/services/note.py`。

问题：`.md` 缓存在**截图替换之前**就写盘了。

```python
markdown_cache_file.write_text(markdown)          # 616 行：先写盘
...
markdown = self._post_process_markdown(...)        # 218 行：之后才替换截图
```

结果 `note_results/<task>_markdown.md` 里留着 `*Screenshot-[00:34]*` 占位符，
带图的成品只存在于 `<task>.json` 的 `markdown` 字段（界面读的是 JSON，所以肉眼看不出来）。

修法：在后处理、`prepend_source_link()` 之后，把最终 markdown 回写一次缓存。

```python
markdown = prepend_source_link(markdown, str(video_url))

try:
    markdown_cache_file.write_text(markdown, encoding="utf-8")
except OSError as exc:
    logger.warning(f"回写 markdown 缓存失败（不影响笔记生成）: {exc}")
```

## 打包

```bat
:: PyInstaller（backend/build.bat）
pyinstaller ... --add-data "ffmpeg\bin;ffmpeg\bin" backend\main.py
```

产物目录约定（二者任选，都能被探测到）：

```
BiliNoteBackend\BiliNoteBackend.exe
BiliNoteBackend\ffmpeg\bin\ffmpeg.exe          ← 方式 A
BiliNoteBackend\_internal\ffmpeg\bin\ffmpeg.exe ← 方式 B
```

Tauri 安装包把同样的 `ffmpeg/bin` 放进 `src-tauri/resources`，一起打包分发即可。

## 注意

补丁要生效必须**重新打包后端 exe**（PyInstaller）以及安装包（Tauri 需要 Rust + MSVC 工具链），
已有的官方安装包不会因为换了这个 `.py` 文件而改变行为 —— 那种情况请用仓库里的
[一键安装脚本](../installer/)。
