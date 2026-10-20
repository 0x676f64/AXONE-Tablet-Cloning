# Lists every account, every installed program (32 and 64 bit) and TEXA/Sentinel folders.
# Writes the report next to this script (on the USB) and opens it.
$out = Join-Path $PSScriptRoot 'factory-check-report.txt'
$r = @()
$r += "FACTORY CHECK   $(Get-Date)   computer: $env:COMPUTERNAME"
$r += ''
$r += '== ACCOUNTS =='
$r += (Get-LocalUser | Format-Table Name, FullName, Enabled -AutoSize | Out-String).Trim()
$r += ''
$r += '== INSTALLED PROGRAMS =='
$progs = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object DisplayName | Sort-Object DisplayName -Unique
$r += ($progs | Format-Table DisplayName, DisplayVersion, Publisher -AutoSize | Out-String -Width 250).Trim()
$r += ''
$r += '== TEXA / SENTINEL FOLDERS (should all be False) =='
foreach ($d in 'C:\Program Files (x86)\TEXA', 'C:\Program Files\TEXA', 'C:\ProgramData\TEXA', 'C:\Program Files (x86)\Common Files\Aladdin Shared', 'C:\Program Files\Common Files\Aladdin Shared') {
    $r += ("{0,-6} {1}" -f (Test-Path $d), $d)
}
$r += ''
$bad = $progs | Where-Object { $_.DisplayName -match 'IDC ?[56]|TeamViewer' -or $_.Publisher -match 'TeamViewer' }
$r += '== VERDICT =='
if ($bad) { $r += 'PROBLEM: found ' + (($bad.DisplayName) -join ', ') + '. Send this file to IT before going further.' }
else      { $r += 'CLEAN: no IDC5, IDC6 or TeamViewer installed. (TEXA SysEye and the Sentinel runtime are factory parts and are fine.)' }
$r | Set-Content -Path $out -Encoding UTF8
Start-Process notepad.exe $out
