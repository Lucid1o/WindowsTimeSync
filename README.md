# WindowsTimeSync

Fix the wrong Windows clock after dual-booting with Linux. A tiny PowerShell script that installs a silent background task to re-sync your time automatically.

## The problem

When you dual boot Windows and Linux, the clock is often off by a few hours after switching OS (for example, 5 hours 30 minutes in India).

- **Linux** stores the hardware clock (RTC) in **UTC**.
- **Windows** stores the hardware clock in **local time**.

Each OS "corrects" the clock using its own assumption, so the other one shows the wrong time.

## What this does

`TimeSyncFix.ps1` installs a Windows Scheduled Task that runs hidden as SYSTEM and re-syncs the clock via Windows Time (`w32tm`) when:

- the PC boots
- a user logs on
- the PC wakes from sleep or hibernate
- a network connects

It retries for about 2 minutes, since the network is often not ready right after boot. Results are logged to `C:\ProgramData\TimeSyncFix\log.txt`.

Optionally, it can also apply the permanent fix by telling Windows to treat the hardware clock as UTC, like Linux does.

## Requirements

- Windows 10 or 11
- PowerShell 5.1+ (built in)
- Administrator rights
- Internet access (for syncing)

## Install

Open PowerShell **as Administrator** in the folder containing the script:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\TimeSyncFix.ps1 -Install
```

To also apply the permanent fix (recommended):

```powershell
.\TimeSyncFix.ps1 -Install -UseUTC
```

You only need to do this once. After that it runs by itself.

## Usage

| Command | What it does |
|---|---|
| `.\TimeSyncFix.ps1 -Install` | Installs the background task and runs a first sync |
| `.\TimeSyncFix.ps1 -Install -UseUTC` | Same, and sets `RealTimeIsUniversal=1` in the registry |
| `.\TimeSyncFix.ps1 -Run` | Runs one sync right now |
| `.\TimeSyncFix.ps1 -Uninstall` | Removes the scheduled task |

## Verify it works

- Check `C:\ProgramData\TimeSyncFix\log.txt` after a reboot for a "Time synced successfully" line.
- Or open **Task Scheduler** and look for a task named **TimeSyncFix**.

## About `-UseUTC`

This sets `HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation\RealTimeIsUniversal = 1`, so Windows and Linux agree on how to read the hardware clock and the offset never appears. The sync task then acts as a safety net.

Alternative (Linux side instead): `sudo timedatectl set-local-rtc 1`

Use one of the two fixes, not both.

## Uninstall

```powershell
.\TimeSyncFix.ps1 -Uninstall
```

To undo the UTC change, delete the `RealTimeIsUniversal` value from the registry key above, or set it to `0`.

## License

MIT
