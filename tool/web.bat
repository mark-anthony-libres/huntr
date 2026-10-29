@echo off
rem Runs the app on the web (Chrome, localhost:7357) here: r reload, R restart,
rem q quit; tooleload_web from another window reloads it too.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0web.ps1" %*
