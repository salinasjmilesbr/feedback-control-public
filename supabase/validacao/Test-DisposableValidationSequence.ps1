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

function Invoke-Preflight {
    param([object[]]$Steps)
    $json = '[' + (($Steps | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress }) -join ',') + ']'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath -PreflightOnly -PlanJsonBase64 $encoded 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Preflight falhou: $($output -join ' ')" }
    return ($output -join "`n")
}

$simple = Invoke-Preflight @([pscustomobject]@{ Type = 'SQL'; Path = '01-cenario-f5-07.sql' })
if ($simple -notmatch '"Type":"SQL"') { throw 'Preflight de SQL simples nao normalizou.' }
$multiple = Invoke-Preflight @(
    [pscustomobject]@{ Type = 'SQL'; Path = '01-cenario-f5-07.sql' },
    [pscustomobject]@{ Type = 'SQL'; Path = '02-validar-f5-07.sql' }
)
if (($multiple | Select-String -AllMatches '"Type":"SQL"').Matches.Count -ne 2) { throw 'Preflight de Scripts multiplos nao normalizou.' }
$legacy = Invoke-Preflight @([pscustomobject]@{ Type = 'SQL'; Path = '01-cenario-f5-07.sql' })
if ($legacy -notmatch '"Path"') { throw 'Preflight de Scenario/Validator nao normalizou.' }
$withId = Invoke-Preflight @([pscustomobject]@{ Type = 'SQL'; Id = 'optional'; Path = '01-cenario-f5-07.sql' })
if ($withId -notmatch '"Id":"optional"') { throw 'Plan com Id nao normalizou.' }
$withoutId = Invoke-Preflight @([pscustomobject]@{ Type = 'SQL'; Path = '01-cenario-f5-07.sql' })
if ($withoutId -match 'Property.*Id|Id.*cannot be found') { throw 'Plan sem Id ainda falha.' }
$ErrorActionPreference = 'Continue'
$waitJson = '[{"Type":"WAIT"}]'
$waitEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($waitJson))
$waitFailed = & powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath -PreflightOnly -PlanJsonBase64 $waitEncoded 2>&1
if (($waitFailed -join ' ') -notmatch 'WAIT sem Id') { throw 'WAIT sem Id deveria falhar.' }
$unknownJson = '[{"Type":"UNKNOWN","Path":"01-cenario-f5-07.sql"}]'
$unknownEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($unknownJson))
$unknownFailed = & powershell -NoProfile -ExecutionPolicy Bypass -File $runnerPath -PreflightOnly -PlanJsonBase64 $unknownEncoded 2>&1
if (($unknownFailed -join ' ') -notmatch 'Tipo de step desconhecido') { throw 'Tipo desconhecido deveria falhar.' }
$ErrorActionPreference = 'Stop'

$legacyIndex = $runner.IndexOf('$scriptsToRun = @($Scenario) + @($Validator)', [StringComparison]::Ordinal)
$sequenceIndex = $runner.IndexOf('$scriptsToRun = @($Script)', [StringComparison]::Ordinal)
if ($sequenceIndex -lt 0 -or $legacyIndex -lt 0) { throw 'Seletores de contrato nao encontrados.' }

Write-Host 'PASS: contrato legado, sequencia ordenada, validacao previa de paths, falha imediata e cleanup estao presentes.'
