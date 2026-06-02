@echo off
chcp 65001 >nul
title ScrollFunk Auto Finder

cd /d "%~dp0"

echo ==============================
echo      ScrollFunk Auto Finder
echo ==============================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0AutoFindFunks.ps1"

echo.
echo Hotovo.
pause
