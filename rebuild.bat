@echo off
rem Rebuilds everything the launcher runs after a git pull: the native game,
rem the web game, Haxen and CrownAndCardLauncher.exe (close the launcher first).
rem   rebuild.bat          build, then wait for a key
rem   rebuild.bat /nopause build and exit (for scripts)
setlocal
cd /d "%~dp0"

echo [1/4] Game, native window (native\game.hl)
call haxe build-hl.hxml || goto :failed
if not exist native\hl.exe echo   HashLink isn't in native\ yet; run: powershell -File tools\fetch_hashlink.ps1

echo [2/4] Game, web build (web\game.js)
call haxe build-js.hxml || goto :failed

echo [3/4] Haxen (web\haxen.js)
call haxe haxen.hxml || goto :failed

echo [4/4] Launcher (CrownAndCardLauncher.exe)
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
