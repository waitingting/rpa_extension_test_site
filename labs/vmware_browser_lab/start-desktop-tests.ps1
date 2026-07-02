param(
  [string]$ComputerName = "192.168.150.129",
  [string]$UserName = "wpwor",
  [string]$Password = "",
  [string]$RemoteStage = "C:\rpad-vmware-browser-lab",
  [string]$LabRoot = "C:\browser-e2e",
  [string]$TestSiteRepo = "C:\workspace\rpa_extension_test_site",
  [string]$RpadRepo = "C:\workspace\rpad",
  [string]$ExtensionRepo = "C:\workspace\web_extension_unified",
  [string]$ExtensionBuild = "C:\workspace\web_extension_unified\build-mv3",
  [string]$ExtensionId = "agccmolgecegkikobaiomldmkdaahkkm",
  [string]$ChromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe",
  [string]$Qihu360Path = "C:\Users\wpwor\AppData\Roaming\360se6\Application\360se.exe",
  [switch]$Include360Smoke,
  [switch]$SkipBrowserSmoke,
  [switch]$SkipExtensionSmoke,
  [switch]$SkipProviderUnit,
  [switch]$SkipBrowserManagerUnit,
  [switch]$SkipBrowserManagerInstall,
  [switch]$SkipProviderAutoCapture,
  [switch]$RunProviderInteractive
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

$session = New-PSSession -ComputerName $ComputerName -Credential $credential -Authentication Negotiate
try {
  Invoke-Command -Session $session -ScriptBlock {
    param($RemoteStage)
    New-Item -ItemType Directory -Force -Path $RemoteStage | Out-Null
  } -ArgumentList $RemoteStage

  Copy-Item -ToSession $session -Force `
    -Path (Join-Path $PSScriptRoot "run-desktop-tests.ps1") `
    -Destination (Join-Path $RemoteStage "run-desktop-tests.ps1")

  $taskResult = Invoke-Command -Session $session -ScriptBlock {
    param(
      $RemoteStage,
      $LabRoot,
      $TestSiteRepo,
      $RpadRepo,
      $ExtensionRepo,
      $ExtensionBuild,
      $ExtensionId,
      $ChromePath,
      $Qihu360Path,
      $Include360Smoke,
      $SkipBrowserSmoke,
      $SkipExtensionSmoke,
      $SkipProviderUnit,
      $SkipBrowserManagerUnit,
      $SkipBrowserManagerInstall,
      $SkipProviderAutoCapture,
      $RunProviderInteractive
    )

    $scriptPath = Join-Path $RemoteStage "run-desktop-tests.ps1"
    $args = @(
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", "`"$scriptPath`"",
      "-LabRoot", "`"$LabRoot`"",
      "-TestSiteRepo", "`"$TestSiteRepo`"",
      "-RpadRepo", "`"$RpadRepo`"",
      "-ExtensionRepo", "`"$ExtensionRepo`"",
      "-ExtensionBuild", "`"$ExtensionBuild`"",
      "-ExtensionId", "`"$ExtensionId`"",
      "-ChromePath", "`"$ChromePath`"",
      "-Qihu360Path", "`"$Qihu360Path`""
    )
    if ($Include360Smoke) { $args += "-Include360Smoke" }
    if ($SkipBrowserSmoke) { $args += "-SkipBrowserSmoke" }
    if ($SkipExtensionSmoke) { $args += "-SkipExtensionSmoke" }
    if ($SkipProviderUnit) { $args += "-SkipProviderUnit" }
    if ($SkipBrowserManagerUnit) { $args += "-SkipBrowserManagerUnit" }
    if ($SkipBrowserManagerInstall) { $args += "-SkipBrowserManagerInstall" }
    if ($SkipProviderAutoCapture) { $args += "-SkipProviderAutoCapture" }
    if ($RunProviderInteractive) { $args += "-RunProviderInteractive" }

    $taskName = "RpadBrowserDesktopTests"
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ($args -join " ")
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddDays(1)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal
    Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 2
    Get-ScheduledTask -TaskName $taskName | Get-ScheduledTaskInfo |
      Select-Object TaskName, LastRunTime, LastTaskResult, NextRunTime
  } -ArgumentList $RemoteStage, $LabRoot, $TestSiteRepo, $RpadRepo, $ExtensionRepo, $ExtensionBuild, $ExtensionId, $ChromePath, $Qihu360Path, $Include360Smoke, $SkipBrowserSmoke, $SkipExtensionSmoke, $SkipProviderUnit, $SkipBrowserManagerUnit, $SkipBrowserManagerInstall, $SkipProviderAutoCapture, $RunProviderInteractive

  $taskResult
  Write-Host "Desktop task started. Watch logs in $LabRoot\logs inside the VM."
} finally {
  if ($session) {
    Remove-PSSession $session
  }
}
