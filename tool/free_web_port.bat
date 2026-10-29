@echo off
rem Frees the web debug port (7357 by default; or: free_web_port 8080):
rem stops a Chrome debug run of the app still on it, and its Chrome.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0free_web_port.ps1" %*
