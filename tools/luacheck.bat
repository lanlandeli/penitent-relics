@echo off
REM ============================================================================
REM Penitent Relics Lua syntax check (Windows double-click version)
REM Runs luac -p on every .lua file under mod/
REM Requires tools/lua/luac53.exe (portable Lua 5.3; see docs/development/agent_workflow.md)
REM ============================================================================
setlocal enabledelayedexpansion
set "LUAC=%~dp0lua\luac53.exe"
set "MODROOT=%~dp0..\mod"

if not exist "%LUAC%" (
    echo [ERROR] %LUAC% not found.
    echo         Install the portable Lua 5.3 build into tools\lua\ ^(see docs/development/agent_workflow.md^).
    exit /b 1
)

echo ========== Penitent Relics Lua syntax check ==========
set /a FAIL=0
set /a TOTAL=0
for /r "%MODROOT%" %%f in (*.lua) do (
    set /a TOTAL+=1
    "%LUAC%" -p "%%f" >nul 2>&1
    if errorlevel 1 (
        echo [FAIL] %%f
        "%LUAC%" -p "%%f"
        set /a FAIL+=1
    ) else (
        echo [ OK ] %%f
    )
)
echo ==================================================
echo !TOTAL! file(s) checked, !FAIL! failed
if !FAIL! gtr 0 (
    echo [RESULT] Syntax errors found. Fix them and re-run.
    exit /b 1
)
echo [RESULT] All checks passed.
