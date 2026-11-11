@echo off
rem Drag a source file onto this file, or double-click it from a shortcut: the window
rem stays open until Enter is pressed so the output can be read.
setlocal
set "CODE_RUNNER_PS=powershell.exe"
where pwsh.exe >nul 2>nul && set "CODE_RUNNER_PS=pwsh.exe"
"%CODE_RUNNER_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-Code.ps1" -Pause %*
exit /b %ERRORLEVEL%
