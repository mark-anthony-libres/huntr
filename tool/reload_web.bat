@echo off
rem Reloads the web app started with tool\web (hot reload; "reload_web restart"
rem for a hot restart, which starts the app over).
set "action=r"
if /i "%~1"=="restart" set "action=R"
if not exist "%~dp0..\.dart_tool" (echo Run tool\web first. & exit /b 1)
<nul set /p "=%action%" > "%~dp0..\.dart_tool\web_run_command"
if "%action%"=="R" (echo Restarting the web app...) else (echo Reloading the web app...)
