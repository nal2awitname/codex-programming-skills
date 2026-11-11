@echo off
rem Run a source file with Invoke-Code.ps1 even where script execution is disabled.
rem Usage: run-code.cmd [runner options] <file-or-folder> [program arguments...]
setlocal
set "CODE_RUNNER_PS=powershell.exe"
where pwsh.exe >nul 2>nul && set "CODE_RUNNER_PS=pwsh.exe"
"%CODE_RUNNER_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-Code.ps1" %*
exit /b %ERRORLEVEL%
