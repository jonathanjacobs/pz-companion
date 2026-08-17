@echo off
REM SPDX-License-Identifier: Apache-2.0
REM Start the deterministic Spike 002 sidecar on Windows.
REM PZ_USER_DIR may be set before launch to override %%USERPROFILE%%\Zomboid.

setlocal
set "SCRIPT_DIR=%~dp0"
if not defined PZ_USER_DIR set "PZ_USER_DIR=%USERPROFILE%\Zomboid"

where py >nul 2>&1
if %errorlevel%==0 (
    py -3 "%SCRIPT_DIR%whg_companion_sidecar.py" --pz-user-dir "%PZ_USER_DIR%" %*
    exit /b %errorlevel%
)

python "%SCRIPT_DIR%whg_companion_sidecar.py" --pz-user-dir "%PZ_USER_DIR%" %*
exit /b %errorlevel%
