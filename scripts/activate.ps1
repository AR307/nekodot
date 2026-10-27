$runtime = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '../.runtime') -Directory -Filter 'node-v24*-win-x64' | Select-Object -First 1
if (-not $runtime) { throw 'Install Node 24 LTS, or provision the project-local Node 24 runtime first.' }
$env:PATH = $runtime.FullName + [IO.Path]::PathSeparator + $env:PATH
Write-Host "Node $(node --version) ready for nekodot."
