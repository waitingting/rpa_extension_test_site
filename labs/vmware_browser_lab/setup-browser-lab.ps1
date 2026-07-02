param(
  [string]$TestSiteRepo = "C:\workspace\rpa_extension_test_site",
  [string]$RpadRepo = "C:\workspace\rpad",
  [string]$ExtensionRepo = "C:\workspace\web_extension_unified",
  [string]$Install360Path = "",
  [string]$LabRoot = "C:\browser-e2e",
  [string]$TestSource = ""
)

$ErrorActionPreference = "Stop"

function Install-Exe {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string[]]$Args
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Installer not found: $Path"
  }

  $process = Start-Process -FilePath $Path -ArgumentList $Args -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "Installer failed: $Path exit=$($process.ExitCode)"
  }
}

function Enable-Rdp {
  Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
  $rules = Get-NetFirewallRule -Name "RemoteDesktop-*" -ErrorAction SilentlyContinue
  if ($rules) {
    $rules | Enable-NetFirewallRule | Out-Null
    return
  }
  foreach ($group in @("Remote Desktop", "远程桌面")) {
    $rules = Get-NetFirewallRule -DisplayGroup $group -ErrorAction SilentlyContinue
    if ($rules) {
      $rules | Enable-NetFirewallRule | Out-Null
      return
    }
  }
  Write-Warning "Remote Desktop firewall rules were not found by name or display group."
}

function Install-Chrome {
  $installer = Join-Path $env:TEMP "chrome_installer.exe"
  Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $installer
  Install-Exe -Path $installer -Args @("/silent", "/install")
}

function Install-Firefox {
  $installer = Join-Path $env:TEMP "firefox_installer.exe"
  Invoke-WebRequest "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US" -OutFile $installer
  Install-Exe -Path $installer -Args @("/S")
}

function Install-Node {
  $msi = Join-Path $env:TEMP "node-v20.15.1-x64.msi"
  Invoke-WebRequest "https://nodejs.org/dist/v20.15.1/node-v20.15.1-x64.msi" -OutFile $msi
  $process = Start-Process msiexec.exe -ArgumentList @("/i", $msi, "/qn", "/norestart") -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "Node installer failed: exit=$($process.ExitCode)"
  }
}

function Refresh-Path {
  $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
  $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = "$machine;$user"
}

function Prepare-Automation {
  New-Item -ItemType Directory -Force -Path $LabRoot | Out-Null

  $testSource = if ($TestSource) { $TestSource } else { Join-Path $TestSiteRepo "tests\browser_e2e" }
  if (-not (Test-Path -LiteralPath $testSource)) {
    throw "Browser E2E tests not found: $testSource"
  }

  Copy-Item -LiteralPath (Join-Path $testSource "package.json") -Destination (Join-Path $LabRoot "package.json") -Force
  Copy-Item -LiteralPath (Join-Path $testSource "browser-smoke.spec.js") -Destination (Join-Path $LabRoot "browser-smoke.spec.js") -Force
  Copy-Item -LiteralPath (Join-Path $testSource "fixture-site.spec.js") -Destination (Join-Path $LabRoot "fixture-site.spec.js") -Force
  Copy-Item -LiteralPath (Join-Path $testSource "rpad-extension-smoke.spec.js") -Destination (Join-Path $LabRoot "rpad-extension-smoke.spec.js") -Force

  Push-Location $LabRoot
  npm install
  npx playwright install chromium
  npx playwright install firefox
  Pop-Location
}

Write-Host "Enabling RDP..."
Enable-Rdp

Write-Host "Installing Chrome..."
Install-Chrome

Write-Host "Installing Firefox..."
Install-Firefox

if ($Install360Path -and (Test-Path -LiteralPath $Install360Path)) {
  Write-Host "Installing 360 browser from $Install360Path..."
  Start-Process -FilePath $Install360Path -ArgumentList @("/S") -Wait
} else {
  Write-Host "360 browser installer not provided. Skipping."
}

Write-Host "Installing Node.js..."
Install-Node
Refresh-Path

Write-Host "Preparing automation tests..."
Prepare-Automation

Write-Host "Browser lab ready."
Write-Host "Test site repo: $TestSiteRepo"
Write-Host "Rpad repo: $RpadRepo"
Write-Host "Extension repo: $ExtensionRepo"
Write-Host "Lab root: $LabRoot"
