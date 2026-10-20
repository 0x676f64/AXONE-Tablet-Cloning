<#
.SYNOPSIS
  CEAS Axeone first-boot provisioning. Runs once on each freshly imaged tablet.

.DESCRIPTION
  Installed on the master by Prep-Master.ps1 as scheduled task "CEAS-FirstBoot"
  (runs at CEAS logon, highest privileges). On a new clone it:
    1. Confirms this tablet got its own identity from deploy.cmd
    2. Waits for network
    3. Sets time zone and syncs the clock (IDC6 will not activate with a bad date)
    4. Installs TeamViewer fresh and waits for its unique ID
    5. Verifies everything and shows the status screen:
         YELLOW = automatic part done; warehouse installs IDC6 (Truck + OHW),
                  enters the key, sets the TeamViewer password, runs Check Tablet
         GREEN  = ready to ship
         RED    = problem; set aside for IT
       IDC6 is installed BY HAND by the warehouse (decided Oct 2026).
  Every step is logged to C:\Setup\provision-log.txt and recorded in
  C:\Setup\provision-state.json, so re-running skips what is already done.
  When all steps pass, the scheduled task removes itself.

  -VerifyOnly   Run only the checks and show the status screen. Used by the
                "Check Tablet" shortcut after the warehouse finishes by hand.

  ---- CONFIG: edit the block below to match the staged files on the master ----
#>
[CmdletBinding()]
param([switch]$VerifyOnly)

# ============================ CONFIG ============================
$Config = @{
    MasterName    = 'CEAS-MASTER'            # the master tablet's computer name; a clone must NOT have it
    TimeZone      = 'Central Standard Time'
    NetworkWaitMinutes = 10

    TeamViewer    = @{
        Installer = 'C:\Setup\TeamViewer\TeamViewer_Setup_x64.exe'
        Args      = '/S'
    }

    # How we recognise that IDC6 is installed: any Programs-and-Features entry matching this
    IDC6InstalledPattern = 'IDC6|IDC 6'   # IDC6 only; must not match IDC5 or other TEXA software
}
# ================================================================

$ErrorActionPreference = 'Stop'
$SetupDir  = 'C:\Setup'
$LogFile   = Join-Path $SetupDir 'provision-log.txt'
$StateFile = Join-Path $SetupDir 'provision-state.json'
$StatusFile= Join-Path $SetupDir 'TABLET-STATUS.txt'
$TaskName  = 'CEAS-FirstBoot'
$Host.UI.RawUI.WindowTitle = 'CEAS Tablet Setup'

function Log($msg, $color = 'Gray') {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $LogFile -Value $line
    Write-Host $msg -ForegroundColor $color
}
function Banner($text, $color) {
    Write-Host ''
    Write-Host ('=' * 64) -ForegroundColor $color
    foreach ($l in $text) { Write-Host ("   " + $l) -ForegroundColor $color }
    Write-Host ('=' * 64) -ForegroundColor $color
    Write-Host ''
}
function Get-State { if (Test-Path $StateFile) { Get-Content $StateFile -Raw | ConvertFrom-Json } else { [pscustomobject]@{} } }
function Set-Done($step) {
    $s = Get-State
    $s | Add-Member -NotePropertyName $step -NotePropertyValue (Get-Date).ToString('s') -Force
    $s | ConvertTo-Json | Set-Content $StateFile
}
function Is-Done($step) { $s = Get-State; return [bool]($s.PSObject.Properties[$step]) }

function Get-TeamViewerId {
    foreach ($k in 'HKLM:\SOFTWARE\TeamViewer', 'HKLM:\SOFTWARE\WOW6432Node\TeamViewer') {
        $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if ($p -and $p.ClientID) { return [int64]$p.ClientID }
    }
    return $null
}
function Test-TeamViewerPasswordSet {
    foreach ($k in 'HKLM:\SOFTWARE\TeamViewer', 'HKLM:\SOFTWARE\WOW6432Node\TeamViewer') {
        $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if ($p -and $p.PSObject.Properties['SecurityPasswordAES']) { return $true }
    }
    return $false
}
function Get-InstalledPrograms {
    $paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | Select-Object DisplayName, DisplayVersion
}
function Test-IDC6Installed { [bool](Get-InstalledPrograms | Where-Object { $_.DisplayName -match $Config.IDC6InstalledPattern }) }

function Test-Online {
    # TCP to port 80/443 first (works where ping is blocked), ping as fallback
    foreach ($t in @(@('www.msftconnecttest.com', 80), @('1.1.1.1', 443))) {
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $ar = $c.BeginConnect($t[0], $t[1], $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(3000) -and $c.Connected) { $c.Close(); return $true }
            $c.Close()
        } catch {}
    }
    try { if (Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue) { return $true } } catch {}
    return $false
}
function Sync-Clock {
    # Returns 'ntp', 'http' or $null. Runs with EAP=Continue: w32tm writes to stderr,
    # which would be a terminating error under Stop in PowerShell 5.1.
    $ErrorActionPreference = 'Continue'
    $how = $null
    try { Set-TimeZone -Id $Config.TimeZone } catch {}
    try {
        Set-Service w32time -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service w32time -ErrorAction SilentlyContinue
        $null = & w32tm /config /manualpeerlist:"time.windows.com,0x8" /syncfromflags:manual /update 2>&1
        $null = & w32tm /resync /force 2>&1
        Start-Sleep -Seconds 3
    } catch {}
    if ((Get-Date).Year -ge 2026) { $how = 'ntp' }
    if (-not $how) {
        # NTP blocked? Take the date from a web server's reply header instead.
        try {
            $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -Method Head -UseBasicParsing -TimeoutSec 15
            $hdr = $r.Headers['Date']
            if ($hdr) {
                Set-Date -Date ([DateTimeOffset]::Parse($hdr).LocalDateTime) | Out-Null
                if ((Get-Date).Year -ge 2026) { $how = 'http' }
            }
        } catch {}
    }
    $ErrorActionPreference = 'Stop'
    return $how
}

function Get-HLKeyId {
    try {
        $acc  = Invoke-WebRequest -Uri 'http://localhost:1947/_int_/devices.html' -UseBasicParsing -TimeoutSec 5
        $text = $acc.Content -replace '<script[\s\S]*?</script>', '' -replace '<[^>]+>', ' ' -replace '&nbsp;', ' ' -replace '\s+', ' '
        $m = [regex]::Match($text, '(\d{6,12})\s+Sentinel HL')
        if ($m.Success) { return $m.Groups[1].Value }
    } catch {}
    return $null
}

function Start-Installer([string]$Name, [string]$FilePath, [string]$ArgList, [bool]$Silent, [string]$WorkDir) {
    if (-not (Test-Path $FilePath)) { throw "$Name installer not found at $FilePath" }
    $sp = @{ FilePath = $FilePath; Wait = $true; PassThru = $true }
    if ($ArgList) { $sp.ArgumentList = $ArgList }
    if ($WorkDir) { $sp.WorkingDirectory = $WorkDir }
    if ($Silent) {
        Log "Installing $Name silently..." Cyan
    } else {
        Banner @("$Name installer is opening.",
                 "Click through it with the DEFAULT choices.",
                 "If it offers to start IDC6 at the end, untick that or close IDC6 afterward.",
                 "This window waits until the installer is finished.") Yellow
    }
    $p = Start-Process @sp
    Log "$Name installer exited with code $($p.ExitCode)"
    return $p.ExitCode
}

try {
$problems = @()
$identity = @{}
if (Test-Path (Join-Path $SetupDir 'tablet-identity.txt')) {
    Get-Content (Join-Path $SetupDir 'tablet-identity.txt') | ForEach-Object { if ($_ -match '^(\w+)=(.*)$') { $identity[$matches[1]] = $matches[2] } }
}

$runAuto = -not $VerifyOnly
if ($runAuto) {
    # FAILSAFE 1: once the automatic part has finished, it never runs again on this tablet,
    # even if the scheduled task somehow still exists.
    if (Is-Done 'auto-done') {
        Log 'Automatic setup already finished on this tablet; not running it again.' Yellow
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        $runAuto = $false
    }
}
if ($runAuto) {
    # FAILSAFE 2: at most 3 automatic attempts. After that the task is removed and the
    # warehouse finishes by hand (installers are staged in C:\Setup).
    $st = Get-State
    $runs = 1 + [int]$(if ($st.PSObject.Properties['runs']) { $st.runs } else { 0 })
    $st | Add-Member -NotePropertyName 'runs' -NotePropertyValue $runs -Force
    $st | ConvertTo-Json | Set-Content $StateFile
    if ($runs -gt 3) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        $problems += "Automatic setup ran $($runs - 1) times without finishing and has been switched off on this tablet. Finish by hand: TeamViewer installer is in C:\Setup\TeamViewer, IDC6 in C:\Setup\IDC6, then run Check Tablet."
        Log "RUN LIMIT: $($runs - 1) attempts; task removed." Red
        $runAuto = $false
    }
}
if ($runAuto) {
    Banner @('CEAS TABLET SETUP', 'Leave this tablet alone until this window shows YELLOW, GREEN or RED.', 'About 5 minutes.') Cyan
    Log "---- First boot run $runs started on $env:COMPUTERNAME ----"

    # ---- 1. Identity -------------------------------------------------------
    try {
        if ($env:COMPUTERNAME -ieq $Config.MasterName) { throw "This tablet still has the MASTER's name ($($Config.MasterName)). deploy.cmd did not set its identity. Re-image it." }
        if ($identity.ComputerName -and $env:COMPUTERNAME -ine $identity.ComputerName) { throw "Computer name is $env:COMPUTERNAME but deploy.cmd recorded $($identity.ComputerName)." }
        $guid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
        if ($identity.MachineGuid -and $guid -ine $identity.MachineGuid) { throw "MachineGuid does not match what deploy.cmd wrote." }
        Log "Identity OK: $env:COMPUTERNAME / $guid" Green
        Set-Done 'identity'
    } catch { $problems += $_.Exception.Message; Log "IDENTITY FAIL: $($_.Exception.Message)" Red }

    # ---- 2. Network --------------------------------------------------------
    $online = $false
    if (-not $problems) {
        Log "Waiting for network (up to $($Config.NetworkWaitMinutes) min)..."
        $deadline = (Get-Date).AddMinutes($Config.NetworkWaitMinutes)
        while ((Get-Date) -lt $deadline) {
            if (Test-Online) { $online = $true; break }
            Start-Sleep -Seconds 5
        }
        if ($online) { Log "Network OK" Green } else { $problems += "No network after $($Config.NetworkWaitMinutes) minutes. Connect the tablet to Wi-Fi, then run Check Tablet from the desktop."; Log "NETWORK FAIL" Red }
    }

    # ---- 3. Clock ----------------------------------------------------------
    if (-not $problems) {
        try {
            $how = Sync-Clock
            if (-not $how) { throw "Clock still shows $(Get-Date). Could not get the time from the internet. IDC6 will not activate until the date is right." }
            Log "Clock OK via $how : $(Get-Date)  ($($Config.TimeZone))" Green
            Set-Done 'clock'
        } catch { $problems += $_.Exception.Message; Log "CLOCK FAIL: $($_.Exception.Message)" Red }
    }

    # ---- 4. TeamViewer -----------------------------------------------------
    if (-not $problems) {
        try {
            if (Get-TeamViewerId) {
                Log "TeamViewer already installed, ID $(Get-TeamViewerId)" Green
            } else {
                $tvCode = Start-Installer -Name 'TeamViewer' -FilePath $Config.TeamViewer.Installer -ArgList $Config.TeamViewer.Args -Silent $true
                if ($tvCode -notin 0, 3010, 1641) { throw "TeamViewer installer failed (exit code $tvCode)" }
                $id = $null
                for ($i = 0; $i -lt 60 -and -not $id; $i++) { Start-Sleep -Seconds 3; $id = Get-TeamViewerId }
                if (-not $id) { throw "TeamViewer installed but has no ID after 3 minutes (needs internet)." }
                Log "TeamViewer OK: ID $id" Green
            }
            Set-Done 'teamviewer'
        } catch { $problems += $_.Exception.Message; Log "TEAMVIEWER FAIL: $($_.Exception.Message)" Red }
    }

}

# ---- 5. Verify (always) ----------------------------------------------------
$tvId   = Get-TeamViewerId
$tvPw   = Test-TeamViewerPasswordSet
$idc6   = Test-IDC6Installed
$guid   = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
$hlKey  = Get-HLKeyId
$masterKey = if (Test-Path (Join-Path $SetupDir 'master-keyid.txt')) { (Get-Content (Join-Path $SetupDir 'master-keyid.txt') -ErrorAction SilentlyContinue | Select-Object -First 1) } else { $null }
$checks = @(
    @{ Name = 'TEXA hardware key is this tablet''s own'; OK = (-not $hlKey -or -not $masterKey -or $hlKey -ne $masterKey); Value = $(if ($hlKey -and $masterKey -and $hlKey -eq $masterKey) { "SAME AS MASTER ($hlKey) - tell IT" } elseif ($hlKey) { "HL key ID $hlKey" } else { 'check by hand: Edge > localhost:1947 > Sentinel Keys' }) },
    @{ Name = 'Unique computer name';      OK = ($env:COMPUTERNAME -ine $Config.MasterName -and $env:COMPUTERNAME -like 'CEAS-*') ; Value = $env:COMPUTERNAME },
    @{ Name = 'MachineGuid matches deploy'; OK = (-not $identity.MachineGuid -or $guid -ieq $identity.MachineGuid); Value = $guid },
    @{ Name = 'Clock year is current';      OK = ((Get-Date).Year -ge 2026); Value = (Get-Date).ToString('yyyy-MM-dd HH:mm') },
    @{ Name = 'TeamViewer installed, has ID'; OK = [bool]$tvId; Value = $tvId },
    @{ Name = 'TeamViewer fixed password set'; OK = $tvPw; Value = $(if ($tvPw) { 'set' } else { 'NOT SET - warehouse step' }) },
    @{ Name = 'IDC6 installed';             OK = $idc6; Value = ((Get-InstalledPrograms | Where-Object { $_.DisplayName -match $Config.IDC6InstalledPattern } | ForEach-Object { $_.DisplayName }) -join ', ') }
)

$allGood = ($problems.Count -eq 0) -and -not ($checks | Where-Object { -not $_.OK })
$lines = @()
$lines += "CEAS TABLET STATUS   $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$lines += "Tablet name: $env:COMPUTERNAME     TeamViewer ID: $tvId     TEXA key ID: $(if ($hlKey) { $hlKey } else { 'see localhost:1947' })"
$lines += ''
foreach ($c in $checks) { $lines += ("[{0}] {1}: {2}" -f $(if ($c.OK) { ' OK ' } else { 'FAIL' }), $c.Name, $c.Value) }
foreach ($p in $problems) { $lines += "[FAIL] $p" }
$lines += ''
if ($allGood) {
    $lines += 'READY TO SHIP. Write the tablet name on the label.'
} elseif (-not $problems -and -not ($checks | Where-Object { -not $_.OK -and $_.Name -notin 'TeamViewer fixed password set', 'IDC6 installed' })) {
    $lines += 'AUTOMATIC SETUP DONE. Warehouse, in this order:'
    $lines += '   1) Install IDC6 (Truck and OHW) the usual way'
    $lines += '   2) Open IDC6 and enter this tablet''s activation key'
    $lines += '   3) Set the TeamViewer fixed password'
    $lines += '   4) Double-click "Check Tablet" on the desktop. GREEN = ship.'
} else {
    $lines += 'NOT READY. Fix the FAIL lines above, then double-click "Check Tablet" on the desktop.'
    $lines += 'Manual fallback: installers are on this tablet in C:\Setup\TeamViewer and C:\Setup\IDC6.'
    $lines += 'If it fails again, set this tablet aside and tell IT.'
}
$lines | Set-Content $StatusFile
Add-Content $LogFile ("STATUS: " + $(if ($allGood) { 'READY' } else { 'NOT READY' }))

$warehouseOnly = -not $problems -and -not ($checks | Where-Object { -not $_.OK -and $_.Name -notin 'TeamViewer fixed password set', 'IDC6 installed' })
$color = if ($allGood) { 'Green' } elseif ($warehouseOnly) { 'Yellow' } else { 'Red' }
Banner $lines $color

if ($allGood -or $warehouseOnly) {
    if (-not (Is-Done 'auto-done')) { Set-Done 'auto-done' }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) { Log 'Automatic setup complete; first-boot task removed. It will not run again.' Green }
    else { Log 'WARNING: could not remove the first-boot task; the auto-done marker will stop it from running again.' Yellow }
}

}
catch {
    $msg = "UNEXPECTED ERROR: $($_.Exception.Message)  (line $($_.InvocationInfo.ScriptLineNumber))"
    try { Add-Content -Path $LogFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $msg) } catch {}
    Banner @('NOT READY', $msg, 'Set this tablet aside and tell IT. The log is C:\Setup\provision-log.txt') Red
}
Write-Host 'Press any key to close this window.'
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
