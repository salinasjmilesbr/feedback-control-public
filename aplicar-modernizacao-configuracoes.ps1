$ErrorActionPreference = "Stop"

$pagina = Join-Path (Get-Location) "src\pages\ConfiguracoesAparenciaPage.tsx"
$index = Join-Path (Get-Location) "src\index.css"
$cssPatch = Join-Path $PSScriptRoot "configuracoes-identidade-modernizacao.css"

if (-not (Test-Path $pagina)) { throw "ConfiguracoesAparenciaPage.tsx não encontrada." }
if (-not (Test-Path $index)) { throw "src/index.css não encontrado." }
if (-not (Test-Path $cssPatch)) { throw "CSS do patch não encontrado." }

$conteudoPagina = Get-Content -Raw -Encoding UTF8 $pagina

if ($conteudoPagina -notmatch 'className="branding-page virtus-page"') {
    if ($conteudoPagina -notmatch 'className="branding-page"') {
        throw "Não foi possível localizar o container branding-page."
    }

    $conteudoPagina = $conteudoPagina.Replace(
        'className="branding-page"',
        'className="branding-page virtus-page"'
    )

    Set-Content -Path $pagina -Value $conteudoPagina -Encoding UTF8
}

$conteudoIndex = Get-Content -Raw -Encoding UTF8 $index
$marcador = "VIRTUS — Configurações / Identidade visual"

if ($conteudoIndex -notmatch [regex]::Escape($marcador)) {
    $novoCss = Get-Content -Raw -Encoding UTF8 $cssPatch
    Add-Content -Path $index -Value "`r`n$novoCss" -Encoding UTF8
}

Write-Host "Modernização de Configurações / Identidade Visual aplicada." -ForegroundColor Green
Write-Host "Nenhuma função de branding ou régua de notas foi alterada." -ForegroundColor Green
