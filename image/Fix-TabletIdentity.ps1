<#
.SYNOPSIS
  Identify and fix cloned CEAS Axeone tablets that are already in the field.

.DESCRIPTION
  Run over TeamViewer in an ELEVATED PowerShell (right-click > Run as administrator).

  NO SWITCHES = REPORT ONLY. Nothing is changed. Shows every value that could be
  what Tech Support is seeing as "the serial number", flags the ones that are
  generic factory placeholders, and appends a row to C:\Setup\identity-log.csv.
  Run it on two tablets and compare: whichever values match is the problem.

  -Rename [-AssetTag <sticker serial>]
      Give the tablet a unique computer name. With -AssetTag, the name is
      CEAS-<sticker serial> so the name on screen matches the label on the back
      (have the customer read it to you). Without it, CEAS-<last 6 of the Wi-Fi MAC>.
      Applies at the next restart. TeamViewer ID is NOT affected, so you keep access.

  -Restart
      Restart now so the new name takes effect. TeamViewer comes back on its own
      after the boot (the unattended password survives a reboot).

  -ResetTeamViewer -Force
      LAST RESORT, only if two tablets report the SAME TeamViewer ID.
      Uninstalls TeamViewer, clears its registry, gives Windows a new MachineGuid,
      reinstalls TeamViewer from C:\Setup, then shows the NEW ID and password on the
      tablet's screen. YOUR SESSION DROPS. Have the customer on the phone to read the
      new ID/password back to you, then reconnect and set the fixed password again.
      Requires the installer to be present in C:\Setup (checked BEFORE anything is
      touched). IDC6 licensing is bound to the built-in HASP, not to MachineGuid.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File C:\Setup\Fix-TabletIdentity.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File C:\Setup\Fix-TabletIdentity.ps1 -Rename -AssetTag AX24-01187 -Restart

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File C:\Setup\Fix-TabletIdentity.ps1 -ResetTeamViewer -Force
#>
[CmdletBinding()]
param(
    [switch]$Rename,
    [string]$AssetTag,
    [switch]$Restart,
    [switch]$ResetTeamViewer,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$logDir   = 'C:\Setup'
$logFile  = Join-Path $logDir 'identity-log.csv'
$ceasKey  = 'HKLM:\SOFTWARE\CEAS\Identity'
$cryptKey = 'HKLM:\SOFTWARE\Microsoft\Cryptography'
$tvKeys   = @('HKLM:\SOFTWARE\TeamViewer', 'HKLM:\SOFTWARE\WOW6432Node\TeamViewer')

if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

# Placeholder values OEMs leave in SMBIOS when the serial was never programmed
$genericSerials = @('', '0', '00000000', 'none', 'n/a', 'na', 'not applicable', 'not specified',
    'default string', 'to be filled by o.e.m.', 'system serial number', 'base board serial number',
    'oem', 'unknown', '123456789', '1234567890', '0123456789', 'serial', 'ffffffff')
function Test-Generic([string]$v) {
    $t = "$v".Trim().ToLower()
    if ($genericSerials -contains $t) { return $true }
    if ($t -match '^(0+|f+|x+)$') { return $true }
    return $false
}

function Get-TeamViewerInfo {
    $info = [ordered]@{ ID = $null; Version = $null; Key = $null }
    foreach ($k in $tvKeys) {
        $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if ($p -and $p.ClientID) {
            $info.ID = [int64]$p.ClientID; $info.Version = $p.Version; $info.Key = $k; break
        }
    }
    return $info
}

function Get-MachineSid {
    try {
        $acct = New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, 'Administrator')
        return $acct.Translate([System.Security.Principal.SecurityIdentifier]).AccountDomainSid.Value
    } catch { return $null }
}

function ConvertTo-ComputerName([string]$raw) {
    # NetBIOS rules: 1-15 chars, letters/digits/hyphen, not all digits
    $clean = (($raw -replace '[^A-Za-z0-9-]', '') -replace '^-+|-+$', '').ToUpper()
    if ($clean.Length -gt 10) { $clean = $clean.Substring($clean.Length - 10) }   # keep the tail, it's the part that varies
    if ($clean.Length -lt 3)  { return $null }
    return "CEAS-$clean"
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$changing  = $Rename -or $Restart -or $ResetTeamViewer -or $AssetTag
if ($changing -and -not $isAdmin) {
    Write-Host 'Changes need an elevated PowerShell (Run as administrator). Report only would work without it.' -ForegroundColor Red
    exit 1
}
if ($ResetTeamViewer -and -not $Force) {
    Write-Host '-ResetTeamViewer drops your session and changes the TeamViewer ID. Add -Force if you mean it.' -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------ REPORT
$bios  = Get-CimInstance Win32_BIOS
$board = Get-CimInstance Win32_BaseBoard
$csp   = Get-CimInstance Win32_ComputerSystemProduct
$enc   = Get-CimInstance Win32_SystemEnclosure | Select-Object -First 1
$disk  = Get-CimInstance Win32_DiskDrive | Where-Object { $_.Index -eq 0 } | Select-Object -First 1
$tv    = Get-TeamViewerInfo
$ceas  = Get-ItemProperty -Path $ceasKey -ErrorAction SilentlyContinue

$nic = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
    Where-Object { $_.MacAddress } |
    Sort-Object @{ Expression = { if ($_.PhysicalMediaType -match '802\.11' -or $_.Name -match 'Wi-?Fi|Wireless|WLAN') { 0 } else { 1 } } }, ifIndex |
    Select-Object -First 1
$mac = if ($nic) { ($nic.MacAddress -replace '[-:]', '').ToUpper() } else { $null }

$row = [ordered]@{
    Timestamp          = (Get-Date).ToString('s')
    ComputerName       = $env:COMPUTERNAME
    AssetTag           = if ($ceas) { $ceas.AssetTag } else { $null }
    # --- firmware (cannot be changed by imaging; generic = never programmed by the OEM)
    BiosSerial         = $bios.SerialNumber
    BiosSerialGeneric  = Test-Generic $bios.SerialNumber
    BoardSerial        = $board.SerialNumber
    BoardSerialGeneric = Test-Generic $board.SerialNumber
    ChassisSerial      = if ($enc) { $enc.SerialNumber } else { $null }
    ChassisAssetTag    = if ($enc) { $enc.SMBIOSAssetTag } else { $null }
    ProductUUID        = $csp.UUID
    Manufacturer       = $csp.Vendor
    Model              = $csp.Name
    # --- Windows identity (cloned from the master unless deploy.cmd fixed it)
    MachineGuid        = (Get-ItemProperty -Path $cryptKey).MachineGuid
    MachineSID         = Get-MachineSid
    ImagedWithIdentity = [bool]($ceas -and $ceas.ComputerName)
    # --- always unique per unit
    TeamViewerID       = $tv.ID
    TeamViewerVersion  = $tv.Version
    PrimaryMAC         = $mac
    DiskSerial         = if ($disk) { "$($disk.SerialNumber)".Trim() } else { $null }
    # --- what this run changed
    NewName            = ''
    NewMachineGuid     = ''
    NewTeamViewerID    = ''
    Error              = ''
}

# ------------------------------------------------------------------ RENAME
try {
    if ($Rename -or $AssetTag) {
        $target = $null
        if ($AssetTag) {
            $target = ConvertTo-ComputerName $AssetTag
            if (-not $target) { throw "AssetTag '$AssetTag' has too few usable characters for a computer name." }
            New-Item -Path $ceasKey -Force | Out-Null
            Set-ItemProperty -Path $ceasKey -Name AssetTag -Value $AssetTag
            $row.AssetTag = $AssetTag
        }
        if ($Rename -and -not $target) {
            $suffix = if ($mac) { $mac.Substring($mac.Length - 6) } else { (Get-Random -Maximum 0xFFFFFF).ToString('X6') }
            $target = "CEAS-$suffix"
        }
        if ($target -and $env:COMPUTERNAME -ne $target) {
            Rename-Computer -NewName $target -Force -WarningAction SilentlyContinue
            New-Item -Path $ceasKey -Force | Out-Null
            Set-ItemProperty -Path $ceasKey -Name ComputerName -Value $target
            Set-ItemProperty -Path $ceasKey -Name RenamedOn -Value (Get-Date).ToString('s')
            $row.NewName = $target
        }
    }
}
catch { $row.Error = $_.Exception.Message }

# ------------------------------------------------------------------ TEAMVIEWER RESET
if ($ResetTeamViewer -and -not $row.Error) {
    try {
        # Find the installer FIRST. Nothing is removed unless we can put it back.
        $installCmd = Get-ChildItem -Path $logDir -Filter 'install-teamviewer.cmd' -ErrorAction SilentlyContinue | Select-Object -First 1
        $installExe = Get-ChildItem -Path $logDir -Filter 'TeamViewer*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $installCmd -and -not $installExe) {
            throw "No TeamViewer installer found in $logDir (install-teamviewer.cmd or TeamViewer*.exe). Copy one there first."
        }

        $uninst = $null
        foreach ($u in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\TeamViewer',
                       'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\TeamViewer') {
            $p = Get-ItemProperty -Path $u -ErrorAction SilentlyContinue
            if ($p -and $p.UninstallString) { $uninst = $p.UninstallString.Trim('"'); break }
        }

        $oldId = $tv.ID
        Write-Host "Resetting TeamViewer (old ID $oldId). Your session will drop now." -ForegroundColor Yellow
        Start-Sleep -Seconds 3

        Stop-Service -Name TeamViewer -Force -ErrorAction SilentlyContinue
        Get-Process -Name 'TeamViewer*', 'tv_*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if ($uninst -and (Test-Path $uninst)) {
            Start-Process -FilePath $uninst -ArgumentList '/S' -Wait
        }
        foreach ($k in $tvKeys + 'HKCU:\SOFTWARE\TeamViewer') {
            Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue
        }
        foreach ($d in "$env:ProgramFiles\TeamViewer", "${env:ProgramFiles(x86)}\TeamViewer", "$env:ProgramData\TeamViewer") {
            if ($d -and (Test-Path $d)) { Remove-Item -Path $d -Recurse -Force -ErrorAction SilentlyContinue }
        }

        $g = [guid]::NewGuid().ToString()
        Set-ItemProperty -Path $cryptKey -Name MachineGuid -Value $g
        $row.NewMachineGuid = $g
        New-Item -Path $ceasKey -Force | Out-Null
        Set-ItemProperty -Path $ceasKey -Name MachineGuid -Value $g

        if ($installCmd) { Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$($installCmd.FullName)`"" -Wait }
        else             { Start-Process -FilePath $installExe.FullName -ArgumentList '/S' -Wait }

        # Wait for the service to register and get an ID
        $newId = $null
        for ($i = 0; $i -lt 60 -and -not $newId; $i++) {
            Start-Sleep -Seconds 3
            $t = Get-TeamViewerInfo
            if ($t.ID -and $t.ID -ne $oldId) { $newId = $t.ID }
        }
        $row.NewTeamViewerID = $newId

        $msg = if ($newId) {
            "TeamViewer has been reset.`n`nNEW TeamViewer ID:  $newId`n`nPlease open TeamViewer and read the ID and the PASSWORD shown there to CEAS Tech Support."
        } else {
            "TeamViewer was reinstalled but has not reported an ID yet.`n`nPlease open TeamViewer and read the ID and PASSWORD shown there to CEAS Tech Support."
        }
        "NewTeamViewerID=$newId`nReset=$((Get-Date).ToString('s'))" | Set-Content -Path (Join-Path $logDir 'teamviewer-reset.txt')
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($msg, 'CEAS Tech Support', 'OK', 'Information') | Out-Null
    }
    catch { $row.Error = $_.Exception.Message }
}

# ------------------------------------------------------------------ OUTPUT
[pscustomobject]$row | Export-Csv -Path $logFile -NoTypeInformation -Append -Force
[pscustomobject]$row | Format-List

if ($row.Error) { Write-Host "ERROR: $($row.Error)" -ForegroundColor Red }

$flags = @()
if ($row.BiosSerialGeneric  -eq $true) { $flags += 'BIOS serial is a factory placeholder - every unit of this model will show it. Imaging did not cause this and cannot fix it.' }
if ($row.BoardSerialGeneric -eq $true) { $flags += 'Board serial is a factory placeholder.' }
if (-not $row.ImagedWithIdentity)      { $flags += 'Imaged BEFORE the identity fix: computer name, MachineGuid and SID are the master''s. Compare TeamViewerID with another unit.' }
if (-not $row.TeamViewerID)            { $flags += 'TeamViewer ID not found in the registry - is TeamViewer installed?' }
foreach ($f in $flags) { Write-Host "  ! $f" -ForegroundColor Yellow }

if ($row.NewName) {
    Write-Host "`nRenamed to $($row.NewName). Takes effect after a restart." -ForegroundColor Green
    Write-Host "Also set this tablet's alias in CEAS's TeamViewer contacts to $($row.NewName)."
}

# One line to paste into the tracking sheet: name | TV ID | asset tag | BIOS serial | disk serial
$paste = ($(if ($row.NewName) { $row.NewName } else { $row.ComputerName }), $row.TeamViewerID, $row.AssetTag, $row.BiosSerial, $row.DiskSerial) -join ' | '
Write-Host "`nTracking line:  $paste"
Write-Host "Logged to $logFile"

if ($Restart -and -not $row.Error) {
    Write-Host 'Restarting in 10 seconds. Reconnect with the same TeamViewer ID and password once it is back.' -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
