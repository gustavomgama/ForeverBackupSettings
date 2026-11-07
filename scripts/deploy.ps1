param(
    [string]$Addon = "ForeverBackupSettings",
    [string]$Target = "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
)
if ($Addon -match '[\\/:*?"<>|]|\.\.') { throw "invalid addon name: $Addon" }
$src = Join-Path $PSScriptRoot "..\addons\$Addon"
if (-not (Test-Path $src)) { throw "addon not found: $src" }
if (-not (Test-Path $Target)) { throw "target not found: $Target" }
$dst = Join-Path $Target $Addon
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
Copy-Item $src $dst -Recurse
Write-Host "deployed $Addon -> $dst"