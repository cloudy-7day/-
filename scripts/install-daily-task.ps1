param(
  [string]$TaskName = "PersonalInfoLibraryDaily",
  [string]$At = "08:00"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $PSScriptRoot "update-daily.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries
$userId = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Daily update for Personal Info Library at Los Angeles time 08:00" -Force
Write-Host "Installed daily task: $TaskName at $At."
