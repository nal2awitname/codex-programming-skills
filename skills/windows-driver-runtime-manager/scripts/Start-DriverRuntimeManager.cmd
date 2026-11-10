@echo off
rem Driver and Runtime Manager launcher
rem Double-click to open the GUI. DriverRuntimeManager.ps1 asks for Administrator
rem rights (UAC) by itself and keeps every argument, so no quoting happens here.
rem Extra arguments are passed through, for example:
rem   Start-DriverRuntimeManager.cmd -Mode Scan -CheckUpdates
rem   Start-DriverRuntimeManager.cmd -Mode Install -Preset gaming -DryRun
rem   Start-DriverRuntimeManager.cmd -Mode Diagnose
rem Set DRM_NO_PAUSE=1 to skip the pause after an error (scripts, CI, scheduled tasks).
setlocal
set "DRM_DIR=%~dp0"
set "DRM_PS1=%DRM_DIR%DriverRuntimeManager.ps1"
if not exist "%DRM_PS1%" goto :missing
cd /d "%DRM_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%DRM_PS1%" -LauncherPath "%~f0" -HideConsole %*
set "DRM_EXIT=%ERRORLEVEL%"
if "%DRM_EXIT%"=="0" exit /b 0
echo.
echo Finished with exit code %DRM_EXIT%. Logs: %ProgramData%\DriverRuntimeManager\Logs
if not defined DRM_NO_PAUSE pause
exit /b %DRM_EXIT%

:missing
echo [ERROR] DriverRuntimeManager.ps1 not found next to this file.
if not defined DRM_NO_PAUSE pause
exit /b 2
