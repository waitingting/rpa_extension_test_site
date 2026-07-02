param(
  [string]$LabRoot = "C:\browser-e2e",
  [string]$TestSiteRepo = "C:\workspace\rpa_extension_test_site",
  [string]$RpadRepo = "C:\workspace\rpad",
  [string]$ExtensionRepo = "C:\workspace\web_extension_unified",
  [string]$ExtensionBuild = "C:\workspace\web_extension_unified\build-mv3",
  [string]$ExtensionId = "agccmolgecegkikobaiomldmkdaahkkm",
  [string]$ChromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe",
  [string]$Qihu360Path = "C:\Users\wpwor\AppData\Roaming\360se6\Application\360se.exe",
  [string]$ProviderFilter = "",
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

function Quote-Argument {
  param([Parameter(Mandatory = $true)][string]$Value)

  if ($Value -notmatch '[\s"]') {
    return $Value
  }
  return '"' + ($Value -replace '"', '\"') + '"'
}

function Invoke-TestCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$ArgumentLine = "",
    [string]$WorkingDirectory = "",
    [int]$TimeoutSeconds = 0
  )

  Write-Host "==> $Name"

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $FilePath
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  if ($WorkingDirectory) {
    $startInfo.WorkingDirectory = $WorkingDirectory
  }
  if ($ArgumentLine) {
    $startInfo.Arguments = $ArgumentLine
  } else {
    $startInfo.Arguments = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join " "
  }

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  if ($TimeoutSeconds -gt 0) {
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      try {
        $process.Kill()
      } catch {
      }
      $process.WaitForExit()
      $stdout = $stdoutTask.Result
      $stderr = $stderrTask.Result
      if ($stdout) {
        Write-Host $stdout
      }
      if ($stderr) {
        Write-Host $stderr
      }
      throw "$Name timed out after ${TimeoutSeconds}s"
    }
  } else {
    $process.WaitForExit()
  }
  $stdout = $stdoutTask.Result
  $stderr = $stderrTask.Result

  if ($stdout) {
    Write-Host $stdout
  }
  if ($stderr) {
    Write-Host $stderr
  }
  if ($process.ExitCode -ne 0) {
    throw "$Name failed: exit=$($process.ExitCode)"
  }

  return $stdout
}

function Invoke-Playwright {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [int]$TimeoutSeconds = 120
  )

  $playwright = Join-Path $LabRoot "node_modules\.bin\playwright.cmd"
  if (-not (Test-Path -LiteralPath $playwright)) {
    throw "Playwright command not found: $playwright"
  }

  $commandLine = '""' + $playwright + '" ' + (($Arguments | ForEach-Object { Quote-Argument $_ }) -join " ") + '"'

  Invoke-TestCommand `
    -Name "Playwright $($Arguments -join ' ')" `
    -FilePath "cmd.exe" `
    -ArgumentLine "/d /s /c $commandLine" `
    -WorkingDirectory $LabRoot `
    -TimeoutSeconds $TimeoutSeconds
}

function Stop-FixtureSiteProcesses {
  $escapedRepo = [regex]::Escape($TestSiteRepo)
  Get-CimInstance Win32_Process -Filter "name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -match "http-server" -and
      $_.CommandLine -match $escapedRepo -and
      $_.CommandLine -match "extension-fixtures"
    } |
    ForEach-Object {
      Write-Host "Stopping stale fixture server pid=$($_.ProcessId)"
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Start-FixtureSite {
  $startScript = Join-Path $TestSiteRepo "scripts\start.ps1"
  if (-not (Test-Path -LiteralPath $startScript)) {
    throw "Fixture site start script not found: $startScript"
  }

  Write-Host "==> start fixture site"
  Stop-FixtureSiteProcesses

  $process = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $startScript) `
    -WorkingDirectory $TestSiteRepo `
    -PassThru `
    -WindowStyle Hidden

  $deadline = (Get-Date).AddSeconds(90)
  do {
    try {
      $response = Invoke-WebRequest -Uri "http://127.0.0.1:8007/" -UseBasicParsing -TimeoutSec 5 -Proxy $null
      if ($response.StatusCode -eq 200) {
        Write-Host "Fixture site is ready: http://127.0.0.1:8007/"
        return $process
      }
    } catch {
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  try {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  } catch {
  }
  throw "Fixture site did not become ready at http://127.0.0.1:8007/."
}

function Stop-FixtureSite {
  param($Process)

  if ($Process -and -not $Process.HasExited) {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
  }
  Stop-FixtureSiteProcesses
}

function Invoke-CapturedCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory = ""
  )

  Write-Host "==> $Name"

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $FilePath
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  if ($WorkingDirectory) {
    $startInfo.WorkingDirectory = $WorkingDirectory
  }
  $startInfo.Arguments = ($Arguments | ForEach-Object { Quote-Argument $_ }) -join " "

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()

  if ($stdout) {
    Write-Host $stdout
  }
  if ($stderr) {
    Write-Host $stderr
  }
  if ($process.ExitCode -ne 0) {
    throw "$Name failed: exit=$($process.ExitCode)"
  }

  return $stdout
}

function Stop-ProviderAutoCaptureProcesses {
  $names = @(
    "chrome",
    "chrome_test",
    "com.datagrand.browser_extension.native_app",
    "com.datagrand.browser_extension.native_app.mv3"
  )
  foreach ($name in $names) {
    Get-Process -Name $name -ErrorAction SilentlyContinue |
      Stop-Process -Force -ErrorAction SilentlyContinue
  }
}

$script:ResolvedExtensionId = ""

function Resolve-ExtensionId {
  if ($script:ResolvedExtensionId) {
    return $script:ResolvedExtensionId
  }

  if (-not (Test-Path -LiteralPath $ExtensionBuild)) {
    throw "Extension build not found: $ExtensionBuild"
  }

  $extensionId = $ExtensionId
  if (-not $extensionId) {
    $extensionId = Get-UnpackedExtensionId -ExtensionPath $ExtensionBuild
  }
  if ($extensionId -notmatch '^[a-p]{32}$') {
    throw "Invalid extension id: $extensionId"
  }

  $script:ResolvedExtensionId = $extensionId
  Write-Host "Unpacked extension id: $extensionId"
  return $script:ResolvedExtensionId
}

function Stop-Qihu360Processes {
  foreach ($name in @("360se", "360chrome")) {
    Get-Process -Name $name -ErrorAction SilentlyContinue |
      Stop-Process -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-Qihu360NativeSmoke {
  param(
    [Parameter(Mandatory = $true)][string]$BrowserPath
  )

  if (-not (Test-Path -LiteralPath $BrowserPath)) {
    throw "360 browser not found: $BrowserPath"
  }

  Write-Host "==> 360 native input smoke"

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class RpadBrowserLabNativeInput {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int x, int y);

  [DllImport("user32.dll")]
  public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll")]
  public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);

  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@

  $payload = "rpad browser lab"
  $okTitle = "RPAD_360_OK"
  $fixture = Join-Path $env:TEMP ("rpad-360-native-smoke-" + [guid]::NewGuid().ToString("N") + ".html")
  $html = @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>RPAD_360_READY</title>
  <style>
    body { margin: 0; min-height: 100vh; padding: 40px; font-family: sans-serif; font-size: 30px; }
    #status { margin-top: 40px; }
    #payload {
      display: block;
      margin-top: 40px;
      width: min(760px, calc(100vw - 120px));
      height: 96px;
      font-size: 36px;
    }
  </style>
</head>
<body tabindex="0">
  <div id="status">Ready</div>
  <input id="payload" autofocus autocomplete="off" spellcheck="false" />
  <script>
    var expected = '$payload';
    var input = document.getElementById('payload');
    var status = document.getElementById('status');
    function check() {
      var typed = input.value;
      status.textContent = typed || 'Ready';
      if (typed === expected) {
        document.title = '$okTitle';
      }
    }
    function focusInput() {
      input.focus();
      input.select();
    }
    document.addEventListener('click', focusInput);
    input.addEventListener('input', check);
    input.addEventListener('keydown', function(event) {
      if (event.key === 'Enter') {
        check();
      }
    });
    window.addEventListener('load', focusInput);
  </script>
</body>
</html>
"@
  Set-Content -LiteralPath $fixture -Value $html -Encoding UTF8
  $url = "file:///" + ($fixture -replace "\\", "/")
  $findWindowByTitle = {
    param([string]$TitlePart)

    $result = [IntPtr]::Zero
    $callback = [RpadBrowserLabNativeInput+EnumWindowsProc]{
      param([IntPtr]$hwnd, [IntPtr]$lparam)

      if ([RpadBrowserLabNativeInput]::IsWindowVisible($hwnd)) {
        $builder = [System.Text.StringBuilder]::new(512)
        [void][RpadBrowserLabNativeInput]::GetWindowText($hwnd, $builder, $builder.Capacity)
        if ($builder.ToString() -like "*$TitlePart*") {
          $script:__rpad360Window = $hwnd
          return $false
        }
      }
      return $true
    }

    $script:__rpad360Window = [IntPtr]::Zero
    [void][RpadBrowserLabNativeInput]::EnumWindows($callback, [IntPtr]::Zero)
    $result = $script:__rpad360Window
    Remove-Variable -Scope Script -Name __rpad360Window -ErrorAction SilentlyContinue
    return $result
  }

  Stop-Qihu360Processes
  try {
    [void](Start-Process -FilePath $BrowserPath -ArgumentList @("--force-renderer-accessibility=complete", "--new-window", $url) -PassThru)
    $deadline = (Get-Date).AddSeconds(30)
    $browserProcess = $null
    do {
      $browserProcess = Get-Process -Name 360se,360chrome -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Sort-Object StartTime -Descending |
        Select-Object -First 1
      if ($browserProcess) { break }
      Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    if (-not $browserProcess) {
      throw "360 browser window was not created."
    }

    $handle = $browserProcess.MainWindowHandle
    [void][RpadBrowserLabNativeInput]::ShowWindow($handle, 3)
    Start-Sleep -Milliseconds 1500
    [void][RpadBrowserLabNativeInput]::SetForegroundWindow($handle)
    Start-Sleep -Milliseconds 500

    [System.Windows.Forms.SendKeys]::SendWait("^l")
    [System.Windows.Forms.SendKeys]::SendWait($url)
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Seconds 3
    $titleHandle = & $findWindowByTitle "RPAD_360_READY"
    if ($titleHandle -ne [IntPtr]::Zero) {
      $handle = $titleHandle
      Write-Host "360 browser window found by title."
    }
    $shell = New-Object -ComObject WScript.Shell
    [void][RpadBrowserLabNativeInput]::ShowWindow($handle, 3)
    [void][RpadBrowserLabNativeInput]::SetForegroundWindow($handle)
    $activated = $shell.AppActivate("RPAD_360_READY")
    Write-Host "360 browser AppActivate result: $activated"
    Start-Sleep -Milliseconds 800

    $rect = New-Object RpadBrowserLabNativeInput+RECT
    if (-not [RpadBrowserLabNativeInput]::GetWindowRect($handle, [ref]$rect)) {
      $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
      $rect.Left = $screen.Left
      $rect.Top = $screen.Top
      $rect.Right = $screen.Right
      $rect.Bottom = $screen.Bottom
      Write-Host "360 window rect unavailable; using primary screen bounds."
    }
    Write-Host "360 window rect: $($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)"

    [System.Windows.Forms.Clipboard]::SetText($payload)
    $clickOffsets = @(
      @{ X = 180; Y = 220 },
      @{ X = 260; Y = 260 },
      @{ X = 360; Y = 300 },
      @{ X = 480; Y = 340 },
      @{ X = 620; Y = 380 }
    )
    $attempt = 0
    foreach ($offset in $clickOffsets) {
      ++$attempt
      Write-Host "360 native input attempt $attempt"
      [void][RpadBrowserLabNativeInput]::ShowWindow($handle, 3)
      [void][RpadBrowserLabNativeInput]::SetForegroundWindow($handle)
      [void]$shell.AppActivate("RPAD_360_READY")
      Start-Sleep -Milliseconds 500
      $pageX = [Math]::Min([Math]::Max($rect.Left + $offset.X, $rect.Left + 20), $rect.Right - 20)
      $pageY = [Math]::Min([Math]::Max($rect.Top + $offset.Y, $rect.Top + 20), $rect.Bottom - 20)
      Write-Host "360 native input click: $pageX,$pageY"
      [void][RpadBrowserLabNativeInput]::SetCursorPos($pageX, $pageY)
      [RpadBrowserLabNativeInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
      [RpadBrowserLabNativeInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
      Start-Sleep -Milliseconds 300
      [System.Windows.Forms.SendKeys]::SendWait("^a")
      [System.Windows.Forms.SendKeys]::SendWait("^v")
      [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

      $deadline = (Get-Date).AddSeconds(8)
      do {
        Start-Sleep -Milliseconds 300
        $successHandle = & $findWindowByTitle $okTitle
        if ($successHandle -ne [IntPtr]::Zero) {
          Write-Host "360 native input smoke passed: $okTitle"
          return
        }
      } while ((Get-Date) -lt $deadline)
    }

    $readyHandle = & $findWindowByTitle "RPAD_360_READY"
    $lastTitle = if ($readyHandle -ne [IntPtr]::Zero) { "RPAD_360_READY" } else { $browserProcess.MainWindowTitle }
    throw "360 native input smoke did not observe success title. Last title: $lastTitle"
  } finally {
    Stop-Qihu360Processes
    Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue
  }
}

function Copy-ItemWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [int]$Retries = 5
  )

  for ($attempt = 1; $attempt -le $Retries; ++$attempt) {
    try {
      Copy-Item -LiteralPath $Source -Destination $Destination -Force
      return
    } catch {
      if ($attempt -eq $Retries) {
        throw
      }
      Stop-ProviderAutoCaptureProcesses
      Start-Sleep -Milliseconds (300 * $attempt)
    }
  }
}

function Get-UnpackedExtensionId {
  param(
    [Parameter(Mandatory = $true)][string]$ExtensionPath,
    [string]$BrowserPath = ""
  )

  $scriptPath = Join-Path $LabRoot "get-extension-id.js"
  $profilePath = Join-Path $env:TEMP ("rpad-extension-id-" + [guid]::NewGuid().ToString("N"))
  $script = @'
const { chromium } = require('@playwright/test');

const extensionPath = process.argv[2];
const userDataDir = process.argv[3];
const executablePath = process.argv[4] || undefined;

(async () => {
  const context = await chromium.launchPersistentContext(userDataDir, {
    headless: false,
    executablePath,
    args: [
      `--disable-extensions-except=${extensionPath}`,
      `--load-extension=${extensionPath}`,
      '--force-renderer-accessibility=complete'
    ]
  });
  try {
    let [background] = context.serviceWorkers();
    if (!background) {
      background = await context.waitForEvent('serviceworker', { timeout: 30000 });
    }
    const id = background.url().split('/')[2];
    if (!id) {
      throw new Error(`Cannot parse extension id from ${background.url()}`);
    }
    console.log(id);
  } finally {
    await context.close();
  }
})().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
'@
  Set-Content -LiteralPath $scriptPath -Value $script -Encoding UTF8

  try {
    $args = @($scriptPath, $ExtensionPath, $profilePath)
    if ($BrowserPath -and (Test-Path -LiteralPath $BrowserPath)) {
      $args += $BrowserPath
    }
    $stdout = Invoke-TestCommand -Name "resolve unpacked extension id" -FilePath "node.exe" -Arguments $args -WorkingDirectory $LabRoot -TimeoutSeconds 45
    $id = (($stdout -split "\r?\n") | Where-Object { $_ -match '^[a-p]{32}$' } | Select-Object -Last 1)
    if (-not $id) {
      throw "Unable to resolve unpacked extension id from command output."
    }
    return $id
  } finally {
    Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Initialize-ProviderAutoCaptureNativeHost {
  if (-not (Test-Path -LiteralPath $ExtensionBuild)) {
    throw "Extension build not found: $ExtensionBuild"
  }

  $extensionId = Resolve-ExtensionId

  $nativeHostName = "com.datagrand.browser_extension.native_app.mv3"
  $sourceNativeExe = Join-Path $RpadRepo "build\out\support\browser_extension\com.datagrand.browser_extension.native_app.exe"
  if (-not (Test-Path -LiteralPath $sourceNativeExe)) {
    throw "Native host executable not found: $sourceNativeExe"
  }

  $nativeDir = Join-Path $env:USERPROFILE ".datagrand\rpad\browser_extension\chrome_mv3"
  New-Item -ItemType Directory -Force -Path $nativeDir | Out-Null
  $nativeExe = Join-Path $nativeDir "$nativeHostName.exe"
  Stop-ProviderAutoCaptureProcesses
  Copy-ItemWithRetry -Source $sourceNativeExe -Destination $nativeExe
  $logConfig = @'
<seelog>
  <outputs formatid="main">
    <file path="native_application.log" />
  </outputs>
  <formats>
    <format id="main" format="%Date(2006-01-02 15:04:05.999) [%LEV] [%File:%Line] [%Func] %Msg%n" />
  </formats>
</seelog>
'@
  Set-Content -LiteralPath (Join-Path $nativeDir "log.xml") -Value $logConfig -Encoding UTF8
  $manifestPath = Join-Path $nativeDir "$nativeHostName.json"
  $manifest = [ordered]@{
    name = $nativeHostName
    description = "Add-on for enabling web automation."
    path = $nativeExe
    type = "stdio"
    allowed_origins = @("chrome-extension://$extensionId/")
  } | ConvertTo-Json -Depth 4
  Set-Content -LiteralPath $manifestPath -Value $manifest -Encoding UTF8

  $registryRoots = @(
    "HKCU\Software\Google\Chrome\NativeMessagingHosts",
    "HKCU\Software\Chromium\NativeMessagingHosts"
  )
  foreach ($root in $registryRoots) {
    & reg.exe add $root /v $nativeHostName /t REG_SZ /d $manifestPath /f | Out-Null
    & reg.exe add "$root\$nativeHostName" /ve /t REG_SZ /d $manifestPath /f | Out-Null
  }
  Write-Host "Native messaging host: $manifestPath"
  $registryRoot = "HKCU:\Software\Google\Chrome\NativeMessagingHosts"
  Write-Host "Native messaging registry value: $((Get-ItemProperty -Path $registryRoot -Name $nativeHostName).$nativeHostName)"
}

function Invoke-BrowserManagerInstallVerification {
  param(
    [Parameter(Mandatory = $true)][string]$BrowserPath
  )

  if (-not (Test-Path -LiteralPath $BrowserPath)) {
    throw "Chrome browser not found for browser_manager install verification: $BrowserPath"
  }

  $managerExe = Join-Path $RpadRepo "build\out\support\browser_extension\browser_manager.exe"
  if (-not (Test-Path -LiteralPath $managerExe)) {
    throw "browser_manager.exe not found: $managerExe"
  }

  $supportDir = Split-Path -Parent $managerExe
  $extensionId = Resolve-ExtensionId
  $nativeHostName = "com.datagrand.browser_extension.native_app.mv3"
  $nativeDir = Join-Path $env:USERPROFILE ".datagrand\rpad\browser_extension\chrome_mv3"
  $nativeExe = Join-Path $nativeDir "$nativeHostName.exe"
  $manifestPath = Join-Path $nativeDir "$nativeHostName.json"

  Stop-ProviderAutoCaptureProcesses
  Invoke-TestCommand `
    -Name "browser_manager install chrome manual mv3" `
    -FilePath $managerExe `
    -Arguments @(
      "--install=chrome",
      "--mode=manual",
      "--manifest_version=3",
      "--id=$extensionId",
      "--path=$BrowserPath",
      "--home=$env:USERPROFILE"
    ) `
    -WorkingDirectory $supportDir `
    -TimeoutSeconds 45

  Start-Sleep -Seconds 2
  Stop-ProviderAutoCaptureProcesses

  if (-not (Test-Path -LiteralPath $nativeExe)) {
    throw "browser_manager did not install native host exe: $nativeExe"
  }
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "browser_manager did not write native manifest: $manifestPath"
  }

  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if ($manifest.name -ne $nativeHostName) {
    throw "Unexpected native manifest name: $($manifest.name)"
  }
  if ($manifest.path -ne $nativeExe) {
    throw "Unexpected native manifest path: $($manifest.path)"
  }
  $expectedOrigin = "chrome-extension://$extensionId/"
  if (@($manifest.allowed_origins) -notcontains $expectedOrigin) {
    throw "Native manifest allowed_origins does not contain $expectedOrigin"
  }

  $registryPath = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$nativeHostName"
  $registryValue = (Get-Item -LiteralPath $registryPath -ErrorAction Stop).GetValue("")
  if ($registryValue -ne $manifestPath) {
    throw "Native messaging registry mismatch: $registryValue"
  }

  Write-Host "browser_manager install verification passed: $manifestPath"
}

function Get-ProviderAutoCaptureBrowserPath {
  $playwrightChromium = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "ms-playwright") -Recurse -Filter "chrome.exe" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "\\chromium-[^\\]+\\chrome-win64\\chrome.exe$" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($playwrightChromium) {
    Write-Host "Provider auto capture browser: $($playwrightChromium.FullName)"
    return $playwrightChromium.FullName
  }
  if ($ChromePath -and (Test-Path -LiteralPath $ChromePath)) {
    Write-Host "Provider auto capture browser: $ChromePath"
    return $ChromePath
  }
  return ""
}

New-Item -ItemType Directory -Force -Path (Join-Path $LabRoot "logs") | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $LabRoot "logs\desktop-tests-$stamp.log"
Start-Transcript -Path $logPath -Force | Out-Null

try {
  Write-Host "Rpad repo: $RpadRepo"
  Write-Host "Test site repo: $TestSiteRepo"
  Write-Host "Extension repo: $ExtensionRepo"
  Write-Host "Lab root: $LabRoot"
  Write-Host "Log: $logPath"
  if ($ChromePath -and (Test-Path -LiteralPath $ChromePath)) {
    Write-Host "Chrome path: $ChromePath"
  } else {
    Write-Host "Chrome path not provided/found. Provider test will use browser discovery."
  }
  if ($Include360Smoke -and (Test-Path -LiteralPath $Qihu360Path)) {
    Remove-Item Env:\QIHU360_PATH -ErrorAction SilentlyContinue
    Write-Host "360 browser: $Qihu360Path"
  } elseif ($Include360Smoke) {
    Remove-Item Env:\QIHU360_PATH -ErrorAction SilentlyContinue
    Write-Host "360 browser not found at: $Qihu360Path"
  } else {
    Remove-Item Env:\QIHU360_PATH -ErrorAction SilentlyContinue
    Write-Host "360 browser smoke disabled. Use -Include360Smoke to enable it."
  }

  if (-not (Test-Path -LiteralPath $LabRoot)) {
    throw "Lab root not found: $LabRoot"
  }
  if (-not (Test-Path -LiteralPath $RpadRepo)) {
    throw "Rpad repo not found: $RpadRepo"
  }
  if (-not (Test-Path -LiteralPath $TestSiteRepo)) {
    throw "Test site repo not found: $TestSiteRepo"
  }
  if (-not (Test-Path -LiteralPath $ExtensionRepo)) {
    throw "Extension repo not found: $ExtensionRepo"
  }
  $browserE2eSource = Join-Path $TestSiteRepo "tests\browser_e2e"
  if (Test-Path -LiteralPath $browserE2eSource) {
    Copy-Item -Path (Join-Path $browserE2eSource "*") -Destination $LabRoot -Recurse -Force
    Write-Host "Browser E2E specs synced from: $browserE2eSource"
  }

  $unitTest = Join-Path $RpadRepo "build\src\providers\chrome\test\chrome_unit_test.exe"
  if (-not $SkipProviderUnit) {
    if (-not (Test-Path -LiteralPath $unitTest)) {
      throw "chrome_unit_test.exe not found: $unitTest"
    }
    Invoke-TestCommand -Name "chrome_unit_test" -FilePath $unitTest
  }

  $managerUnitTest = Join-Path $RpadRepo "build\src\features\browser_extension\manager\browser_manager_unit_test.exe"
  if (-not $SkipBrowserManagerUnit) {
    if (-not (Test-Path -LiteralPath $managerUnitTest)) {
      throw "browser_manager_unit_test.exe not found: $managerUnitTest"
    }
    Invoke-TestCommand -Name "browser_manager_unit_test" -FilePath $managerUnitTest
  }

  Push-Location $LabRoot
  $fixtureProcess = $null
  try {
    if (-not $SkipBrowserSmoke) {
      $fixtureProcess = Start-FixtureSite
      Invoke-Playwright -Arguments @("test", "fixture-site.spec.js", "--reporter=line")
      Invoke-Playwright -Arguments @("test", "browser-smoke.spec.js", "--reporter=line")
      if ($Include360Smoke -and (Test-Path -LiteralPath $Qihu360Path)) {
        Invoke-Qihu360NativeSmoke -BrowserPath $Qihu360Path
      }
    }

    if (-not $SkipExtensionSmoke) {
      if (-not (Test-Path -LiteralPath $ExtensionBuild)) {
        throw "Extension build not found: $ExtensionBuild"
      }
      $env:RPAD_EXTENSION_BUILD = $ExtensionBuild
      Invoke-Playwright -Arguments @("test", "rpad-extension-smoke.spec.js", "--reporter=line") -TimeoutSeconds 180
    }
  } finally {
    Stop-FixtureSite -Process $fixtureProcess
    Pop-Location
  }

  if ($RunProviderInteractive) {
    $providerTest = Join-Path $RpadRepo "build\src\providers\chrome\test\chrome_test.exe"
    if (-not (Test-Path -LiteralPath $providerTest)) {
      throw "chrome_test.exe not found: $providerTest"
    }

    $filter = if ($ProviderFilter) { $ProviderFilter } else { "Chrome.Capture" }
    Write-Host "Interactive provider test will wait for a real mouse click in the desktop session."
    Invoke-TestCommand -Name "chrome_test $filter" -FilePath $providerTest -Arguments @("--gtest_filter=$filter")
  }

  if (-not $SkipProviderAutoCapture) {
    $providerTest = Join-Path $RpadRepo "build\src\providers\chrome\test\chrome_test.exe"
    if (-not (Test-Path -LiteralPath $providerTest)) {
      throw "chrome_test.exe not found: $providerTest"
    }
    try {
      $providerState = Join-Path $env:USERPROFILE ".datagrand\var\uris"
      New-Item -ItemType Directory -Force -Path $providerState | Out-Null
      $providerRegistry = Join-Path $providerState "robot_rpad"
      if (-not $SkipBrowserManagerInstall -and $ChromePath -and (Test-Path -LiteralPath $ChromePath)) {
        Invoke-BrowserManagerInstallVerification -BrowserPath $ChromePath
      }
      $providerChromePath = Get-ProviderAutoCaptureBrowserPath
      Initialize-ProviderAutoCaptureNativeHost
      $env:RPAD_EXTENSION_BUILD = $ExtensionBuild
      if ($providerChromePath) {
        $env:RPAD_CHROME_PATH = $providerChromePath
      } else {
        Remove-Item Env:\RPAD_CHROME_PATH -ErrorAction SilentlyContinue
      }
      Invoke-TestCommand -Name "chrome_test ChromeScenario" -FilePath $providerTest -Arguments @("--gtest_filter=ChromeScenario.*", "--registry_file=$providerRegistry") -WorkingDirectory $providerState -TimeoutSeconds 180
      Invoke-TestCommand -Name "chrome_test Chrome.CaptureAuto" -FilePath $providerTest -Arguments @("--gtest_filter=Chrome.CaptureAuto", "--registry_file=$providerRegistry") -WorkingDirectory $providerState -TimeoutSeconds 90
    } finally {
      Stop-ProviderAutoCaptureProcesses
    }
  }

  Write-Host "Desktop tests completed."
} finally {
  Stop-Transcript | Out-Null
  Write-Host "Transcript: $logPath"
}
