@echo off
rem Rebuilds everything the launcher runs after a git pull: the web game,
rem Haxen and CrownAndCardLauncher.exe (close the launcher first).
rem   rebuild.bat          build, then wait for a key
rem   rebuild.bat /nopause build and exit (for scripts)
setlocal
cd /d "%~dp0"

echo [1/3] Game (web\game.js)
call haxe build-js.hxml || goto :failed

echo [2/3] Haxen (web\haxen.js)
call haxe haxen.hxml || goto :failed

echo [3/3] Launcher (CrownAndCardLauncher.exe)
powershell -NoProfile -ExecutionPolicy Bypass -File launcher\build.ps1 || goto :failed

echo.
echo Rebuilt. Start CrownAndCardLauncher.exe in this folder to play.
set code=0
goto :done

:failed
echo.
echo Rebuild failed; see the errors above. If the launcher build can't write
echo its files, close CrownAndCardLauncher.exe and run this again.
set code=1

:done
if /i not "%~1"=="/nopause" pause
exit /b %code%
