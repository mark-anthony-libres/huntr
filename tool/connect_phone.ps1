# Connects an Android phone over wireless debugging and lets the app on it
# reach the local backend (adb reverse tcp:18000). Safe to run again: if the
# phone is already connected it only renews the reverse forward.
#
#   powershell -ExecutionPolicy Bypass -File tool/connect_phone.ps1 [-Address 192.168.1.20:41234]
#
# The phone must be paired once (Settings > Developer options > Wireless
# debugging > Pair device with pairing code, then `adb pair ip:port`).
param(
    # "ip:port" from the phone's Wireless debugging screen (asked if missing)
    [string]$Address = "",
    # the backend port the app uses (env/phone.json: http://localhost:18000)
    [int]$BackendPort = 18000
)

$ErrorActionPreference = "Stop"
$remembered = Join-Path $PSScriptRoot ".phone_address"

function Find-Adb {
    $onPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    foreach ($sdk in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk")) {
        if ($sdk) {
            $candidate = Join-Path $sdk "platform-tools\adb.exe"
            if (Test-Path $candidate) { return $candidate }
        }
    }
    throw "adb not found. Install Android SDK platform-tools (Android Studio > SDK Manager)."
}

# wireless devices adb has connected ("ip:port   device")
function Get-WirelessDevices([string]$adb) {
    & $adb devices | Select-String -Pattern '^(\d+\.\d+\.\d+\.\d+:\d+)\s+device$' |
        ForEach-Object { $_.Matches[0].Groups[1].Value }
}

function Connect-Reverse([string]$adb, [string]$device) {
    & $adb -s $device reverse "tcp:$BackendPort" "tcp:$BackendPort" | Out-Null
    $list = & $adb -s $device reverse --list
    if (-not ($list -match "tcp:$BackendPort")) {
        throw "Connected, but 'adb reverse' didn't take. Run this again."
    }
}

$adb = Find-Adb
& $adb start-server 2>$null | Out-Null

# 1. already connected: only make sure the app can reach the backend
$connected = @(Get-WirelessDevices $adb)
if ($connected.Count -gt 0 -and -not $Address) {
    $device = $connected[0]
    Connect-Reverse $adb $device
    Write-Host "Already connected to $device. Backend forwarded (phone localhost:$BackendPort -> PC)." -ForegroundColor Green
    exit 0
}

# 2. find it: the phone advertises itself while Wireless debugging is on
if (-not $Address) {
    $found = & $adb mdns services 2>$null | Select-String -Pattern '_adb-tls-connect\._tcp\.?\s+(\d+\.\d+\.\d+\.\d+:\d+)' |
        ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
    if ($found) {
        $Address = $found
        Write-Host "Found the phone at $Address."
    }
}

# 3. ask: the port changes every time Wireless debugging is turned on
if (-not $Address) {
    $lastIp = if (Test-Path $remembered) { ((Get-Content $remembered -Raw).Trim() -split ':')[0] } else { "" }
    Write-Host "On the phone: Settings > Developer options > Wireless debugging > 'IP address & Port'."
    $prompt = if ($lastIp) { "Port (or ip:port) [IP $lastIp]" } else { "ip:port" }
    $answer = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($answer)) {
        throw "No address entered. Run it again with the port from the phone, or pass -Address ip:port."
    }
    $answer = $answer.Trim()
    $Address = if ($answer -match '^\d+$') {
        if (-not $lastIp) { throw "Enter the full ip:port the first time." }
        "${lastIp}:$answer"
    } else { $answer }
}

if ($Address -notmatch '^\d+\.\d+\.\d+\.\d+:\d+$') {
    throw "'$Address' isn't ip:port (e.g. 192.168.254.150:34333)."
}

$result = (& $adb connect $Address 2>&1 | Out-String).Trim()
if ($result -notmatch 'connected to') {
    Write-Host $result -ForegroundColor Red
    Write-Host "Check: Wireless debugging is on, the port is the current one, the phone is paired with this PC, and both are on the same Wi-Fi." -ForegroundColor Yellow
    exit 1
}
Set-Content -Path $remembered -Value $Address -Encoding ascii
Connect-Reverse $adb $Address
Write-Host "Connected to $Address. Backend forwarded (phone localhost:$BackendPort -> PC)." -ForegroundColor Green
