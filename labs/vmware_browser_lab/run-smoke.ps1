param(
  [string]$LabRoot = "C:\browser-e2e"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $LabRoot)) {
  throw "Lab root not found: $LabRoot"
}

Push-Location $LabRoot
npm test
Pop-Location
