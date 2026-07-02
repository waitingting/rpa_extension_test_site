param(
  [string]$InterfaceAlias = "",
  [string]$IPAddress = "192.168.150.129",
  [int]$PrefixLength = 24,
  [string]$DefaultGateway = "",
  [string[]]$DnsServers = @()
)

$ErrorActionPreference = "Stop"

if (-not $InterfaceAlias) {
  $adapter = Get-NetAdapter |
    Where-Object { $_.Status -eq "Up" } |
    Sort-Object InterfaceMetric |
    Select-Object -First 1
  if (-not $adapter) {
    throw "No active network adapter found."
  }
  $InterfaceAlias = $adapter.Name
}

$ipConfig = Get-NetIPConfiguration -InterfaceAlias $InterfaceAlias
if (-not $DefaultGateway) {
  $DefaultGateway = $ipConfig.IPv4DefaultGateway.NextHop
}
if (-not $DnsServers -or $DnsServers.Count -eq 0) {
  $DnsServers = (Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4).ServerAddresses
}
if (-not $DefaultGateway) {
  throw "Default gateway was not detected. Pass -DefaultGateway explicitly."
}
if (-not $DnsServers -or $DnsServers.Count -eq 0) {
  throw "DNS servers were not detected. Pass -DnsServers explicitly."
}

Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -ne "127.0.0.1" } |
  Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress `
  -InterfaceAlias $InterfaceAlias `
  -IPAddress $IPAddress `
  -PrefixLength $PrefixLength `
  -DefaultGateway $DefaultGateway | Out-Null

Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DnsServers

[pscustomobject]@{
  InterfaceAlias = $InterfaceAlias
  IPAddress = $IPAddress
  PrefixLength = $PrefixLength
  DefaultGateway = $DefaultGateway
  DnsServers = $DnsServers -join ","
}
