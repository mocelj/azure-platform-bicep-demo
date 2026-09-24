#requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'Get-PlatformSource.ps1')
$artifacts = Get-Content (Join-Path $root '.platform/catalog/tool-artifacts.json') -Raw | ConvertFrom-Json -AsHashtable
$architecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
$platform = if ($IsWindows) { "win32-$architecture" } elseif ($IsLinux) { "linux-$architecture" } else { throw 'This demo tool setup supports Windows and Linux.' }
$spec = $artifacts.bicep[$platform]
if (-not $spec) { throw "No reviewed Bicep binary is recorded for $platform." }
$tools = Join-Path $root '.tools'
New-Item -ItemType Directory -Path $tools -Force | Out-Null
$binary = Join-Path $tools $(if ($IsWindows) { 'bicep.exe' } else { 'bicep' })
if (-not (Test-Path -LiteralPath $binary) -or (Get-FileHash $binary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $spec.sha256) {
    $download = "$binary.download"
    Invoke-WebRequest $spec.url -OutFile $download
    if ((Get-FileHash $download -Algorithm SHA256).Hash.ToLowerInvariant() -ne $spec.sha256) { throw 'Bicep checksum verification failed.' }
    Move-Item -LiteralPath $download -Destination $binary -Force
}
if (-not $IsWindows) { & chmod +x $binary; if ($LASTEXITCODE -ne 0) { throw 'Could not mark Bicep executable.' } }
$version = & $binary --version
if ($LASTEXITCODE -ne 0 -or $version -notmatch 'version 0\.47\.16 ') { throw 'Bicep 0.47.16 is required.' }
Write-Host $version
