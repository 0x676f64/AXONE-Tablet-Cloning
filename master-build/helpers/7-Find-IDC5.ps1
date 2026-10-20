# Finds every trace of IDC5 / TEXA on the master: shortcuts, per-user installs, startup items,
# scheduled tasks, services, folders. Report saved next to this script and opened in Notepad.
$out = Join-Path $PSScriptRoot 'idc5-trace-report.txt'
$pat = 'IDC ?5|IDC ?6|TEXA|Axone|Navigator|Sentinel|HASP|Aladdin'
$r = @("IDC5 / TEXA TRACE   $(Get-Date)   signed in as $env:USERNAME", '')

$r += '== SHORTCUTS (desktop + Start menu, all users) =='
$sh = New-Object -ComObject WScript.Shell
$lnkRoots = @("$env:PUBLIC\Desktop", "$env:ProgramData\Microsoft\Windows\Start Menu") + (Get-ChildItem 'C:\Users' -Directory | ForEach-Object { "$($_.FullName)\Desktop"; "$($_.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu" })
foreach ($root in $lnkRoots) {
    Get-ChildItem $root -Recurse -Include *.lnk, *.url -ErrorAction SilentlyContinue | ForEach-Object {
        $t = ''; try { $t = $sh.CreateShortcut($_.FullName).TargetPath } catch {}
        if ($_.Name -match $pat -or $t -match $pat) { $r += "  $($_.FullName)`n      -> $t" }
    }
}

$r += ''; $r += '== PER-USER INSTALLS (HKCU of every profile) =='
foreach ($hive in (Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.Name -match 'S-1-5-21' -and $_.Name -notmatch '_Classes$' })) {
    $sidName = $hive.PSChildName
    Get-ItemProperty "Registry::$($hive.Name)\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $pat -or $_.Publisher -match $pat } |
        ForEach-Object { $r += "  [$sidName] $($_.DisplayName)   uninstall: $($_.UninstallString)" }
}
$r += '  (profiles not signed in since boot are not loaded; see folders below)'

$r += ''; $r += '== STARTUP ITEMS =='
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run') {
    $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
    if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and ($_.Name -match $pat -or $_.Value -match $pat) } | ForEach-Object { $r += "  $k : $($_.Name) = $($_.Value)" } }
}
Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp", "C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pat } | ForEach-Object { $r += "  $($_.FullName)" }

$r += ''; $r += '== SCHEDULED TASKS =='
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -match $pat -or $_.TaskPath -match $pat -or ($_.Actions | ForEach-Object { $_.Execute }) -match $pat } | ForEach-Object { $r += "  $($_.TaskPath)$($_.TaskName)  ->  $(($_.Actions | ForEach-Object Execute) -join '; ')" }

$r += ''; $r += '== SERVICES =='
Get-CimInstance Win32_Service | Where-Object { $_.Name -match $pat -or $_.DisplayName -match $pat -or $_.PathName -match $pat } | ForEach-Object { $r += "  $($_.Name)  ($($_.State))  $($_.PathName)" }

$r += ''; $r += '== APPX / STORE APPS (all users) =='
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pat -or $_.Publisher -match $pat } | ForEach-Object { $r += "  $($_.Name)  $($_.PackageFullName)" }

$r += ''; $r += '== FOLDERS (2 levels under Program Files, ProgramData, each user profile, C:\) =='
$dirs = @('C:\', 'C:\Program Files', 'C:\Program Files (x86)', 'C:\ProgramData', 'C:\Users\Public') + (Get-ChildItem 'C:\Users' -Directory | ForEach-Object { $_.FullName; "$($_.FullName)\AppData\Local"; "$($_.FullName)\AppData\Roaming"; "$($_.FullName)\Desktop" })
foreach ($d in $dirs) {
    Get-ChildItem $d -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pat } | ForEach-Object { $r += "  $($_.FullName)" }
}
Get-ChildItem 'C:\' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pat } | ForEach-Object { $r += "  $($_.FullName)" }

$r += ''; $r += 'Send this file to IT. Nothing was changed.'
$r | Set-Content $out -Encoding UTF8
Start-Process notepad.exe $out
