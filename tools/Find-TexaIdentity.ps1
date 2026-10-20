<#
.SYNOPSIS
  Find where the "TEXA serial number" on a cloned Axeone tablet is stored.

.DESCRIPTION
  Run as administrator on a CLONED tablet. Pass the serial number that
  tech support / IDC6 shows for it. The script reports:
    1. The tablet's real hardware serials (BIOS, board, UUID) for comparison.
    2. What the Sentinel/HASP license manager on the tablet says about its
       key(s): hardware (HASP HL) or software (SL), and the key ID.
    3. Every file and registry value under the TEXA and Sentinel locations
       that contains the serial you gave it.
  Nothing is changed. Output is also saved to C:\Setup\texa-identity-report.txt.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Find-TexaIdentity.ps1 -Serial "AX123456"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string[]]$Serial,
    [switch]$WholeDisk   # also search the whole C: drive (slow, 10-30 min)
)

$ErrorActionPreference = 'SilentlyContinue'
$out = @()
function Say($t) { $script:out += $t; Write-Host $t }
function Head($t) { Say ''; Say ('=' * 70); Say $t; Say ('=' * 70) }

if (-not (Test-Path C:\Setup)) { New-Item C:\Setup -ItemType Directory | Out-Null }
$report = 'C:\Setup\texa-identity-report.txt'
$serials = $Serial | ForEach-Object { $_.Trim() } | Where-Object { $_ }

Head "1. HARDWARE IDENTITY (cannot be cloned)"
$bios = Get-CimInstance Win32_BIOS; $board = Get-CimInstance Win32_BaseBoard; $csp = Get-CimInstance Win32_ComputerSystemProduct
Say ("BIOS serial    : {0}" -f $bios.SerialNumber)
Say ("Board serial   : {0}" -f $board.SerialNumber)
Say ("Product UUID   : {0}" -f $csp.UUID)
Say ("Model          : {0} {1}" -f $csp.Vendor, $csp.Name)
Say ("Computer name  : {0}" -f $env:COMPUTERNAME)
foreach ($s in $serials) {
    $hw = @($bios.SerialNumber, $board.SerialNumber, $csp.UUID) | Where-Object { $_ -and $_ -like "*$s*" }
    if ($hw) { Say "  -> '$s' MATCHES a hardware serial. It is NOT cloned; it is this tablet's own." }
    else     { Say "  -> '$s' is NOT a hardware serial on this tablet. It lives in software (cloned)." }
}

Head "2. SENTINEL / HASP LICENSE MANAGER"
$svc = Get-Service hasplms
if ($svc) { Say ("Sentinel service: {0}" -f $svc.Status) } else { Say "Sentinel service (hasplms): not installed" }
$acc = $null
try { $acc = Invoke-WebRequest -Uri 'http://localhost:1947/_int_/devices.html' -UseBasicParsing -TimeoutSec 5 } catch {}
if ($acc) {
    $text = $acc.Content -replace '<script[\s\S]*?</script>', '' -replace '<[^>]+>', ' ' -replace '&nbsp;', ' ' -replace '\s+', ' '
    Say "Admin Control Center reachable (http://localhost:1947). Key table text:"
    # pull out anything that looks like a key row
    $hits = [regex]::Matches($text, '(HASP HL|Sentinel HL|SL-AdminMode|SL-UserMode|SL Legacy|HASP SL|Key Type|Key ID)[^|]{0,120}')
    if ($hits.Count) { foreach ($h in $hits) { Say ("   " + $h.Value.Trim()) } }
    else { Say "   (no key rows parsed; open http://localhost:1947 in a browser on the tablet and read the Sentinel Keys page)" }
    foreach ($s in $serials) { if ($text -like "*$s*") { Say "  -> '$s' appears in the Sentinel key list. It is a Sentinel key ID." } }
} else {
    Say "Admin Control Center not reachable on http://localhost:1947 (no Sentinel runtime, or it is disabled)."
}
$aladdin = "${env:ProgramFiles(x86)}\Common Files\Aladdin Shared\HASP"
if (Test-Path $aladdin) {
    Say "Sentinel license store: $aladdin"
    Get-ChildItem $aladdin -Recurse -File | ForEach-Object { Say ("   {0,10}  {1}  {2}" -f $_.Length, $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm'), $_.FullName.Substring($aladdin.Length + 1)) }
} else { Say "Sentinel license store folder not found." }

Head "3. SERIAL SEARCH - FILES"
$roots = @(
    "$env:ProgramData\TEXA", "$env:ProgramData\Texa", "$env:ProgramData\IDC5", "$env:ProgramData\IDC6",
    "$env:ProgramFiles\TEXA", "${env:ProgramFiles(x86)}\TEXA",
    "$env:ProgramFiles\IDC*", "${env:ProgramFiles(x86)}\IDC*",
    "${env:ProgramFiles(x86)}\Common Files\Aladdin Shared",
    "$env:ProgramFiles\Common Files\Aladdin Shared",
    "$env:ProgramData\SafeNet Sentinel", "$env:ProgramData\Thales",
    "$env:SystemRoot\System32\drivers\etc"
)
$roots += Get-ChildItem "$env:SystemDrive\Users\*\AppData\*\TEXA*" -Directory | Select-Object -ExpandProperty FullName
$roots += Get-ChildItem "$env:SystemDrive\Users\*\AppData\*\IDC*" -Directory | Select-Object -ExpandProperty FullName
$roots += Get-ChildItem "$env:SystemDrive\TEXA*", "$env:SystemDrive\IDC*" -Directory | Select-Object -ExpandProperty FullName
if ($WholeDisk) { $roots = @("$env:SystemDrive\") }
$roots = $roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
Say ("Searching: " + ($roots -join '; '))
$fileHits = 0
foreach ($r in $roots) {
    $files = Get-ChildItem -Path $r -Recurse -File | Where-Object { $_.Length -lt 50MB -and $_.FullName -notmatch '\\Windows\\(WinSxS|servicing|Installer)\\' }
    foreach ($f in $files) {
        foreach ($s in $serials) {
            $m = Select-String -Path $f.FullName -Pattern ([regex]::Escape($s)) -List
            if ($m) {
                $fileHits++
                Say ("  FILE  {0}" -f $f.FullName)
                Say ("        line {0}: {1}" -f $m.LineNumber, (($m.Line -replace '[^\x20-\x7E]', '.').Trim() | ForEach-Object { if ($_.Length -gt 160) { $_.Substring(0, 160) + '...' } else { $_ } }))
            }
        }
    }
}
if (-not $fileHits) { Say "  (no file under those folders contains the serial)" }

Head "4. SERIAL SEARCH - REGISTRY"
$tmp = Join-Path $env:TEMP 'hklm-software.reg'
$regHits = 0
foreach ($hive in 'HKLM\SOFTWARE', 'HKCU\SOFTWARE', 'HKLM\SYSTEM\CurrentControlSet\Services') {
    Remove-Item $tmp -Force
    & reg.exe export $hive $tmp /y | Out-Null
    if (Test-Path $tmp) {
        $cur = ''
        foreach ($line in [IO.File]::ReadLines($tmp, [Text.Encoding]::Unicode)) {
            if ($line.StartsWith('[')) { $cur = $line.Trim('[', ']'); continue }
            foreach ($s in $serials) {
                $hex = ($s.ToCharArray() | ForEach-Object { '{0:x2},00' -f [int]$_ }) -join ','
                if ($line -like "*$s*" -or $line -like "*$hex*") {
                    $regHits++
                    Say ("  REG   {0}" -f $cur)
                    Say ("        {0}" -f ($(if ($line.Length -gt 160) { $line.Substring(0, 160) + '...' } else { $line })))
                }
            }
        }
    }
}
Remove-Item $tmp -Force
if (-not $regHits) { Say "  (no registry value under HKLM\SOFTWARE, HKCU\SOFTWARE or Services contains the serial)" }

Head "5. WHAT THIS MEANS"
Say "If section 1 says the serial is NOT a hardware serial and sections 2-4 show where it is stored,"
Say "that location is the cloned identity. It must be created per tablet (install IDC6 after imaging)"
Say "or removed from the master before capture, with TEXA's confirmation of what is safe to remove."
Say "If section 2 shows a HASP HL (hardware) key with a DIFFERENT ID on two tablets, the key is per-tablet"
Say "and the shared serial is an IDC6 setting, not a license problem."

$out | Set-Content -Path $report -Encoding UTF8
Say ""
Say "Saved to $report"
