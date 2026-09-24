#requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$revision = (Get-Content (Join-Path $root 'platform.ref') -Raw).Trim()
if ($revision -cnotmatch '^[0-9a-f]{40}$') { throw 'platform.ref must contain a full lowercase commit SHA.' }
$destination = Join-Path $root '.platform'
$repository = 'https://github.com/mocelj/azure-platform-catalog.git'
if (Test-Path -LiteralPath $destination) {
    $remote = & git -C $destination remote get-url origin
    if ($LASTEXITCODE -ne 0 -or $remote -ne $repository) { throw 'Existing .platform is not the expected catalog checkout.' }
    $head = & git -C $destination rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $head -ne $revision) { throw 'Existing .platform uses a different revision. Review the checkout before changing it.' }
    if (& git -C $destination status --porcelain) { throw 'The catalog checkout has local changes.' }
} else {
    & git clone --quiet --no-checkout $repository $destination
    if ($LASTEXITCODE -ne 0) { throw 'Catalog clone failed.' }
    & git -C $destination checkout --quiet --detach $revision
    if ($LASTEXITCODE -ne 0) { throw 'Could not check out the approved catalog commit.' }
}
Write-Host "Platform module source: $revision"
