# CEAS Axone Provisioning

Clones one prepared Axone tablet onto many, with a unique Windows identity,
TeamViewer ID and TEXA (IDC6) identity on every unit.

Windows is cloned. TeamViewer installs fresh on each tablet at first boot.
The warehouse installs IDC6 (Truck + OHW) by hand, enters the IDC6 key, sets the
TeamViewer password, and ships. IDC6 is never in the image: that is what gave every
tablet the same TEXA serial in Sept 2026.

Not in this repo (too big or licensed, kept on the IT PC):
`CEAS-Tablet.wim` (~56 GB), `IDC6InstallerSetup.exe`, the TEXA ISOs, `TeamViewer_Setup_x64.exe`, the wallpaper.
Do not move or delete `C:\Setup\IDC6` on shipped tablets: IDC6 mounts its ISOs from there.

---

## The three sticks

| Label | Size / format | What is on it | Who uses it |
|---|---|---|---|
| **BOOT** | any, written by Rufus | `CEAS-WinPE.iso`, burned by Rufus. Nothing copied by hand. | Every station |
| **IMAGE** | 128 GB+, **exFAT** | `CEAS-Tablet.wim` + `image/Fix-TabletIdentity.ps1`, loose in the root | Every station |
| **MASTER BUILD** | any | `master-build/helpers/*` loose in the root, plus the installers to copy onto a master | IT only |

Warehouse stations get **BOOT + IMAGE**. MASTER BUILD never leaves IT.

---

## Repo layout: where each folder goes

| Repo folder | Goes to | Notes |
|---|---|---|
| `boot/` | Your PC only | Run `build-winpe-iso.cmd` as admin, burn the ISO to BOOT with Rufus (GPT / UEFI). **Any change here = rebuild the ISO and re-burn BOOT.** |
| `master-build/kit/` | `C:\Setup\kit\` on the master | The five **files**, not the folder. |
| `master-build/helpers/` | MASTER BUILD stick root | Double-click on the master in numbered order. |
| `image/` | IMAGE stick root | Next to `CEAS-Tablet.wim`. |
| `field-fix/` | Tech support | Fix for tablets shipped before this process. |
| `tools/` | As needed | `Find-TexaIdentity.ps1`: finds where a TEXA serial lives on a tablet. |

---

## Master tablet layout (`C:\`)

```
C:\Setup\
  kit\                         <- master-build/kit/* (5 files)
  TeamViewer\TeamViewer_Setup_x64.exe
  IDC6\IDC6InstallerSetup.exe   <- NOT installed. Warehouse runs it by hand.
  IDC6\Truck\  IDC6\OHW\        <- TEXA ISOs + .dat/.xml/.log. IDC6 MOUNTS these at runtime,
                                  so they stay on every tablet for good (~32 GB of the image).
                                  Every clone gets an "IDC6 Install Files" desktop shortcut.
C:\Windows\Web\Wallpaper\CEAS\Tablet Backgroundfixed.png   (set as background)
```

`C:\Setup\FirstBoot.ps1`, `Check-Tablet.cmd`, `Fix-TabletIdentity.ps1` at the top level
are copied there by `Prep-Master.ps1`. Never by hand.

---

## Build a master (IT)

Start from a factory Axone. It arrives signed in as `user` ("AXONE NEMO PLUS").
Factory TEXA SysEye and the Sentinel runtime are expected and stay.

1. `1-Check-Factory-Software.cmd`. Must end CLEAN (no IDC5, IDC6, TeamViewer).
2. `2-Create-CEAS-User.cmd`. Sign out, sign in as **CEAS**. Everything below as CEAS.
3. Join the warehouse/guest Wi-Fi, tick **Connect automatically**.
4. Copy installers and `master-build/kit/*` into `C:\Setup` per the layout above. Set the wallpaper.
5. `3-Check-Master-Files.cmd`. Must end ALL GOOD.
6. `4-Run-Update-Master.cmd`. Restart and repeat until **CLEAN**.
7. `5-Disable-Factory-User.cmd`.
8. `6-Run-Prep-Master.cmd`. Ends **MASTER READY** and shuts down.

`7-Find-IDC5.cmd` is diagnostic only: lists every TEXA/IDC trace on the tablet.

## Capture the master

1. IMAGE stick root: `CAPTURE-MASTER.txt` (empty) + `Fix-TabletIdentity.ps1`.
   No `CEAS-Tablet-NEW.wim`.
   *Older BOOT sticks only:* also an empty file named `CEAS-Tablet.wim`.
2. BOOT + IMAGE in the master. Boot menu (Enter) → BOOT.
   Screen shows **CAPTURE MODE**. 30-60 min, then it turns off.
3. On the PC: delete `CAPTURE-MASTER.txt` (and any empty placeholder),
   rename `CEAS-Tablet-NEW.wim` → `CEAS-Tablet.wim`. Back it up.

Keep the master. Do not clone onto it or boot it into Windows.

## Clone a tablet (warehouse)

1. BOOT + IMAGE in. Boot menu (Enter) → BOOT.
2. "Installing Windows image", then a name like `CEAS-1A2B3C4D`. Write it on the label. It turns off.
3. Pull both sticks, power on (on charger). CEAS signs in, **CEAS TABLET SETUP** runs.
4. About 5 minutes later the window turns **yellow**: automatic part done.
5. Install IDC6 (Truck and OHW) the usual way, open IDC6 and enter the activation key,
   set the TeamViewer fixed password.
6. Desktop → **Check Tablet** → **Green** = ship.
   Red = set aside, send IT `C:\Setup\provision-log.txt`.

Status screen shows tablet name, TeamViewer ID and TEXA key ID.
The TEXA key ID must differ from the master's: 1870054098 in decimal (Sentinel page, localhost:1947) = 6F76C2D2 in hex (what IDC6 shows). Compare in the same format. First verified clone: 2574B943 hex. If the screen says
"check by hand", open Edge > `localhost:1947` > Sentinel Keys > Key ID.

## Failsafes in first boot

- The automatic part (identity, network, clock, TeamViewer) runs **once**. When it reaches
  yellow it marks itself done in `C:\Setup\provision-state.json` and removes its own task.
  Even if the task survived, the marker stops it from running again.
- A red result retries at the next sign-in, **at most 3 times**. After that the task is removed
  and the status screen names the manual fallback: installers are on every tablet in
  `C:\Setup\TeamViewer` and `C:\Setup\IDC6`. The warehouse installs by hand, then runs Check Tablet.
- Check Tablet (-VerifyOnly) never installs anything. A green Check Tablet also removes a leftover task.

## Refresh the master (every 1-2 months)

Boot the master into Windows, sign in as CEAS, swap in newer TEXA ISOs if any,
run `4-Run-Update-Master.cmd` until CLEAN, then `6-Run-Prep-Master.cmd`, then capture again.

---

## When a file changes

| File changed | Update |
|---|---|
| `master-build/kit/*` | `C:\Setup\kit\` on the master, then rerun `6-Run-Prep-Master.cmd` and recapture |
| `boot/*` | Rebuild `CEAS-WinPE.iso`, re-burn every BOOT stick |
| `image/Fix-TabletIdentity.ps1` | Every IMAGE stick root; also `master-build/kit/` and `field-fix/` (same file) |
| `master-build/helpers/*` | MASTER BUILD stick root |

## Known items to confirm on the first test clone

- The name IDC6 shows in Settings > Apps matches `IDC6InstalledPattern` in `FirstBoot.ps1`
  (default `IDC6|IDC 6`). If Check Tablet says IDC6 not installed after it is, fix that pattern.
- TeamViewer password check flips to set after the warehouse sets it.
