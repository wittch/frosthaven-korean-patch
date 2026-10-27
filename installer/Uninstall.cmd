@rem SPDX-License-Identifier: MIT
@rem Copyright (c) 2026 wittch
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" %*
if errorlevel 1 (echo Operation failed. Read the message above. & pause & exit /b 1)
pause
