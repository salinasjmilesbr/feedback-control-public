$ErrorActionPreference = "Stop"

$arquivo = Join-Path (Get-Location) "src\pages\MinhaAvaliacaoDetalhePage.tsx"

if (-not (Test-Path $arquivo)) {
    throw "Arquivo não encontrado: $arquivo. Execute este script na raiz do projeto feedback-control."
}

$conteudo = Get-Content -Raw -Encoding UTF8 $arquivo

# 1) Importa o formatador central de notas.
$importAntigo = @'
import {
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
'@

$importNovo = @'
import {
  formatarNota,
  getEscalaAvaliacao,
  getItemEscalaPorNota,
} from "../services/escalaAvaliacaoStorage";
'@

if ($conteudo.Contains($importAntigo)) {
    $conteudo = $conteudo.Replace($importAntigo, $importNovo)
}

# 2) Padroniza todas as notas visíveis desta página para uma casa decimal.
$substituicoes = @{
    'feedback.notaMedia.toFixed(2)' = 'formatarNota(feedback.notaMedia)'
    'item.notaMedia.toFixed(2)' = 'formatarNota(item.notaMedia)'
    'criterio.nota.toFixed(2)' = 'formatarNota(criterio.nota)'
    'subcriterio.notaGerente.toFixed(2)' = 'formatarNota(subcriterio.notaGerente)'
    'subcriterio.notaCoordenador.toFixed(2)' = 'formatarNota(subcriterio.notaCoordenador)'
    'subcriterio.notaColegiado.toFixed(2)' = 'formatarNota(subcriterio.notaColegiado)'
    'subcriterio.notaFinal.toFixed(2)' = 'formatarNota(subcriterio.notaFinal)'
}

foreach ($par in $substituicoes.GetEnumerator()) {
    $conteudo = $conteudo.Replace($par.Key, $par.Value)
}

# 3) Atualiza a explicação da régua: ela agora usa faixas configuráveis, não arredondamento.
$textoAntigo = @'
              Médias decimais usam a nota inteira mais próxima para a
              referência visual.
'@

$textoNovo = @'
              Médias decimais são classificadas conforme as faixas definidas
              na configuração da régua de notas.
'@

$conteudo = $conteudo.Replace($textoAntigo, $textoNovo)

Set-Content -Path $arquivo -Value $conteudo -Encoding UTF8

Write-Host ""
Write-Host "Patch aplicado com sucesso em:"
Write-Host "  src/pages/MinhaAvaliacaoDetalhePage.tsx"
Write-Host ""
Write-Host "Agora rode: npm run build"
