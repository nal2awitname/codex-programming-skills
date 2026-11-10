@echo off
rem Driver and Runtime Manager launcher
rem Double-click to open the GUI. Requests Administrator rights (UAC) when needed.
rem Extra arguments are passed to DriverRuntimeManager.ps1, for example:
rem   Start-DriverRuntimeManager.cmd -Mode Scan -CheckUpdates
rem   Start-DriverRuntimeManager.cmd -Mode Install -Preset gaming -DryRun
setlocal
set "DRM_DIR=%~dp0"
set "DRM_PS1=%DRM_DIR%DriverRuntimeManager.ps1"
if not exist "%DRM_PS1%" (
  echo [ERROR] DriverRuntimeManager.ps1 not found next to this file.
  pause
  exit /b 2
)
fltmc >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator rights...
  if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  ) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
  )
  exit /b 0
)
cd /d "%DRM_DIR%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%DRM_PS1%" -LauncherPath "%~f0" %*
set "DRM_EXIT=%ERRORLEVEL%"
if not "%DRM_EXIT%"=="0" (
  echo.
  echo Finished with exit code %DRM_EXIT%. Logs: %ProgramData%\DriverRuntimeManager\Logs
  pause
)
exit /b %DRM_EXIT%
