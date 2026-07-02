# RPA Extension Test Site

This fixture site is intentionally dense. It is meant for manually testing browser extension capture, selector generation, iframe traversal, form controls, tables, lists, dynamic DOM changes, and pre-existing `data-dgid` collisions.

## Start

```powershell
cd C:\workspace\rpa_extension_test_site
yarn install
yarn start
```

Open:

```text
http://localhost:8007/
```

The start script runs three `http-server` processes:

```text
main     http://localhost:8007/
cross-a  http://127.0.0.1:8008/
cross-b  http://localhost:8009/
```

The different host/port combinations are deliberate so browser extensions see real cross-origin frames.

## Coverage

- Same-origin iframe: `main/frames/same-origin.html`
- Nested same-origin iframe: `main/frames/nested.html`
- Cross-origin iframe: `http://127.0.0.1:8008/cross-origin.html`
- Nested cross-origin iframe: `http://localhost:8009/deep-cross.html`
- Text inputs, password, search, email, url, tel, number, date/time family, color, file, range
- Radio, checkbox, datalist, single and multiple select, textarea, contenteditable
- Buttons, links, image, canvas, svg, details, dialog, progress, meter
- Complex table with rowspan, colspan, inputs and action buttons
- Nested lists, ordered lists, definition lists, ARIA tree-like region
- Open shadow DOM fixture
- Static duplicate `data-dgid` values to simulate saved pages that already contain extension markers

## Stop Servers

The start script prints the spawned process IDs. Stop them from the same shell with:

```powershell
Get-Process node | Where-Object { $_.Path -like '*node*' } | Stop-Process
```

If other Node processes are running, stop only the printed PIDs.
