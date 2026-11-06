@echo off
py -3 "%~dp0range_totals.py" %*
exit /b %errorlevel%
