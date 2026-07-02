param(
  [string]$ComputerName = "192.168.150.129",
  [string]$UserName = "wpwor",
  [string]$Password = "",
  [string]$Install360Path = "",
  [string]$RemoteStage = "C:\rpad-vmware-browser-lab",
  [string]$LabRoot = "C:\browser-e2e",
  [string]$TestSiteRepo = "C:\workspace\rpa_extension_test_site",
  [string]$RpadRepo = "C:\workspace\rpad",
  [string]$ExtensionRepo = "C:\workspace\web_extension_unified",
  [switch]$SkipTrustedHosts,
  [switch]$SkipSsh
)

$ErrorActionPreference = "Stop"

if (-not $Password) {
  $credential = Get-Credential -UserName $UserName -Message "VM Windows credential"
} else {
  if ($UserName -notmatch '[\\@]') {
    $UserName = "$ComputerName\$UserName"
  }
  $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
  $credential = [pscredential]::new($UserName, $securePassword)
}

if (-not $SkipTrustedHosts) {
  try {
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value $ComputerName -Force
  } catch {
    Write-Warning "Could not update TrustedHosts. Retrying without changing it. Run this script from an elevated PowerShell if New-PSSession fails."
  }
}

$session = New-PSSession -ComputerName $ComputerName -Credential $credential -Authentication Negotiate
try {
  Invoke-Command -Session $session -ScriptBlock {
    param($RemoteStage)
    New-Item -ItemType Directory -Force -Path $RemoteStage | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $RemoteStage "tests\browser_e2e") | Out-Null
  } -ArgumentList $RemoteStage

  Copy-Item -ToSession $session -Force `
    -Path (Join-Path $PSScriptRoot "*.ps1") `
    -Destination $RemoteStage

  Copy-Item -ToSession $session -Recurse -Force `
    -Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "tests\browser_e2e\*") `
    -Destination (Join-Path $RemoteStage "tests\browser_e2e")

  Invoke-Command -Session $session -ScriptBlock {
    param($RemoteStage, $TestSiteRepo, $RpadRepo, $ExtensionRepo, $Install360Path, $LabRoot)
    Set-ExecutionPolicy Bypass -Scope Process -Force
    & (Join-Path $RemoteStage "setup-browser-lab.ps1") `
      -TestSiteRepo $TestSiteRepo `
      -RpadRepo $RpadRepo `
      -ExtensionRepo $ExtensionRepo `
      -Install360Path $Install360Path `
      -LabRoot $LabRoot `
      -TestSource (Join-Path $RemoteStage "tests\browser_e2e")
  } -ArgumentList $RemoteStage, $TestSiteRepo, $RpadRepo, $ExtensionRepo, $Install360Path, $LabRoot

  if (-not $SkipSsh) {
    Invoke-Command -Session $session -ScriptBlock {
      param($RemoteStage)
      Set-ExecutionPolicy Bypass -Scope Process -Force
      & (Join-Path $RemoteStage "enable-ssh.ps1")
    } -ArgumentList $RemoteStage
  }
} finally {
  if ($session) {
    Remove-PSSession $session
  }
}
