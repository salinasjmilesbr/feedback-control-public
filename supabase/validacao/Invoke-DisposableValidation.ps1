[CmdletBinding()]
param(
    [string]$Scenario = '01-cenario-f5-07.sql',
    [string[]]$Validator = @(
        '02-validar-f5-07.sql',
        '03-validar-f5-07-cutover.sql'
    )
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $repoRoot 'supabase'
$validationRoot = Join-Path $env:TEMP "feedback-control-validation-$PID"
$validationProjectRoot = Join-Path $validationRoot 'supabase'
$projectId = 'feedback-control-validation'
$containerName = "supabase_db_$projectId"
$runtimeContainerName = 'supabase_db_feedback-control'

. (Join-Path $PSScriptRoot 'DisposableValidationSafety.ps1')

if ($validationRoot -eq $repoRoot -or $validationRoot -eq $sourceRoot) {
    throw 'Alvo de validacao inseguro: a copia temporaria coincide com o projeto/runtime.'
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$ArgumentList)

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Comando falhou ($LASTEXITCODE): $FilePath $($ArgumentList -join ' ')"
    }
}

function Get-RuntimeFingerprint {
    if (-not ((docker ps --format '{{.Names}}') -contains $runtimeContainerName)) {
        throw "Runtime ausente; a prova before/after exige o container $runtimeContainerName em execucao."
    }

    $query = @'
select 'organizations=' || count(*) || ':' || md5(coalesce(string_agg(id::text || ':' || coalesce(name, ''), '|' order by id), '')) from public.organizations;
select 'auth_users=' || count(*) || ':' || md5(coalesce(string_agg(id::text || ':' || coalesce(email, ''), '|' order by id), '')) from auth.users;
'@
    $result = docker exec $runtimeContainerName psql -U postgres -d postgres -At -X -v ON_ERROR_STOP=1 -c $query
    if ($LASTEXITCODE -ne 0) {
        throw 'Nao foi possivel capturar o fingerprint do runtime.'
    }
    return (@($result) | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) -join "`n"
}

try {
    if ((docker ps --format '{{.Names}}') -contains $containerName) {
        throw "A validacao descartavel ja esta em execucao: $containerName. Encerre-a antes de repetir."
    }

    New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null
    Copy-Item -LiteralPath $sourceRoot -Destination $validationProjectRoot -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'src') -Destination (Join-Path $validationRoot 'src') -Recurse -Force

    $configPath = Join-Path $validationProjectRoot 'config.toml'
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $config = $config -replace '(?m)^project_id\s*=\s*"[^"]+"', "project_id = `"$projectId`""
    $config = $config -replace '(?m)^port\s*=\s*54321\r?$', 'port = 55421'
    $config = $config -replace '(?m)^port\s*=\s*54322\r?$', 'port = 55422'
    $config = $config -replace '(?m)^shadow_port\s*=\s*54320\r?$', 'shadow_port = 55420'
    $config = $config -replace '(?m)^port\s*=\s*54323\r?$', 'port = 55423'
    $config = $config -replace '(?ms)(\[local_smtp\]\r?\n)enabled\s*=\s*true', '$1enabled = false'
    Set-Content -LiteralPath $configPath -Value $config -Encoding UTF8 -NoNewline

    Assert-DisposableValidationTarget -Workdir $validationRoot -TempRoot $env:TEMP `
        -ProjectId $projectId -ContainerName $containerName `
        -RuntimeContainerName $runtimeContainerName -Config $config
    Write-Host 'Config descartavel validado: project_id e portas conferem.'

    $runtimeFingerprintBefore = Get-RuntimeFingerprint
    Write-Host "Runtime fingerprint BEFORE:`n$runtimeFingerprintBefore"

    $cli = 'npx'
    $cliArgs = @('--yes', 'supabase@2.116.0', '--workdir', $validationRoot)
    Invoke-Checked $cli ($cliArgs + @('start'))
    Invoke-Checked $cli ($cliArgs + @('db', 'reset', '--local', '--yes'))

    if (-not ((docker ps --format '{{.Names}}') -contains $containerName)) {
        throw "Container descartavel esperado nao esta em execucao: $containerName"
    }
    if ((docker ps --format '{{.Names}}') -contains $runtimeContainerName) {
        Write-Host "Runtime preservado; alvo da validacao: $containerName"
    }

    $scenarioPath = Join-Path (Join-Path $sourceRoot 'validacao') $Scenario
    if (-not (Test-Path -LiteralPath $scenarioPath -PathType Leaf)) {
        throw "Cenario inexistente: $Scenario"
    }
    Get-Content -LiteralPath $scenarioPath -Raw -Encoding UTF8 |
        docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "Cenario falhou: $Scenario" }

    foreach ($validatorName in $Validator) {
        $validatorPath = Join-Path (Join-Path $sourceRoot 'validacao') $validatorName
        if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
            throw "Validador inexistente: $validatorName"
        }
        Get-Content -LiteralPath $validatorPath -Raw -Encoding UTF8 |
            docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1
        if ($LASTEXITCODE -ne 0) { throw "Validador falhou: $validatorName" }
    }

    $runtimeFingerprintAfter = Get-RuntimeFingerprint
    Write-Host "Runtime fingerprint AFTER:`n$runtimeFingerprintAfter"
    if ($runtimeFingerprintBefore -ne $runtimeFingerprintAfter) {
        throw 'Isolamento falhou: fingerprint do runtime mudou durante a validacao.'
    }
    Write-Host 'Isolamento comprovado: fingerprint do runtime permaneceu identico.'
}
finally {
    if (Test-Path -LiteralPath $validationRoot) {
        & npx --yes supabase@2.116.0 --workdir $validationRoot stop --no-backup
        Remove-Item -LiteralPath $validationRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
