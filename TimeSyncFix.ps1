<#
.SYNOPSIS
  Fixes the wrong Windows clock after dual-booting with Linux.
  Runs silently in the background and re-syncs time at boot, logon,
  wake from sleep, and whenever a network connects.

.USAGE (run PowerShell as Administrator)
  .\TimeSyncFix.ps1 -Install            # install background task (recommended)
  .\TimeSyncFix.ps1 -Install -UseUTC    # also make Windows treat hardware clock as UTC (permanent fix)
  .\TimeSyncFix.ps1 -Uninstall          # remove the task (and leave registry as-is)
  .\TimeSyncFix.ps1 -Run                # do one sync now (this is what the task runs)
#>

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Run,
    [switch]$UseUTC
)

$TaskName = "TimeSyncFix"
$AppDir   = Join-Path $env:ProgramData "TimeSyncFix"
$LogFile  = Join-Path $AppDir "log.txt"
$Target   = Join-Path $AppDir "TimeSyncFix.ps1"

function Write-Log($msg) {
    if (-not (Test-Path $AppDir)) { New-Item -ItemType Directory -Path $AppDir -Force | Out-Null }
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $LogFile -Value $line
    # keep the log small
    if ((Get-Item $LogFile).Length -gt 200KB) {
        Get-Content $LogFile -Tail 200 | Set-Content $LogFile
    }
    Write-Host $line
}

function Assert-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Please run PowerShell as Administrator."
        exit 1
    }
}

function Sync-Time {
    try {
        Set-Service -Name w32time -StartupType Automatic -ErrorAction SilentlyContinue
        if ((Get-Service w32time).Status -ne "Running") { Start-Service w32time }

        & w32tm /config /syncfromflags:manual /manualpeerlist:"time.windows.com time.google.com pool.ntp.org" /reliable:yes /update | Out-Null

        # Network may not be up right after boot/wake: retry for ~2 minutes
        for ($i = 1; $i -le 12; $i++) {
            $out = & w32tm /resync /force 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Time synced successfully (attempt $i). Now: $(Get-Date)"
                return
            }
            Write-Log "Attempt $i failed, retrying in 10s... ($($out -join ' '))"
            Start-Sleep -Seconds 10
        }
        Write-Log "Could not sync time after all retries (no internet?)."
    } catch {
        Write-Log "Error: $($_.Exception.Message)"
    }
}

if ($Run) {
    Sync-Time
    exit 0
}

if ($Uninstall) {
    Assert-Admin
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Task removed. Files remain in $AppDir (delete manually if you like)."
    exit 0
}

if ($Install) {
    Assert-Admin

    if (-not (Test-Path $AppDir)) { New-Item -ItemType Directory -Path $AppDir -Force | Out-Null }
    Copy-Item -Path $PSCommandPath -Destination $Target -Force

    if ($UseUTC) {
        # Windows will treat the hardware clock as UTC, same as Linux. Fixes the root cause.
        $key = "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation"
        New-ItemProperty -Path $key -Name "RealTimeIsUniversal" -Value 1 -PropertyType DWord -Force | Out-Null
        Write-Host "Set RealTimeIsUniversal=1 (Windows now reads the hardware clock as UTC)."
    }

    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Target`" -Run"

    # Triggers: boot, logon, resume from sleep/hibernate, network connected
    $tBoot  = New-ScheduledTaskTrigger -AtStartup
    $tLogon = New-ScheduledTaskTrigger -AtLogOn

    $evClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $tResume = New-CimInstance -CimClass $evClass -ClientOnly
    $tResume.Enabled = $true
    $tResume.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name=''Microsoft-Windows-Power-Troubleshooter''] and EventID=1]]</Select></Query></QueryList>'

    $tNet = New-CimInstance -CimClass $evClass -ClientOnly
    $tNet.Enabled = $true
    $tNet.Subscription = '<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[EventID=10000]]</Select></Query></QueryList>'

    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -Hidden

    Register-ScheduledTask -TaskName $TaskName -Action $action `
        -Trigger @($tBoot, $tLogon, $tResume, $tNet) `
        -Principal $principal -Settings $settings -Force | Out-Null

    Write-Host "Installed. The task '$TaskName' runs silently at boot, logon, wake and network connect."
    Write-Host "Log file: $LogFile"
    Write-Host "Running a first sync now..."
    Sync-Time
    exit 0
}

Get-Help $PSCommandPath -Detailed | Out-String | Write-Host
