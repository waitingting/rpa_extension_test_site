$ErrorActionPreference = "Stop"

$capability = Get-WindowsCapability -Online | Where-Object Name -like "OpenSSH.Server*"
if ($capability.State -ne "Installed") {
  Add-WindowsCapability -Online -Name $capability.Name
}

Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule `
    -Name "OpenSSH-Server-In-TCP" `
    -DisplayName "OpenSSH Server (sshd)" `
    -Enabled True `
    -Direction Inbound `
    -Protocol TCP `
    -Action Allow `
    -LocalPort 22 | Out-Null
} else {
  Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" | Out-Null
}

Write-Host "OpenSSH Server enabled on port 22"
