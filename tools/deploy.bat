@echo off
REM ============================================================================
REM Penitent Relics deployment: mirror mod/ into the game's mods/PenitentRelics folder.
REM Usage: run tools\deploy.bat from a command prompt.
REM Warning: /MIR removes target files that are no longer present in mod/.
REM ============================================================================
setlocal

REM Change this path if the game is installed elsewhere.
set "GAME_MODS=E:\SteamLibrary\steamapps\common\The Binding of Isaac Rebirth\mods"
set "TARGET=%GAME_MODS%\PenitentRelics"
set "SOURCE=%~dp0..\mod"

if not exist "%GAME_MODS%" (
    echo [ERROR] Game mods directory not found: %GAME_MODS%
    echo         Update GAME_MODS near the top of this script and try again.
    exit /b 1
)

if not exist "%SOURCE%" (
    echo [ERROR] Project mod directory not found: %SOURCE%
    exit /b 1
)

echo Deploying Penitent Relics ...
echo   Source: %SOURCE%
echo   Target: %TARGET%
echo.

robocopy "%SOURCE%" "%TARGET%" /MIR /NFL /NDL /NJH /NJS
if %errorlevel% leq 7 (
    echo.
    echo [OK] Deployment complete. Restart the game and enable Penitent Relics.
) else (
    echo.
    echo [ERROR] Robocopy failed with exit code %errorlevel%
    exit /b %errorlevel%
)
