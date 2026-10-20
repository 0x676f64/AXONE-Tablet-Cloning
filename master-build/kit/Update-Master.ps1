<#
.SYNOPSIS
  Bring the master fully up to date. Run as administrator; repeat after each restart until it says CLEAN.

.DESCRIPTION
  Why it could loop before, and what this version does about each:
    - Defender virus definitions are re-released several times a day, so there was
      always "one more update". Definitions are now skipped (the clones get them on
      their own after shipping).
    - Driver updates from Windows Update can replace Axeone's factory drivers.
      Drivers are now skipped; the factory drivers are what the tablet ships with.
    - Windows version upgrades (feature updates) are skipped; the master stays on
      the version it came with.
    - An update that keeps failing would be offered forever. Each update is counted;
      after 2 failed attempts it is hidden and listed as STUCK so the loop ends.
    - Running it again before restarting re-offers the same updates. It now checks
      for a pending restart first and stops with RESTART NOW.
  Everything is logged to C:\Setup\update-log.txt.
#>
$ErrorActionPreference = 'Stop'
$SetupDir = 'C:\Setup'
$Log      = Join-Path $SetupDir 'update-log.txt'
$Tries    = Join-Path $SetupDir 'update-attempts.json'
New-Item $SetupDir -ItemType Directory -Force | Out-Null
function Say($m, $c = 'Gray') { Add-Content $Log ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m); Write-Host $m -ForegroundColor $c }

Say "---- Update-Master run ----" Cyan

function Get-UKey($u) {
    foreach ($v in @($u.KB, ($u.KBArticleIDs -join ','), $u.Title, $u.Identity.UpdateID)) {
        if ($v -and "$v".Trim()) { return "$v".Trim() }
    }
    return $null
}


# 1. Module
try {
    if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
        Say 'Installing the Windows Update module (one time)...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        Set-PSRepository PSGallery -InstallationPolicy Trusted
        Install-Module PSWindowsUpdate -Force -Scope AllUsers
    }
    Import-Module PSWindowsUpdate
} catch {
    Say "Could not install the Windows Update module: $($_.Exception.Message)" Red
    Say 'Check the tablet has internet (open a website in Edge), then run this again.' Red
    exit 1
}

# 2. Pending restart?
if (Get-WURebootStatus -Silent) {
    Say 'RESTART NOW. Updates are installed but waiting for a restart. Restart, sign in as CEAS, run this again.' Yellow
    exit 0
}

# 3. What is available (skipping drivers, version upgrades, virus definitions). Windows Update only.
$skip = @('Drivers', 'Upgrades', 'Definition Updates')
try {
    $available = @(Get-WindowsUpdate -NotCategory $skip)
} catch {
    Say "Could not check for updates: $($_.Exception.Message)" Red
    Say 'Usually no internet. Open a website in Edge to confirm, then run this again.' Red
    exit 1
}
$attempts = @{}
if (Test-Path $Tries) { (Get-Content $Tries -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $attempts[$_.Name] = [int]$_.Value } }

$stuck = @(); $todo = @()
foreach ($u in $available) {
    $key = Get-UKey $u
    if (-not $key) { Say ('   (ignored an entry with no update name: ' + ($u | Out-String).Trim() + ')'); continue }
    if ($attempts.ContainsKey($key) -and $attempts[$key] -ge 2) { $stuck += $u } else { $todo += $u }
}
foreach ($u in $stuck) {
    Say "STUCK (failed twice, hiding it): $($u.Title)" Yellow
    try {
        if ($u.KB) { Get-WindowsUpdate -KBArticleID $u.KB -Hide -AcceptAll -Confirm:$false | Out-Null }
        else       { Get-WindowsUpdate -Title $u.Title -Hide -AcceptAll -Confirm:$false | Out-Null }
    } catch { Say "  could not hide it: $($_.Exception.Message)" Yellow }
}

if (-not $todo) {
    Say 'CLEAN - no updates left to install.' Green
    if ($stuck) { Say ("Hidden as stuck: " + (($stuck | ForEach-Object Title) -join '; ')) Yellow }
    Say 'Next: 5-Disable-Factory-User.cmd, then 6-Run-Prep-Master.cmd' Green
    Remove-Item $Tries -ErrorAction SilentlyContinue
    exit 0
}

Say ("Installing {0} update(s):" -f $todo.Count) Cyan
$todo | ForEach-Object { Say ("   - {0}" -f $_.Title) }
foreach ($u in $todo) { $key = Get-UKey $u; if (-not $key) { continue }; $attempts[$key] = 1 + $(if ($attempts.ContainsKey($key)) { [int]$attempts[$key] } else { 0 }) }
$attempts | ConvertTo-Json | Set-Content $Tries

try {
    $results = @(Install-WindowsUpdate -NotCategory $skip -AcceptAll -IgnoreReboot -Confirm:$false)
} catch {
    Say "Install run stopped early: $($_.Exception.Message)" Yellow
    Say 'RESTART NOW, sign in as CEAS, and run this again. Whatever installed stays installed.' Yellow
    exit 0
}
foreach ($r in $results) { Say ("   {0,-10} {1}" -f $r.Result, $r.Title) }
$failed = @($results | Where-Object { $_.Result -match 'Fail|Abort' })
if ($failed) { Say ("{0} update(s) failed this round; they will be retried once more, then hidden." -f $failed.Count) Yellow }

Say 'RESTART NOW, sign in as CEAS, and run this again until it says CLEAN.' Yellow
