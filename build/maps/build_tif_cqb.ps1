# Builds maps/tif_cqb.bsp: generate the VMF, then vbsp++ / vvis++ / vrad++.
# Usage: powershell -ExecutionPolicy Bypass -File build_tif_cqb.ps1 [-Fast]
param([switch]$Fast)

$ErrorActionPreference = "Stop"
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$addon = Split-Path -Parent $here
$game  = "K:\SteamLibrary\steamapps\common\GarrysMod\garrysmod"
$tools = "K:\THE SUPER RTX DIDDY MAP EDITOR\TOOLS++"
$build = Join-Path $here "build"

python (Join-Path $here "make_tif_cqb.py")
if ($LASTEXITCODE -ne 0) { throw "VMF generation failed" }

New-Item -ItemType Directory -Force $build | Out-Null
Copy-Item (Join-Path $here "tif_cqb.vmf") $build -Force
$map = Join-Path $build "tif_cqb"

& "$tools\vbsp++.exe" -game $game $map
if ($LASTEXITCODE -ne 0) { throw "vbsp++ failed" }
if ($Fast) { & "$tools\vvis++.exe" -fast -game $game $map } else { & "$tools\vvis++.exe" -game $game $map }
if ($LASTEXITCODE -ne 0) { throw "vvis++ failed" }
if ($Fast) { & "$tools\vrad++.exe" -fast -game $game $map } else { & "$tools\vrad++.exe" -final -game $game $map }
if ($LASTEXITCODE -ne 0) { throw "vrad++ failed" }

$maps = Join-Path $addon "maps"
New-Item -ItemType Directory -Force $maps | Out-Null
Copy-Item "$map.bsp" $maps -Force
Write-Host "Built $maps\tif_cqb.bsp"
