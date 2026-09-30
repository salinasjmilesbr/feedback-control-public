[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runnerPath = Join-Path $PSScriptRoot 'Invoke-DisposableValidation.ps1'
$runner = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Failure)
    if ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) {
        throw $Failure
    }
}

Assert-Contains $runner '[string[]]$Script' 'Parametro Script ausente.'
Assert-Contains $runner '$scriptsToRun = @($Script)' 'Sequencia explicita nao e selecionada.'
Assert-Contains $runner '$scriptsToRun = @($Scenario) + @($Validator)' 'Contrato legado nao e preservado.'
Assert-Contains $runner 'foreach ($scriptName in $scriptsToRun)' 'Paths nao sao validados em ordem antes da execucao.'
Assert-Contains $runner 'if (-not (Test-Path -LiteralPath $resolved -PathType Leaf))' 'Path inexistente nao e rejeitado previamente.'
Assert-Contains $runner '[object[]]$Plan' 'Contrato Plan ausente.'
Assert-Contains $runner "@('SQL', 'MIGRATION_REPLAY', 'PSQL_BACKGROUND', 'PSQL_FOREGROUND', 'WAIT')" 'Allowlist de tipos do plano ausente.'
Assert-Contains $runner "'MIGRATION_REPLAY'" 'Replay de migration nao e suportado.'
Assert-Contains $runner "'PSQL_BACKGROUND'" 'Background psql nao e suportado.'
Assert-Contains $runner "'PSQL_FOREGROUND'" 'Foreground psql nao e suportado.'
Assert-Contains $runner "'WAIT'" 'Wait psql nao e suportado.'
Assert-Contains $runner 'Start-PlanPsqlBackground' 'Orquestracao de background ausente.'
Assert-Contains $runner 'Wait-PlanPsqlBackground' 'Orquestracao de wait ausente.'
Assert-Contains $runner 'Plano terminou com processos PSQL_BACKGROUND sem WAIT.' 'Plano aceita background sem wait.'
Assert-Contains $runner 'foreach ($process in $backgroundProcesses.Values)' 'Cleanup de backgrounds ausente.'
Assert-Contains $runner 'Tipo de step desconhecido:' 'Step desconhecido nao e rejeitado.'
Assert-Contains $runner 'Resolve-PlanPath' 'Paths do plano nao sao preflightados.'
Assert-Contains $runner "Join-Path `$sourceRoot 'migrations'" 'Migration replay nao esta restrito ao catalogo de migrations.'
Assert-Contains $runner "Join-Path `$sourceRoot 'validacao'" 'SQL do plano nao esta restrito ao catalogo de validacao.'
if ($runner -match '\$step\.Command|Invoke-Expression|Start-Process.+\$step\.Command') {
    throw 'Plano aceita superficie de comando arbitrario.'
}
Assert-Contains $runner 'Invoke-Checked $cli ($cliArgs + @(''db'', ''reset'', ''--local'', ''--yes''))' 'Migrations/reset descartavel nao estao protegidos.'
Assert-Contains $runner 'finally {' 'Descarte garantido ausente.'
Assert-Contains $runner 'Remove-Item -LiteralPath $validationRoot -Recurse -Force' 'Limpeza do ambiente descartavel ausente.'
Assert-Contains $runner 'Assert-DisposableValidationTarget' 'Guard do alvo descartavel ausente.'
Assert-Contains $runner 'TEMP' 'Contrato TEMP/TMP nao e referenciado.'

$legacyIndex = $runner.IndexOf('$scriptsToRun = @($Scenario) + @($Validator)', [StringComparison]::Ordinal)
$sequenceIndex = $runner.IndexOf('$scriptsToRun = @($Script)', [StringComparison]::Ordinal)
if ($sequenceIndex -lt 0 -or $legacyIndex -lt 0) { throw 'Seletores de contrato nao encontrados.' }

Write-Host 'PASS: contrato legado, sequencia ordenada, validacao previa de paths, falha imediata e cleanup estao presentes.'
