import os
import subprocess
import sys
from dotenv import load_dotenv

from app.utils.logger import get_logger
logger = get_logger(__name__)


def _load_dotenv_from_multiple_paths():
    """尝试多个位置加载 .env，适配源码运行和 PyInstaller 打包场景。

    PyInstaller 打包后当前工作目录是 EXE 所在目录，而源码运行时 .env
    通常在项目根目录或 backend/ 同级。遍历常见候选路径确保能命中。
    """
    candidates = []
    # 1. 当前工作目录（EXE 所在目录）
    candidates.append(os.path.join(os.getcwd(), '.env'))
    # 2. 本脚本所在目录（backend/）
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates.append(os.path.join(script_dir, '.env'))
    # 3. 项目根目录（backend/../.env）
    candidates.append(os.path.join(script_dir, '..', '.env'))
    # 4. PyInstaller 打包后的 _internal/ 子目录
    if getattr(sys, 'frozen', False):
        exe_dir = os.path.dirname(sys.executable)
        candidates.append(os.path.join(exe_dir, '_internal', '.env'))

    for path in candidates:
        normalized = os.path.normpath(path)
        if os.path.isfile(normalized):
            load_dotenv(normalized)
            return
    # 都没找到，fallback 到默认行为（从 CWD 找）
    load_dotenv()


_load_dotenv_from_multiple_paths()


def _bundled_ffmpeg_dirs():
    """返回随包分发的 ffmpeg 候选目录（按优先级）。

    官方安装包本身不含 ffmpeg，这里支持把 ffmpeg/bin 一起打进安装目录，
    这样即使用户 .env 里没写 FFMPEG_BIN_PATH 也能开箱可用：
      1. 源码运行：backend/../ffmpeg/bin
      2. PyInstaller onedir：<EXE 目录>/ffmpeg/bin（推荐的分发位置）
      3. PyInstaller onedir：<EXE 目录>/_internal/ffmpeg/bin
      4. PyInstaller onefile：<_MEIPASS>/ffmpeg/bin
    """
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


def check_ffmpeg_exists() -> bool:
    """
    检查 ffmpeg 是否可用。优先使用 FFMPEG_BIN_PATH 环境变量指定的路径，
    其次使用随包分发的 ffmpeg 目录，最后才扫描系统 PATH。
    """
    ffmpeg_bin_path = os.getenv("FFMPEG_BIN_PATH")
    logger.info(f"FFMPEG_BIN_PATH: {ffmpeg_bin_path}")
    if ffmpeg_bin_path and os.path.isdir(ffmpeg_bin_path):
        os.environ["PATH"] = ffmpeg_bin_path + os.pathsep + os.environ.get("PATH", "")
        logger.info(f"使用FFMPEG_BIN_PATH: {ffmpeg_bin_path}")
    else:
        bundled = next((d for d in _bundled_ffmpeg_dirs() if os.path.isfile(os.path.join(d, "ffmpeg.exe"))), None)
        if bundled:
            os.environ["FFMPEG_BIN_PATH"] = bundled
            os.environ["PATH"] = bundled + os.pathsep + os.environ.get("PATH", "")
            logger.info(f"使用随包分发的 ffmpeg: {bundled}")
        else:
            # 遍历系统PATH寻找ffmpeg.exe
            system_path = os.environ.get("PATH", "")
            path_dirs = system_path.split(os.pathsep)
            for path_dir in path_dirs:
                ffmpeg_exe_path = os.path.join(path_dir, "ffmpeg.exe")
                if os.path.isfile(ffmpeg_exe_path):
                    os.environ["PATH"] = path_dir + os.pathsep + system_path
                    logger.info(f"在系统PATH中找到ffmpeg: {path_dir}")
                    break
    try:
        subprocess.run(["ffmpeg", "-version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        logger.info("ffmpeg 已安装")
        return True
    except (FileNotFoundError, OSError, subprocess.CalledProcessError):
        logger.info("ffmpeg 未安装")
        return False


def ensure_ffmpeg_or_raise():
    """
    校验 ffmpeg 是否可用，否则抛出异常并提示安装方式。
    """
    if not check_ffmpeg_exists():
        logger.error("未检测到 ffmpeg，请先安装后再使用本功能。")
        raise EnvironmentError(
            " 未检测到 ffmpeg，请先安装后再使用本功能。\n"
            "👉 下载地址：https://ffmpeg.org/download.html\n"
            "🪟 Windows 推荐：https://www.gyan.dev/ffmpeg/builds/\n"
            "💡 如果你已安装，请将其路径写入 `.env` 文件，例如：\n"
            "FFMPEG_BIN_PATH=/your/custom/ffmpeg/bin"
        )
