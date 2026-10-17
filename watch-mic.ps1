# Polls the Yeti Nano's USB identity once a second and logs every change with a timestamp.
# Usage: .\watch-mic.ps1 [-Seconds 300]
param([int]$Seconds = 300)
$log = Join-Path $PSScriptRoot 'watch-mic.log'
$prev = ''
$end = (Get-Date).AddSeconds($Seconds)
"=== watch start $(Get-Date -Format 'HH:mm:ss.fff') ===" | Tee-Object $log -Append
while ((Get-Date) -lt $end) {
    $ids = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match '^USB\\VID_(B58E&PID_000[56]|046D&PID_0AB1)\\' } |
        ForEach-Object { "$($_.InstanceId.Substring(4,17)) [$($_.Status)]" }
    $cur = ($ids | Sort-Object) -join ', '
    if ($cur -eq '') { $cur = '(none)' }
    if ($cur -ne $prev) {
        "$(Get-Date -Format 'HH:mm:ss.fff')  $cur" | Tee-Object $log -Append
        $prev = $cur
    }
    Start-Sleep -Milliseconds 1000
}
"=== watch end $(Get-Date -Format 'HH:mm:ss.fff') ===" | Tee-Object $log -Append
