@echo off
setlocal

rem ?? AutoHotkey v2?PATH -> ??? -> ???????
rem ??????????????????????????"???????"??
rem ????????????????? AutoHotkey???????? ExportFlowPrompts.ahk?

set "AHK="
for %%P in (AutoHotkey.exe) do if not defined AHK set "AHK=%%~$PATH:P"

if not defined AHK (
    for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\AutoHotkey" /v InstallDir 2^>nul') do (
        if exist "%%B\v2\AutoHotkey.exe" set "AHK=%%B\v2\AutoHotkey.exe"
    )
)
if not defined AHK (
    for /f "tokens=2,*" %%A in ('reg query "HKCU\SOFTWARE\AutoHotkey" /v InstallDir 2^>nul') do (
        if exist "%%B\v2\AutoHotkey.exe" set "AHK=%%B\v2\AutoHotkey.exe"
    )
)
if not defined AHK if exist "%ProgramFiles%\AutoHotkey\v2\AutoHotkey.exe" set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey.exe"
if not defined AHK if exist "%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey.exe" set "AHK=%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey.exe"

if not defined AHK (
    echo [export] AutoHotkey v2 not found. Install it first, or run ExportFlowPrompts.ahk with your own AutoHotkey.exe.
    exit /b 3
)

"%AHK%" "%~dp0ExportFlowPrompts.ahk" %*
exit /b %ERRORLEVEL%
