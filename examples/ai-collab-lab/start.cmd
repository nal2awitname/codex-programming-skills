@echo off
rem Double-click to start AI Collab Lab in your browser.
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  py -3 collab_lab.py %*
) else (
  python collab_lab.py %*
)
if errorlevel 1 pause
