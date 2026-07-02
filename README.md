# RPA Extension Test Framework

This repository contains the product-side browser extension automation test
framework. It keeps browser fixture sites, Playwright browser smoke tests, and
VMware true-machine lab scripts outside of the rpad server repository.

## Project Layout

```text
sites/extension-fixtures/      Dense local websites used by capture tests
tests/browser_e2e/             Playwright browser and extension smoke tests
labs/vmware_browser_lab/       Windows VM setup and desktop automation scripts
scripts/start.ps1              Starts the local fixture sites
```

The rpad repository remains responsible for provider implementation, unit tests,
and compiled test binaries. This repository is responsible for preparing and
driving realistic browser environments.

## Local Fixture Site

```powershell
cd C:\workspace\rpa_extension_test_site
yarn install
yarn start
```

Open:

```text
http://127.0.0.1:8007/
```

The start script runs three `http-server` processes:

```text
main     http://127.0.0.1:8007/
cross-a  http://127.0.0.1:8008/
cross-b  http://127.0.0.1:8009/
```

The different host/port combinations are deliberate so browser extensions see
real cross-origin frames.

## Fixture Coverage

- Same-origin iframe: `sites/extension-fixtures/main/frames/same-origin.html`
- Nested same-origin iframe: `sites/extension-fixtures/main/frames/nested.html`
- Cross-origin iframe: `http://127.0.0.1:8008/cross-origin.html`
- Nested cross-origin iframe: `http://127.0.0.1:8009/deep-cross.html`
- Text inputs, password, search, email, url, tel, number, date/time family, color, file, range
- Radio, checkbox, datalist, single and multiple select, textarea, contenteditable
- Buttons, links, image, canvas, svg, details, dialog, progress, meter
- Complex table with rowspan, colspan, inputs and action buttons
- Nested lists, ordered lists, definition lists, ARIA tree-like region
- Open shadow DOM fixture
- Static duplicate `data-dgid` values to simulate saved pages that already contain extension markers

## VMware True-Machine Lab

Current lab VM:

```text
Host:     192.168.150.129
User:     wpwor
Password: 1
Shared:   host C:\workspace mapped to guest C:\workspace
Browsers: 360, Google Chrome, Firefox, Edge
```

The host builds rpad and the browser extension. The VM runs the built binaries
directly through the shared `C:\workspace` directory.

Recommended fixed-IP setup inside the Windows VM:

```powershell
C:\workspace\rpa_extension_test_site\labs\vmware_browser_lab\set-static-ip.ps1 -IPAddress 192.168.150.129
```

The helper detects the active adapter, default gateway, and DNS from the current
DHCP lease. If the VM uses VMware NAT DHCP reservation instead, pin
`192.168.150.129` in VMware's DHCP config and keep the guest on DHCP.

Run the full headed desktop regression from the host:

```powershell
C:\workspace\rpa_extension_test_site\labs\vmware_browser_lab\start-desktop-tests.ps1 `
  -ComputerName 192.168.150.129 `
  -UserName wpwor `
  -Password 1 `
  -TestSiteRepo C:\workspace\rpa_extension_test_site `
  -RpadRepo C:\workspace\rpad `
  -ExtensionRepo C:\workspace\web_extension_unified `
  -ExtensionBuild C:\workspace\web_extension_unified\build-mv3-rpad-e2e-3 `
  -ExtensionId "" `
  -Include360Smoke `
  -Qihu360Path "C:\Users\wpwor\AppData\Roaming\360se6\Application\360se.exe"
```

Logs are written in the VM under:

```text
C:\browser-e2e\logs
```

## Test Coverage

Unit tests are built and owned by the rpad repo, then executed in the VM:

```text
C:\workspace\rpad\build\src\providers\chrome\test\chrome_unit_test.exe
C:\workspace\rpad\build\src\features\browser_extension\manager\browser_manager_unit_test.exe
```

Functional tests cover:

- Chromium and Firefox click/input smoke
- Optional 360 browser native mouse/keyboard smoke
- Unpacked extension loading smoke
- Browser manager installation verification
- Chrome provider scenario tests: `ChromeScenario.*`
- Non-interactive real browser capture: `Chrome.CaptureAuto`

## Test Dashboard

Start the local dashboard from the host:

```powershell
cd C:\workspace\rpa_extension_test_site
yarn dashboard
```

Open:

```text
http://127.0.0.1:8787/
```

The dashboard can run one selected test at a time and stream the result log.
Available entries include:

- Local `chrome_unit_test.exe`
- Local `browser_manager_unit_test.exe`
- Local fixture, browser smoke, and unpacked extension smoke tests
- VM full regression
- VM unit-only run
- VM browser smoke run
- VM extension smoke run
- VM provider scenario and capture run

The VM runs are started through `labs/vmware_browser_lab/start-desktop-tests.ps1`.
After the VM scheduled task starts, the dashboard polls `C:\browser-e2e\logs`
over WinRM and displays the latest desktop test log.

Environment variables can override defaults before starting the dashboard:

```powershell
$env:RPAD_REPO = "C:\workspace\rpad"
$env:RPAD_EXTENSION_REPO = "C:\workspace\web_extension_unified"
$env:RPAD_EXTENSION_BUILD = "C:\workspace\web_extension_unified\build-mv3-rpad-e2e-3"
$env:RPA_VM_HOST = "192.168.150.129"
$env:RPA_VM_USER = "wpwor"
$env:RPA_VM_PASSWORD = "1"
$env:RPA_QIHU360_PATH = "C:\Users\wpwor\AppData\Roaming\360se6\Application\360se.exe"
```

## Stop Site Servers

The start script prints spawned process IDs. Stop only those PIDs, or use:

```powershell
Get-Process node | Where-Object { $_.Path -like '*node*' } | Stop-Process
```
