[CmdletBinding()]
param(
    [string]$Scenario = '01-cenario-f5-07.sql',
    [string[]]$Validator = @(
        '02-validar-f5-07.sql',
        '03-validar-f5-07-cutover.sql'
    ),
    [switch]$Interactive,
    [string]$TargetCommit,
    [string]$CandidateWorktree
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
    param([string]$FilePath, [string[]]$ArgumentList, [switch]$Quiet)

    if ($Quiet) {
        $previousErrorAction = $ErrorActionPreference
        try {
            # Windows PowerShell promotes native stderr progress to NativeCommandError
            # under Stop. Keep CLI output (including credentials) out of the terminal.
            $ErrorActionPreference = 'Continue'
            & $FilePath @ArgumentList *> $null
        } finally {
            $ErrorActionPreference = $previousErrorAction
        }
    } else {
        & $FilePath @ArgumentList
    }
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

function Assert-NoDisposableResources {
    $containers = @(docker ps -a --format '{{.Names}}')
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel inventariar containers Docker.' }
    $volumes = @(docker volume ls --format '{{.Name}}')
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel inventariar volumes Docker.' }
    $networks = @(docker network ls --format '{{.Name}}')
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel inventariar redes Docker.' }
    Assert-NoDisposableResourceNames -Containers $containers -Volumes $volumes -Networks $networks
}

function Assert-InteractiveMainCheckout {
    $branch = git -C $repoRoot branch --show-current
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel ler a branch local.' }
    $head = git -C $repoRoot rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel ler HEAD.' }
    $originMain = git -C $repoRoot rev-parse refs/remotes/origin/main
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel ler origin/main.' }
    $relevant = @(git -C $repoRoot status --porcelain --untracked-files=all -- `
        supabase/migrations supabase/functions supabase/config.toml `
        supabase/seed.sql supabase/roles.sql src)
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel conferir as fontes da stack.' }
    Assert-DisposableMainState -Branch $branch -Head $head -OriginMain $originMain -RelevantStatus $relevant
    return $head
}

function Assert-InteractiveResourceOwnership {
    $container = docker inspect $containerName | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel inspecionar o container descartavel.' }
    $volume = docker volume inspect 'supabase_db_feedback-control-validation' | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel inspecionar o volume descartavel.' }
    $network = docker network inspect 'supabase_network_feedback-control-validation' | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel inspecionar a rede descartavel.' }
    Assert-DisposableResourceOwnership -Container $container -Volume $volume -Network $network -Workdir $validationRoot
}

$startAttempted = $false
$validationLock = $null
$candidateManifest = $null
$worktreeManifest = $null
if ($PSBoundParameters.ContainsKey('TargetCommit') -and -not $Interactive) {
    throw 'TargetCommit exige o modo Interactive.'
}
if ($PSBoundParameters.ContainsKey('CandidateWorktree') -and -not $Interactive) {
    throw 'CandidateWorktree exige o modo Interactive.'
}
if ($PSBoundParameters.ContainsKey('CandidateWorktree') -and $PSBoundParameters.ContainsKey('TargetCommit')) {
    throw 'CandidateWorktree e TargetCommit sao mutuamente exclusivos.'
}
try {
    $validationLock = Enter-DisposableValidationLock -TempRoot $env:TEMP
    if ($Interactive) {
        if ($PSBoundParameters.ContainsKey('CandidateWorktree')) {
            $candidatePath = Assert-DisposableCandidateWorktreePath -CandidateWorktree $CandidateWorktree -RepoRoot $repoRoot
            $worktreeManifest = Assert-DisposableCandidateWorktreeCheckout -RepoRoot $repoRoot -CandidateWorktree $candidatePath
            $baselineCommit = $worktreeManifest.BaselineCommit
        } else {
            $baselineCommit = Assert-InteractiveMainCheckout
            if ($PSBoundParameters.ContainsKey('TargetCommit')) {
                $candidateManifest = Assert-DisposableTargetCommit -RepoRoot $repoRoot `
                    -BaselineCommit $baselineCommit -TargetCommit $TargetCommit
            }
        }
        Assert-NoDisposableResources
        Assert-DisposablePortsAvailable -Ports @(55420, 55421, 55422, 55423)
        if (Test-Path -LiteralPath $validationRoot) { throw "Workdir descartavel preexistente: $validationRoot" }
    } elseif ((docker ps --format '{{.Names}}') -contains $containerName) {
        throw "A validacao descartavel ja esta em execucao: $containerName. Encerre-a antes de repetir."
    }

    New-Item -ItemType Directory -Path $validationRoot -Force | Out-Null
    if ($null -ne $worktreeManifest) {
        $worktreeManifest = Invoke-DisposableCandidateWorktreeMaterialization -RepoRoot $repoRoot `
            -BaselineCommit $worktreeManifest.BaselineCommit `
            -CandidateWorktree $worktreeManifest.CandidatePath `
            -CandidateBranch $worktreeManifest.CandidateBranch `
            -ProjectRoot $validationRoot
        $worktreeManifest | ConvertTo-Json -Depth 6 | Set-Content `
            -LiteralPath (Join-Path $validationRoot 'candidate-worktree-manifest.json') -Encoding UTF8
        Write-Host "Baseline origin/main: $($worktreeManifest.BaselineCommit); candidato (worktree nao commitado): $($worktreeManifest.Candidate.Path)"
        Write-Host "Snapshot verificado antes de Docker/Supabase: $($worktreeManifest.SnapshotFileCount) arquivo(s); fingerprint $($worktreeManifest.SnapshotFingerprint)"
        Write-Host "Operacoes materializadas: $($worktreeManifest.Operations.Count); migrations novas: $(@($worktreeManifest.NewMigrations).Count); historicas verificadas: $(@($worktreeManifest.HistoricalMigrations).Count)"
    } elseif ($null -ne $candidateManifest) {
        $applicationFiles = @('index.html', 'package.json', 'package-lock.json',
            'vite.config.ts', 'tsconfig.json', 'tsconfig.app.json', 'tsconfig.node.json', 'eslint.config.js')
        Export-DisposableCommitPaths -RepoRoot $repoRoot -Commit $baselineCommit `
            -ProjectRoot $validationRoot -Paths @('supabase')
        Export-DisposableCommitPaths -RepoRoot $repoRoot -Commit $TargetCommit `
            -ProjectRoot $validationRoot -Paths (@('src', 'public') + $applicationFiles)
        Assert-DisposableExportedTree -RepoRoot $repoRoot -Commit $baselineCommit `
            -ProjectRoot $validationRoot -Path 'supabase'
        Assert-DisposableExportedTree -RepoRoot $repoRoot -Commit $TargetCommit `
            -ProjectRoot $validationRoot -Path 'src'
        Assert-DisposableExportedTree -RepoRoot $repoRoot -Commit $TargetCommit `
            -ProjectRoot $validationRoot -Path 'public'
        Assert-DisposableExportedFiles -RepoRoot $repoRoot -Commit $TargetCommit `
            -ProjectRoot $validationRoot -Paths $applicationFiles
        Assert-DisposableSourceCopyWithoutTemp -ProjectRoot $validationProjectRoot
        $candidateManifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $validationRoot 'candidate-manifest.json') -Encoding UTF8
        Write-Host "Baseline Supabase: $baselineCommit; aplicacao candidata: $TargetCommit"
    } else {
        Copy-DisposableSupabaseSource -SourceRoot $sourceRoot -TargetRoot $validationProjectRoot
        Copy-Item -LiteralPath (Join-Path $repoRoot 'src') -Destination (Join-Path $validationRoot 'src') -Recurse -Force
    }
    Write-Host 'Copia descartavel sem supabase/.temp validada antes do start.'

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

    if ($null -ne $worktreeManifest) {
        # A transformacao CONTROLADA do config.toml ocorre DEPOIS do fingerprint do
        # snapshot e e registrada SEPARADAMENTE (o fingerprint acima nao a inclui).
        [pscustomobject]@{
            Mode                = 'CandidateWorktree'
            ConfigPath          = 'supabase/config.toml'
            BaselineCommit      = $worktreeManifest.BaselineCommit
            SnapshotFingerprint = $worktreeManifest.SnapshotFingerprint
            ConfigSha256        = (Get-DisposableSha256 -Path $configPath)
            Transformations     = @(
                "project_id -> $projectId",
                'api.port 54321 -> 55421',
                'db.port 54322 -> 55422',
                'db.shadow_port 54320 -> 55420',
                'studio.port 54323 -> 55423',
                'local_smtp.enabled true -> false'
            )
        } | ConvertTo-Json -Depth 4 | Set-Content `
            -LiteralPath (Join-Path $validationRoot 'candidate-worktree-config-transform.json') -Encoding UTF8
        Write-Host 'Transformacao de config registrada separadamente do manifesto do snapshot.'
    }

    if ($Interactive) {
        $migrationFiles = @(Get-ChildItem -LiteralPath (Join-Path $validationProjectRoot 'migrations') -File -Filter '*.sql' | ForEach-Object { $_.Name })
        Assert-DisposableEvaluationMigrations -MigrationFiles $migrationFiles
        Write-Host 'Copia descartavel: #404 presente; migrations #414 ausentes.'
    }

    $runtimeFingerprintBefore = Get-RuntimeFingerprint
    Write-Host "Runtime fingerprint BEFORE:`n$runtimeFingerprintBefore"

    $cli = 'npx'
    $cliArgs = @('--yes', 'supabase@2.116.0', '--workdir', $validationRoot)
    $startAttempted = $true
    Invoke-Checked $cli ($cliArgs + @('start')) -Quiet:$Interactive
    Invoke-Checked $cli ($cliArgs + @('db', 'reset', '--local', '--yes'))

    if (-not ((docker ps --format '{{.Names}}') -contains $containerName)) {
        throw "Container descartavel esperado nao esta em execucao: $containerName"
    }
    if ($Interactive) { Assert-InteractiveResourceOwnership }
    if ((docker ps --format '{{.Names}}') -contains $runtimeContainerName) {
        Write-Host "Runtime preservado; alvo da validacao: $containerName"
    }

    if ($Interactive) {
        $versions = @(docker exec $containerName psql -U postgres -d postgres -At -X -v ON_ERROR_STOP=1 -c 'select version from supabase_migrations.schema_migrations order by version')
        if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel conferir migrations do banco descartavel.' }
        Assert-DisposableEvaluationMigrations -MigrationFiles $migrationFiles -AppliedVersions $versions
        Write-Host 'Banco descartavel: #404 aplicada; migrations #414 ausentes.'
    } else {
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
    }

    $runtimeFingerprintAfter = Get-RuntimeFingerprint
    Write-Host "Runtime fingerprint AFTER:`n$runtimeFingerprintAfter"
    if ($runtimeFingerprintBefore -ne $runtimeFingerprintAfter) {
        throw 'Isolamento falhou: fingerprint do runtime mudou durante a validacao.'
    }
    Write-Host 'Isolamento comprovado: fingerprint do runtime permaneceu identico.'
    if ($Interactive) {
        Write-Host "Stack descartavel ativa: project_id=$projectId; API=http://127.0.0.1:55421; Studio=http://127.0.0.1:55423"
        Write-Host "Workdir descartavel: $validationRoot"
        Write-Host 'Mantenha este terminal aberto. Digite ENCERRAR e pressione Enter para descartar a stack.'
        do {
            $answer = Read-Host 'Comando de encerramento'
            if ($null -eq $answer) { throw 'Entrada interativa encerrada; iniciando cleanup.' }
        } while ($answer -ne 'ENCERRAR')
    }
}
finally {
    try {
        if ($Interactive) {
            Invoke-DisposableInteractiveCleanup -Workdir $validationRoot -TempRoot $env:TEMP `
                -ProjectId $projectId -ContainerName $containerName `
                -RuntimeContainerName $runtimeContainerName -StartAttempted $startAttempted `
                -GetContainers {
                    $names = @(docker ps -a --format '{{.Names}}')
                    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel inventariar containers no cleanup.' }
                    $names
                } -AssertOwnership { Assert-InteractiveResourceOwnership } -StopStack {
                    & npx --yes supabase@2.116.0 --workdir $validationRoot stop --no-backup
                    if ($LASTEXITCODE -ne 0) { throw "Stop descartavel falhou; workdir preservado para diagnostico: $validationRoot" }
                }
        } elseif (Test-Path -LiteralPath $validationRoot) {
            & npx --yes supabase@2.116.0 --workdir $validationRoot stop --no-backup
            Remove-Item -LiteralPath $validationRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    } finally {
        if ($null -ne $validationLock) { $validationLock.Dispose() }
    }
}
