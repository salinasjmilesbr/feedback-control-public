[CmdletBinding()]
param(
    [string]$Scenario = '01-cenario-f5-07.sql',
    [string[]]$Validator = @(
        '02-validar-f5-07.sql',
        '03-validar-f5-07-cutover.sql'
    ),
    [Alias('Scripts')]
    [string[]]$Script,
    [object[]]$Plan
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $repoRoot 'supabase'
$validationScriptRoot = Join-Path $sourceRoot 'validacao'
$validationRoot = Join-Path $env:TEMP "feedback-control-validation-$PID"
$validationProjectRoot = Join-Path $validationRoot 'supabase'
$projectId = 'feedback-control-validation'
$containerName = "supabase_db_$projectId"
$runtimeContainerName = 'supabase_db_feedback-control'

. (Join-Path $PSScriptRoot 'DisposableValidationSafety.ps1')

$scriptsToRun = @()
$stepsToRun = @()
if ($null -ne $Plan -and $Plan.Count -gt 0) {
    $stepsToRun = @($Plan)
} elseif ($null -ne $Script -and $Script.Count -gt 0) {
    $scriptsToRun = @($Script)
} else {
    $scriptsToRun = @($Scenario) + @($Validator)
}

if ($stepsToRun.Count -eq 0 -and $scriptsToRun.Count -eq 0) {
    throw 'Nenhum script de validacao foi informado.'
}

function Resolve-PlanPath {
    param([string]$Type, [string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw "Step $Type sem Path." }
    $root = if ($Type -eq 'MIGRATION_REPLAY') { Join-Path $sourceRoot 'migrations' } else { $validationScriptRoot }
    $resolved = Join-Path $root $Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Path inexistente para $Type: $Path"
    }
    return (Resolve-Path -LiteralPath $resolved).Path
}

if ($stepsToRun.Count -eq 0) {
    $stepsToRun = foreach ($scriptName in $scriptsToRun) { [pscustomobject]@{ Type = 'SQL'; Path = $scriptName } }
}

$resolvedPlan = foreach ($step in $stepsToRun) {
    $type = [string]$step.Type
    if ($type -notin @('SQL', 'MIGRATION_REPLAY', 'PSQL_BACKGROUND', 'PSQL_FOREGROUND', 'WAIT')) {
        throw "Tipo de step desconhecido: $type"
    }
    if ($type -eq 'WAIT') {
        if ([string]::IsNullOrWhiteSpace([string]$step.Id)) { throw 'WAIT sem Id.' }
        [pscustomobject]@{ Type = $type; Id = [string]$step.Id }
        continue
    }
    if (($type -eq 'PSQL_BACKGROUND') -and [string]::IsNullOrWhiteSpace([string]$step.Id)) {
        throw 'PSQL_BACKGROUND sem Id.'
    }
    [pscustomobject]@{ Type = $type; Id = [string]$step.Id; Path = Resolve-PlanPath -Type $type -Path ([string]$step.Path) }
}

$backgroundProcesses = @{}
function Invoke-PlanPsql {
    param([string]$Path, [string]$Name)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 |
        docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "Step falhou: $Name" }
}

function Start-PlanPsqlBackground {
    param([string]$Path, [string]$Id)
    $stdout = Join-Path $validationRoot "psql-$Id.out"
    $stderr = Join-Path $validationRoot "psql-$Id.err"
    $process = Start-Process -FilePath 'docker' -ArgumentList @('exec', '-i', $containerName, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1') -RedirectStandardInput $Path -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -NoNewWindow
    $backgroundProcesses[$Id] = $process
}

function Wait-PlanPsqlBackground {
    param([string]$Id)
    if (-not $backgroundProcesses.ContainsKey($Id)) { throw "WAIT para background desconhecido: $Id" }
    $process = $backgroundProcesses[$Id]
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "PSQL_BACKGROUND falhou ($($process.ExitCode)): $Id" }
    $backgroundProcesses.Remove($Id)
}

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

    foreach ($step in $resolvedPlan) {
        switch ($step.Type) {
            'SQL' { Invoke-PlanPsql -Path $step.Path -Name (Split-Path -Leaf $step.Path) }
            'MIGRATION_REPLAY' { Invoke-PlanPsql -Path $step.Path -Name (Split-Path -Leaf $step.Path) }
            'PSQL_BACKGROUND' { Start-PlanPsqlBackground -Path $step.Path -Id $step.Id }
            'PSQL_FOREGROUND' { Invoke-PlanPsql -Path $step.Path -Name (Split-Path -Leaf $step.Path) }
            'WAIT' { Wait-PlanPsqlBackground -Id $step.Id }
        }
    }

    if ($backgroundProcesses.Count -ne 0) {
        throw 'Plano terminou com processos PSQL_BACKGROUND sem WAIT.'
    }

    $runtimeFingerprintAfter = Get-RuntimeFingerprint
    Write-Host "Runtime fingerprint AFTER:`n$runtimeFingerprintAfter"
    if ($runtimeFingerprintBefore -ne $runtimeFingerprintAfter) {
        throw 'Isolamento falhou: fingerprint do runtime mudou durante a validacao.'
    }
    Write-Host 'Isolamento comprovado: fingerprint do runtime permaneceu identico.'
}
finally {
    foreach ($process in $backgroundProcesses.Values) {
        if (-not $process.HasExited) { $process.Kill() }
        $process.WaitForExit()
    }
    if (Test-Path -LiteralPath $validationRoot) {
        & npx --yes supabase@2.116.0 --workdir $validationRoot stop --no-backup
        Remove-Item -LiteralPath $validationRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
