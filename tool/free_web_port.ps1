# Frees the web debug port (7357 by default): stops a Chrome debug run of the
# app that is still going (flutter run on that port, the Chrome it opened)
# and anything else listening there. Runs before "Huntr (Chrome :7357)"
# starts, and on its own as the "Stop web debug" task - for when VS Code has
# lost the session and shows no Stop button.
param([int]$Port = 7357)

$stopped = 0

# flutter run for the web on this port: the whole tree (dart, Chrome)
Get-CimInstance Win32_Process -Filter "Name = 'cmd.exe'" |
  Where-Object { $_.CommandLine -match 'flutter\.bat"?\s+run\b' -and $_.CommandLine -match "--web-port[ =]$Port\b" } |
  ForEach-Object {
    Write-Host "Stopping flutter run (pid $($_.ProcessId)) and what it started"
    taskkill /PID $_.ProcessId /T /F *> $null
    $stopped++
  }

# anything still listening on the port
Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty OwningProcess -Unique |
  ForEach-Object {
    $name = (Get-Process -Id $_ -ErrorAction SilentlyContinue).ProcessName
    Write-Host "Stopping $name (pid $_) on port $Port"
    taskkill /PID $_ /T /F *> $null
    $stopped++
  }

Start-Sleep -Milliseconds 500
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
  Write-Host "Port $Port is still in use."
  exit 1
}
if ($stopped -eq 0) { Write-Host "Port $Port is free." } else { Write-Host "Port $Port is free now." }
