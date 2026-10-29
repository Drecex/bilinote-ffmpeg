@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
echo ==========================================
echo   BiliNote + FFmpeg
echo ==========================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="0" (echo [OK] Done.) else (echo [FAILED] exit code %RC%, see install.log)
echo.
pause
endlocal
exit /b %RC%
