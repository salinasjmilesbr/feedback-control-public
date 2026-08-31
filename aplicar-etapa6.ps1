$ErrorActionPreference = "Stop"

node (Join-Path $PSScriptRoot "aplicar-etapa6.mjs")

if ($LASTEXITCODE -ne 0) {
  throw "O aplicador retornou erro."
}

Write-Host "Etapa 6 aplicada. Execute npm run build." -ForegroundColor Green
