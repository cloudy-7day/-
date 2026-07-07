param(
  [string]$TaskName = "PersonalInfoLibraryWebServer"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $PSScriptRoot "start-web-server.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries
$userId = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Start Personal Info Library web server after user logon" -Force
Write-Host "Installed web server task: $TaskName."
