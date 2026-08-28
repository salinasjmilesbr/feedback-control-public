$ErrorActionPreference = "Stop"

$arquivo = Join-Path $PSScriptRoot "src\pages\ColaboradorDetalhePage.tsx"
if (-not (Test-Path $arquivo)) {
    $arquivo = Join-Path (Get-Location) "src\pages\ColaboradorDetalhePage.tsx"
}

if (-not (Test-Path $arquivo)) {
    throw "Arquivo src/pages/ColaboradorDetalhePage.tsx não encontrado."
}

$conteudo = Get-Content -Raw -Encoding UTF8 $arquivo

if ($conteudo -notmatch 'useLayoutEffect') {
    $conteudoNovo = $conteudo -replace `
        'import \{ useState, type CSSProperties, type ReactNode \} from "react";', `
        'import { useLayoutEffect, useState, type CSSProperties, type ReactNode } from "react";'

    if ($conteudoNovo -eq $conteudo) {
        throw "Não foi possível localizar o import do React para incluir useLayoutEffect."
    }

    $conteudo = $conteudoNovo
}

if ($conteudo -notmatch 'window\.scrollTo\(0,\s*0\)') {
    $ancora = '  const navigate = useNavigate();'
    $insercao = @'
  const navigate = useNavigate();

  useLayoutEffect(() => {
    window.scrollTo(0, 0);
  }, [id]);
'@

    if (-not $conteudo.Contains($ancora)) {
        throw "Não foi possível localizar o ponto de inserção do scroll no topo."
    }

    $conteudo = $conteudo.Replace($ancora, $insercao)
}

Set-Content -Path $arquivo -Value $conteudo -Encoding UTF8
Write-Host "Ajuste aplicado: ColaboradorDetalhePage agora abre sempre no topo." -ForegroundColor Green
