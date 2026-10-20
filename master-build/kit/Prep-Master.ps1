<#
.SYNOPSIS
  Prepare the master Axeone tablet for capture. Run as administrator on the master.

.DESCRIPTION
  Checks the master is in the right state, configures it, stages the first-boot
  task, cleans up, and shuts down ready for capture. It REFUSES to continue if
  IDC6 or TeamViewer is installed on the master, because that is exactly what put
  one identity on every tablet last time.

  Before running:
    - Windows Update is finished (run Update-Master.ps1 until it says clean)
    - Local user CEAS exists
    - Wallpaper applied
    - Staged files are in place:
        C:\Setup\TeamViewer\TeamViewer_Setup_x64.exe
      Optional: C:\Setup\IDC6\ with the IDC6 installer/ISOs, if the warehouse should
      install from files already on the tablet. Leave it out to keep the image small.
    - FirstBoot.ps1, Check-Tablet.cmd and Fix-TabletIdentity.ps1 in the same folder as this script
    - The CONFIG block at the top of FirstBoot.ps1 matches those paths

  -SkipShutdown   do everything but the final shutdown
#>
[CmdletBinding()]
param([switch]$SkipShutdown)

$ErrorActionPreference = 'Stop'
$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$SetupDir = 'C:\Setup'
$User     = 'CEAS'
$MasterName = 'CEAS-MASTER'
$fail = @(); $warn = @()
New-Item $SetupDir -ItemType Directory -Force | Out-Null
function OK($m)   { Write-Host "  [ OK ] $m" -ForegroundColor Green }
function Warn($m) { $script:warn += $m; Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Fail($m) { $script:fail += $m; Write-Host "  [FAIL] $m" -ForegroundColor Red }

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Host 'Run as administrator.' -ForegroundColor Red; exit 1 }

Write-Host "`n== 1. Must NOT be on the master ==" -ForegroundColor Cyan
$programs = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object DisplayName
$idc = $programs | Where-Object { $_.DisplayName -match 'IDC\s?[56]|TEXA|Sentinel|HASP|Aladdin' -or $_.Publisher -match 'TEXA|Thales|SafeNet|Gemalto|Aladdin' }
if ($idc) { Fail ("TEXA software (IDC5/IDC6/Sentinel) is INSTALLED on the master: " + (($idc.DisplayName | Select-Object -Unique) -join ', ') + ". Uninstall it (and reboot) before capture. Its identity would be cloned to every tablet.") } else { OK 'No IDC5, IDC6, TEXA or Sentinel software installed' }
if ($programs | Where-Object { $_.DisplayName -like 'TeamViewer*' }) { Fail 'TeamViewer is installed on the master. Uninstall it; it installs fresh on each tablet.' } else { OK 'TeamViewer not installed' }
# Factory Axones ship with TEXA SysEye (hardware monitor) and the Sentinel runtime. Both are fine to clone
# AS LONG AS the Sentinel key store holds no software (SL) key. The built-in hardware key (HL) is per tablet.
$masterKey = $null
try {
    $acc  = Invoke-WebRequest -Uri 'http://localhost:1947/_int_/devices.html' -UseBasicParsing -TimeoutSec 5
    $text = $acc.Content -replace '<script[\s\S]*?</script>', '' -replace '<[^>]+>', ' ' -replace '&nbsp;', ' ' -replace '\s+', ' '
    if ($text -match 'SL-AdminMode|SL-UserMode|SL Legacy|SL-Legacy') {
        Fail 'Sentinel holds a SOFTWARE (SL) license key. That is this tablet''s identity and would be cloned. Open localhost:1947 > Sentinel Keys and send IT a photo.'
    } else {
        $m = [regex]::Match($text, '(\d{6,12})\s+Sentinel HL')
        if ($m.Success) { $masterKey = $m.Groups[1].Value; OK "Sentinel: hardware key only (HL key ID $masterKey). No software key. Safe to clone." }
        else            { OK 'Sentinel: no software key found.' }
        $masterKey | Set-Content (Join-Path $SetupDir 'master-keyid.txt') -ErrorAction SilentlyContinue
    }
} catch { Warn 'Sentinel runtime not running (localhost:1947 unreachable). Fine if IDC5/TEXA was never installed.' }
foreach ($d in "${env:ProgramFiles(x86)}\TEXA", "$env:ProgramFiles\TEXA") {
    if (Test-Path $d) { Fail "Folder $d exists: IDC5/IDC6 program files are still present. Uninstall it, restart, run again." }
}
foreach ($d in "${env:ProgramFiles(x86)}\Texa S.p.A", "$env:ProgramData\Texa", "$env:ProgramData\SafeNet Sentinel", "${env:ProgramFiles(x86)}\Common Files\Aladdin Shared") {
    if (Test-Path $d) { OK "factory folder kept: $d" }
}

Write-Host "`n== 2. Staged files ==" -ForegroundColor Cyan
$fb = Join-Path $here 'FirstBoot.ps1'
if (-not (Test-Path $fb)) { Fail 'FirstBoot.ps1 not found next to this script' } else {
    $cfgText = Get-Content $fb -Raw
    $paths = [regex]::Matches($cfgText, "(Installer|Path|Iso)\s*=\s*'([^']+)'") | ForEach-Object { $_.Groups[2].Value } | Select-Object -Unique
    foreach ($p in $paths) {
        $hits = @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue)
        if ($hits.Count -eq 1)    { OK ("staged: " + $hits[0].FullName + "  ({0:N1} GB)" -f ($hits[0].Length / 1GB)) }
        elseif ($hits.Count -gt 1){ Fail "more than one file matches $p - leave only one: $(($hits.Name) -join ', ')" }
        else                      { Fail "missing staged installer: $p (copy it, or fix the CONFIG block in FirstBoot.ps1)" }
    }
    # IDC6 is installed by hand by the warehouse from C:\Setup\IDC6. Check the files are there; do not mount anything.
    if (Test-Path 'C:\Setup\IDC6\IDC6InstallerSetup.exe') { OK 'staged: C:\Setup\IDC6\IDC6InstallerSetup.exe' } else { Warn 'C:\Setup\IDC6\IDC6InstallerSetup.exe not found; the warehouse will need the installer on a USB stick.' }
    foreach ($envName in 'Truck', 'OHW') {
        $isos = @(Get-ChildItem "C:\Setup\IDC6\$envName\*.iso" -File -ErrorAction SilentlyContinue)
        if ($isos.Count -eq 1 -and $isos[0].Length -gt 1GB) { OK ("staged: {0}  ({1:N1} GB)" -f $isos[0].FullName, ($isos[0].Length / 1GB)) }
        elseif ($isos.Count -gt 1) { Fail "C:\Setup\IDC6\$envName has more than one .iso; leave only one" }
        elseif ($isos.Count -eq 1) { Fail "C:\Setup\IDC6\$envName\$($isos[0].Name) is only $([math]::Round($isos[0].Length/1MB)) MB; copy it again" }
        else { Warn "C:\Setup\IDC6\$envName has no .iso; IDC6 $envName data will not be on the tablets" }
        foreach ($i in $isos) {
            $di = Get-DiskImage -ImagePath $i.FullName -ErrorAction SilentlyContinue
            if ($di -and $di.Attached) { Dismount-DiskImage -ImagePath $i.FullName -ErrorAction SilentlyContinue | Out-Null; Warn "closed an open ISO: $($i.Name)" }
        }
    }
    if (Test-Path 'C:\Setup\IDC6') {
        $gb = (Get-ChildItem 'C:\Setup\IDC6' -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1GB
        OK ("C:\Setup\IDC6 staged ({0:N1} GB): installer + Truck/OHW ISOs. IDC6 mounts these ISOs at runtime; they must stay." -f $gb)
    } else { Warn 'C:\Setup\IDC6 is missing. The warehouse needs IDC6InstallerSetup.exe and the Truck/OHW ISOs on the tablet; IDC6 mounts the ISOs at runtime.' }
}
foreach ($f in 'Check-Tablet.cmd', 'Fix-TabletIdentity.ps1') { if (Test-Path (Join-Path $here $f)) { OK "found $f" } else { Fail "$f not found next to this script" } }

Write-Host "`n== 3. User and sign-in ==" -ForegroundColor Cyan
$u = Get-LocalUser -Name $User -ErrorAction SilentlyContinue
if (-not $u) { Fail "Local user $User does not exist" } else {
    if (-not $u.Enabled) { Fail "$User is disabled" }
    if (-not (Get-LocalGroupMember Administrators -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$User" })) { Add-LocalGroupMember -Group Administrators -Member $User; OK "$User added to Administrators" } else { OK "$User is an administrator" }
    if ($u.PasswordRequired) { Warn "$User has a password; auto sign-in below assumes none" }
    $others = Get-LocalUser | Where-Object { $_.Enabled -and $_.Name -ne $User -and $_.Name -notin 'Administrator','Guest','DefaultAccount','WDAGUtilityAccount','defaultuser0' }
    if ($others) { Warn ("Other enabled local accounts: " + ($others.Name -join ', ') + ". Disable them or auto sign-in may show the account picker.") }
}
if (-not $fail) {
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty $wl AutoAdminLogon '1'; Set-ItemProperty $wl DefaultUserName $User; Set-ItemProperty $wl DefaultPassword ''
    # No DefaultDomainName: it would hold the MASTER's name and break auto sign-in once the clone is renamed.
    # deploy.cmd writes the clone's own name there.
    Remove-ItemProperty $wl DefaultDomainName -ErrorAction SilentlyContinue
    Remove-ItemProperty $wl AutoLogonCount -ErrorAction SilentlyContinue
    OK "Auto sign-in as $User"
}

Write-Host "`n== 4. Settings ==" -ForegroundColor Cyan
if (-not $fail) {
    & powercfg /change standby-timeout-ac 0 | Out-Null; & powercfg /change monitor-timeout-ac 30 | Out-Null; & powercfg /change hibernate-timeout-ac 0 | Out-Null
    OK 'Never sleep on AC (first boot takes a while)'
    Set-TimeZone -Id 'Central Standard Time'; OK 'Time zone Central'
    if ($env:COMPUTERNAME -ine $MasterName) { Rename-Computer -NewName $MasterName -Force -WarningAction SilentlyContinue; Warn "Master renamed to $MasterName (takes effect at shutdown). FirstBoot refuses to run on a tablet with that name." } else { OK "Master name is $MasterName" }
    $wifi = (& netsh wlan show profiles) -match 'All User Profile' | ForEach-Object { ($_ -split ':', 2)[1].Trim() }
    if ($wifi) { Warn ("Wi-Fi profiles in the image: " + ($wifi -join ', ') + ". Tablets ship with these credentials. Use a provisioning SSID you can rotate.") } else { Warn 'No saved Wi-Fi profile. First boot needs network; tablets will wait up to 10 min for someone to connect them.' }
}

Write-Host "`n== 5. First-boot task ==" -ForegroundColor Cyan
if (-not $fail) {
    New-Item $SetupDir -ItemType Directory -Force | Out-Null
    Copy-Item $fb (Join-Path $SetupDir 'FirstBoot.ps1') -Force
    Copy-Item (Join-Path $here 'Check-Tablet.cmd') (Join-Path $SetupDir 'Check-Tablet.cmd') -Force
    Copy-Item (Join-Path $here 'Fix-TabletIdentity.ps1') (Join-Path $SetupDir 'Fix-TabletIdentity.ps1') -Force
    Copy-Item (Join-Path $here 'Check-Tablet.cmd') 'C:\Users\Public\Desktop\Check Tablet.cmd' -Force
    $lnk = 'C:\Users\Public\Desktop\IDC6 Install Files.lnk'
    if (Test-Path 'C:\Setup\IDC6') {
        $ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut($lnk); $sc.TargetPath = 'C:\Setup\IDC6'; $sc.Save()
        OK 'Desktop shortcut "IDC6 Install Files" -> C:\Setup\IDC6'
    } elseif (Test-Path $lnk) { Remove-Item $lnk -Force }
    Remove-Item (Join-Path $SetupDir 'provision-state.json'), (Join-Path $SetupDir 'provision-log.txt'), (Join-Path $SetupDir 'TABLET-STATUS.txt'), (Join-Path $SetupDir 'tablet-identity.txt'), (Join-Path $SetupDir 'identity-log.csv'), (Join-Path $SetupDir 'update-attempts.json'), (Join-Path $SetupDir 'update-log.txt') -ErrorAction SilentlyContinue
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$SetupDir\FirstBoot.ps1`""
    # The task is stored by the account's SID, not "CEAS-MASTER\CEAS": the clone gets a new
    # computer name, and a name-based task would fail to start after the rename. The SID survives cloning.
    $sid = (Get-LocalUser -Name $User).SID.Value
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $sid
    $trigger.Delay = 'PT20S'
    $principalT= New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName 'CEAS-FirstBoot' -Action $action -Trigger $trigger -Principal $principalT -Settings $settings -Force | Out-Null
    $t = Get-ScheduledTask -TaskName 'CEAS-FirstBoot' -ErrorAction SilentlyContinue
    if ($t) { OK "Scheduled task CEAS-FirstBoot registered (runs as $sid at logon, highest privileges)" } else { Fail 'Scheduled task CEAS-FirstBoot was NOT registered' }
}

Write-Host "`n== 6. Cleanup ==" -ForegroundColor Cyan
if (-not $fail) {
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\*", "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem 'C:\Users\*\AppData\Local\Temp' -Directory -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item "$($_.FullName)\*" -Recurse -Force -ErrorAction SilentlyContinue }
    $ErrorActionPreference = 'SilentlyContinue'
    foreach ($l in (& wevtutil el)) { & wevtutil cl "$l" 2>&1 | Out-Null }
    $ErrorActionPreference = 'Stop'
    OK 'Temp, update cache and event logs cleared'
    Write-Host '  Running component cleanup to shrink the image (5-15 min)...'
    $ErrorActionPreference = 'SilentlyContinue'
    & Dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    OK 'Component store cleaned'
}

Write-Host ''
if ($fail) {
    Write-Host "NOT READY FOR CAPTURE. Fix these and run again:" -ForegroundColor Red
    $fail | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
if ($warn) { Write-Host 'Warnings:' -ForegroundColor Yellow; $warn | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow } }
Write-Host "`nMASTER READY. Next: boot from the WinPE stick and capture with" -ForegroundColor Green
Write-Host '  Dism /Capture-Image /ImageFile:<usb>:\CEAS-Tablet.wim /CaptureDir:C:\ /Name:"CEAS Tablet" /Compress:max /CheckIntegrity' -ForegroundColor Green
Write-Host '(Put CAPTURE-MASTER.txt on the storage USB and boot the WinPE stick; deploy.cmd does this for you.)'
if (-not $SkipShutdown) { Write-Host 'Shutting down in 15 seconds.'; Start-Sleep 15; Stop-Computer -Force }
