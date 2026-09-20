$ErrorActionPreference = 'Stop'
Remove-Item Env:DEBUG -ErrorAction SilentlyContinue
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
  $portableJava = Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.cache\farmtwin\jdk') -Filter java.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $portableJava) { throw 'Install Java 21+ or place a portable JRE under ~/.cache/farmtwin/jdk.' }
  $env:PATH = "$($portableJava.DirectoryName);$env:PATH"
}
Push-Location (Join-Path $workspace 'functions')
try {
  npm run test
  if ($LASTEXITCODE -ne 0) { throw 'Backend verification failed.' }
} finally { Pop-Location }
