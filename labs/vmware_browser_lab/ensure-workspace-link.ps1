param(
  [string]$Workspace = "C:\workspace",
  [string]$SharedWorkspace = "\\vmware-host\Shared Folders\workspace"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SharedWorkspace)) {
  throw "VMware shared workspace not found: $SharedWorkspace"
}

if (Test-Path -LiteralPath $Workspace) {
  $item = Get-Item -LiteralPath $Workspace -Force
  if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw "$Workspace already exists and is not a symbolic link. Refusing to overwrite it."
  }
} else {
  New-Item -ItemType SymbolicLink -Path $Workspace -Target $SharedWorkspace | Out-Null
}

$checks = [ordered]@{
  Workspace = Test-Path -LiteralPath $Workspace
  RpadRepo = Test-Path -LiteralPath (Join-Path $Workspace "rpad")
  ExtensionRepo = Test-Path -LiteralPath (Join-Path $Workspace "web_extension_unified")
}

$checks.GetEnumerator() | ForEach-Object {
  if (-not $_.Value) {
    throw "Workspace check failed: $($_.Key)"
  }
}

Get-Item -LiteralPath $Workspace -Force | Select-Object FullName, Target
