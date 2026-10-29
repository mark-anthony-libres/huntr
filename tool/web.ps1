# Runs the app on the web (Chrome, http://localhost:7357) in this window,
# reloadable from anywhere: keys here work as in `flutter run` (r reload,
# R restart, q quit), and `tool\reload_web` from any other window (or a
# script) reloads it too. A run left over on the port is stopped first.
param([int]$Port = 7357, [string]$Env = "env/dev.json")

$root = Split-Path -Parent $PSScriptRoot
$commands = Join-Path $root ".dart_tool\web_run_command"
& (Join-Path $PSScriptRoot "free_web_port.ps1") -Port $Port | Out-Host
Remove-Item $commands -ErrorAction SilentlyContinue

$start = New-Object System.Diagnostics.ProcessStartInfo
$start.FileName = "cmd.exe"
$start.Arguments = "/c flutter run -d chrome --web-hostname localhost --web-port $Port --dart-define-from-file=$Env"
$start.WorkingDirectory = $root
$start.UseShellExecute = $false
$start.RedirectStandardInput = $true
$flutter = [System.Diagnostics.Process]::Start($start)
$flutter.StandardInput.AutoFlush = $true
Write-Host "r reload, R restart, q quit - or run tool\reload_web from another window"

try {
  while (-not $flutter.HasExited) {
    # a key pressed here (none when this isn't run in a console window)
    try {
      while ([Console]::KeyAvailable) {
        $flutter.StandardInput.Write([Console]::ReadKey($true).KeyChar)
      }
    } catch [System.InvalidOperationException] {}
    # a command from tool\reload_web
    if (Test-Path $commands) {
      $command = (Get-Content $commands -Raw).Trim()
      Remove-Item $commands -ErrorAction SilentlyContinue
      if ($command) { $flutter.StandardInput.Write($command) }
    }
    Start-Sleep -Milliseconds 200
  }
} finally {
  if (-not $flutter.HasExited) { taskkill /PID $flutter.Id /T /F *> $null }
  Remove-Item $commands -ErrorAction SilentlyContinue
}
