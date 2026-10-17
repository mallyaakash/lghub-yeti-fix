# Phase 1 test: the moment the mic enumerates as Logitech 046D:0AB1 (firmware 4.10 running,
# flash already complete), kill every G HUB process so nothing talks to the new firmware.
# Logs every identity change at ~50 ms resolution to kill-ghub.log.
# Uses cfgmgr32 directly because Get-PnpDevice / WMI take ~1 s per query.
param([int]$Seconds = 900, [string]$Trigger = '046D&PID_0AB1')  # regex on the current identity list that fires the kill
$log = Join-Path $PSScriptRoot 'kill-ghub.log'
function Say($m) { "$(Get-Date -Format 'HH:mm:ss.fff')  $m" | Tee-Object $log -Append }

Add-Type -Namespace Win32 -Name CfgMgr -MemberDefinition @'
[DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
public static extern int CM_Get_Device_ID_List_SizeW(out uint len, string filter, uint flags);
[DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
public static extern int CM_Get_Device_ID_ListW(string filter, char[] buffer, uint bufferLen, uint flags);
'@
# CM_GETIDLIST_FILTER_ENUMERATOR (0x1) | CM_GETIDLIST_FILTER_PRESENT (0x100): present devices under the USB enumerator
function Get-PresentUsbIds {
    $len = [uint32]0
    [void][Win32.CfgMgr]::CM_Get_Device_ID_List_SizeW([ref]$len, 'USB', 0x101)
    $buf = New-Object char[] $len
    [void][Win32.CfgMgr]::CM_Get_Device_ID_ListW('USB', $buf, $len, 0x101)
    (-join $buf).Split([char]0) | Where-Object { $_ }
}

Say "=== start; kill trigger: $Trigger ==="
$prev = ''; $killed = $false
$end = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $end) {
    $ids = Get-PresentUsbIds | Where-Object { $_ -match '^USB\\VID_(B58E&PID_000[56]|046D&PID_0AB1)\\' }
    $cur = (($ids | ForEach-Object { $_.Substring(4,17) }) | Sort-Object) -join ', '
    if ($cur -eq '') { $cur = '(none)' }
    if ($cur -ne $prev) { Say $cur; $prev = $cur }
    if (-not $killed -and $prev -ne '' -and $cur -match $Trigger) {
        $procs = Get-Process lghub, lghub_agent, lghub_gl, lghub_system_tray, lghub_updater -ErrorAction SilentlyContinue
        foreach ($p in $procs) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; Say "killed $($p.Name) [$($p.Id)]" } catch { Say "FAILED to kill $($p.Name): $($_.Exception.Message)" } }
        $killed = $true
        Say "=== G HUB killed; now just watching ==="
    }
    Start-Sleep -Milliseconds 50
}
Say "=== end ==="
