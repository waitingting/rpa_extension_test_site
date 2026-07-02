# VMware Browser Lab

This folder prepares a VMware Windows desktop VM for true-machine browser
extension tests.

## Target VM requirements

- Windows 10/11 desktop VM.
- VMware Tools installed.
- Network access to the server repo and extension repo, or VMware shared
  folders mapped into the guest.
- Administrator PowerShell inside the guest.
- A fixed display resolution and DPI for stable coordinate tests.

## Guest setup

Copy this folder into the VM, or access it through a VMware shared folder, then
run PowerShell as Administrator:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\setup-browser-lab.ps1 `
  -TestSiteRepo C:\workspace\rpa_extension_test_site `
  -RpadRepo C:\workspace\rpad `
  -ExtensionRepo C:\workspace\web_extension_unified `
  -Install360Path C:\installers\360browser.exe
```

`-Install360Path` is optional. Use a pinned offline installer for 360 browser.

The script will:

- Enable RDP.
- Enable OpenSSH Server on port 22 when using `connect-and-setup.ps1`.
- Install Chrome.
- Install Firefox.
- Install 360 browser when an installer path is provided.
- Install Node.js.
- Install Playwright dependencies.
- Create `C:\browser-e2e`.
- Copy the smoke tests from `C:\workspace\rpa_extension_test_site\tests\browser_e2e`.

If VMware shared folders expose the host workspace as
`\\vmware-host\Shared Folders\workspace`, create the stable guest path:

```powershell
C:\rpad-vmware-browser-lab\ensure-workspace-link.ps1
```

## Remote setup from the host

If only RDP is enabled, first RDP into the VM and run this one-time command in
Administrator PowerShell:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
Set-NetConnectionProfile -NetworkCategory Private
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
Enable-NetFirewallRule -Name WINRM-HTTP-In-TCP
```

Then run this from the host:

```powershell
C:\workspace\rpa_extension_test_site\labs\vmware_browser_lab\connect-and-setup.ps1 `
  -ComputerName 192.168.150.129 `
  -UserName wpwor `
  -Password 1 `
  -TestSiteRepo C:\workspace\rpa_extension_test_site `
  -Install360Path C:\installers\360browser.exe
```

## Run smoke tests in the VM

```powershell
cd C:\browser-e2e
npm test
```

For true headed browser tests, run the command inside the RDP desktop session.
WinRM is useful for installation and checks, but some browsers, especially
Firefox, can fail in a non-interactive WinRM session because no real desktop
framebuffer is attached.

To start the headed test batch from the host while executing it in the logged-on
desktop session:

```powershell
C:\workspace\rpa_extension_test_site\labs\vmware_browser_lab\start-desktop-tests.ps1 `
  -ComputerName 192.168.150.129 `
  -UserName wpwor `
  -Password 1
```

Logs are written in the VM under `C:\browser-e2e\logs`.

If 360 browser is installed somewhere other than the default per-user path, pass
its executable explicitly and enable the optional 360 smoke:

```powershell
C:\workspace\rpa_extension_test_site\labs\vmware_browser_lab\start-desktop-tests.ps1 `
  -ComputerName 192.168.150.129 `
  -UserName wpwor `
  -Password 1 `
  -TestSiteRepo C:\workspace\rpa_extension_test_site `
  -Include360Smoke `
  -Qihu360Path "C:\Users\wpwor\AppData\Roaming\360se6\Application\360se.exe"
```

To test OS-level keyboard/mouse injection inside the RDP session:

```powershell
C:\rpad-vmware-browser-lab\input-smoke.ps1
```

To pin the current VMware guest address inside Windows, run in elevated
PowerShell inside the VM:

```powershell
C:\rpad-vmware-browser-lab\set-static-ip.ps1 -IPAddress 192.168.150.129
```

The script detects the active adapter, gateway, and DNS from the current DHCP
lease. Pass `-InterfaceAlias`, `-DefaultGateway`, or `-DnsServers` explicitly if
the VM has multiple active adapters.

## Run rpad chrome provider tests

Build on the host or inside the VM, then run inside the VM:

```powershell
C:\workspace\rpad\build\src\providers\chrome\test\chrome_unit_test.exe
C:\workspace\rpad\build\src\providers\chrome\test\chrome_test.exe --gtest_filter=Chrome.Capture
```

`chrome_test.exe --gtest_filter=Chrome.Capture` is interactive. Move the mouse
over a browser element and click to capture.

The non-interactive true-machine capture check is included in the desktop batch
by default:

```powershell
C:\workspace\rpa_extension_test_site\labs\vmware_browser_lab\start-desktop-tests.ps1 `
  -ComputerName 192.168.150.129 `
  -UserName wpwor `
  -Password 1 `
  -TestSiteRepo C:\workspace\rpa_extension_test_site `
  -SkipBrowserSmoke `
  -SkipExtensionSmoke `
  -SkipProviderUnit
```

Before running `chrome_test Chrome.CaptureAuto`, the runner:

- loads the unpacked MV3 extension once to resolve its Chrome extension id;
- writes the HKCU native messaging manifest for
  `com.datagrand.browser_extension.native_app.mv3`;
- writes the provider websocket port under `%USERPROFILE%\.datagrand\var\uris`
  so the Go native host can publish it to the extension;
- starts Chrome with `--load-extension` and a temporary user data directory;
- focuses a fixture DOM button and exits capture by sending Escape.

Use `-SkipProviderAutoCapture` when you only want the browser smoke/unit checks.
If Chrome is installed outside the default path, pass `-ChromePath`.

## Recommended VMware workflow

1. Create a clean VM snapshot named `browser-lab-clean`.
2. Run `setup-browser-lab.ps1`.
3. Create a snapshot named `browser-lab-ready`.
4. Before each true-machine test batch, revert to `browser-lab-ready`.
5. Keep browser versions and extension builds pinned for reproducibility.

## Automation entry points

- `setup-browser-lab.ps1`: one-time or snapshot setup.
- `run-smoke.ps1`: run browser smoke tests.
- `run-desktop-tests.ps1`: run headed browser/provider checks in the VM desktop.
- `start-desktop-tests.ps1`: host-side helper that schedules `run-desktop-tests.ps1`
  into the logged-on VM desktop session.
- `ensure-workspace-link.ps1`: map VMware shared workspace to `C:\workspace`.
- `input-smoke.ps1`: simple OS-level keyboard/mouse smoke script.
- `set-static-ip.ps1`: pin the VM IPv4 address after confirming the current
  gateway and DNS settings.
- `tests/browser_e2e/browser-smoke.spec.js`: Playwright click/input baseline.

For fully remote execution, enable WinRM in the guest and use `Invoke-Command`
from the host. RDP is still useful for observing/debugging coordinate issues.
