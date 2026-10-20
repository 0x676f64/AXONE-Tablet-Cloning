# Confirms C:\Setup is laid out exactly as the scripts expect. Writes a report onto the USB.
$out = Join-Path $PSScriptRoot 'master-files-report.txt'
$r = @("MASTER FILE CHECK   $(Get-Date)   signed in as: $env:USERNAME", '')
$ok = $true
foreach ($p in 'C:\Setup\kit\Update-Master.ps1', 'C:\Setup\kit\Prep-Master.ps1', 'C:\Setup\kit\FirstBoot.ps1', 'C:\Setup\kit\Check-Tablet.cmd', 'C:\Setup\kit\Fix-TabletIdentity.ps1', 'C:\Setup\TeamViewer\TeamViewer_Setup_x64.exe') {
    $t = Test-Path $p; if (-not $t) { $ok = $false }
    $r += ("{0,-6} {1}" -f $(if ($t) { 'OK' } else { 'MISSING' }), $p)
}
if (Test-Path 'C:\Setup\IDC6') {
    $gb = (Get-ChildItem 'C:\Setup\IDC6' -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1GB
    $r += ("OK     C:\Setup\IDC6 staged ({0:N1} GB) - installer + Truck/OHW ISOs, keep them" -f $gb)
} else { $ok = $false; $r += 'MISSING C:\Setup\IDC6 (IDC6InstallerSetup.exe + Truck\ + OHW\)' }
foreach ($bad in 'C:\Setup\kit\kit', 'C:\Setup\kit\1-master', 'C:\Setup\kit\master-build') { if (Test-Path $bad) { $ok = $false; $r += "WRONG  $bad exists: the five script files go straight into C:\Setup\kit, not in a subfolder" } }
if ($env:USERNAME -ne 'CEAS') { $ok = $false; $r += "WRONG  signed in as $env:USERNAME, not CEAS" }
$r += ''
$r += $(if ($ok) { 'ALL GOOD. Next: double-click 4-Run-Update-Master.cmd' } else { 'FIX THE LINES ABOVE, then run this check again.' })
$r | Set-Content -Path $out -Encoding UTF8
Start-Process notepad.exe $out
