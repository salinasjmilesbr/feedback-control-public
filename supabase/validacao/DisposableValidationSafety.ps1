Set-StrictMode -Version Latest

function Get-DisposableConfigValue {
    param([string]$Text, [string]$Key)

    $pattern = '(?m)^' + [regex]::Escape($Key) + '\s*=\s*"([^"]+)"\s*$'
    $matches = [regex]::Matches($Text, $pattern)
    if ($matches.Count -ne 1) { throw "Config temporario invalido: esperado exatamente um valor quoted para $Key." }
    return $matches[0].Groups[1].Value
}

function Get-DisposableConfigPort {
    param([string]$Text, [string]$Section, [string]$Key)

    $sectionPattern = '(?ms)^\[' + [regex]::Escape($Section) + '\]\r?\n(.*?)(?=^\[|\z)'
    $sectionMatch = [regex]::Match($Text, $sectionPattern)
    if (-not $sectionMatch.Success) { throw "Config temporario invalido: secao [$Section] ausente." }
    $portPattern = '(?m)^' + [regex]::Escape($Key) + '\s*=\s*(\d+)\s*$'
    $portMatches = [regex]::Matches($sectionMatch.Groups[1].Value, $portPattern)
    if ($portMatches.Count -ne 1) { throw "Config temporario invalido: esperado exatamente um $Section.$Key." }
    return [int]$portMatches[0].Groups[1].Value
}

function Assert-DisposableValidationWorkdir {
    param([string]$Workdir, [string]$TempRoot)

    $resolvedWorkdir = (Resolve-Path -LiteralPath $Workdir -ErrorAction Stop).Path
    $resolvedTempRoot = (Resolve-Path -LiteralPath $TempRoot -ErrorAction Stop).Path
    if ((Split-Path -Parent $resolvedWorkdir) -ne $resolvedTempRoot -or (Split-Path -Leaf $resolvedWorkdir) -notmatch '^feedback-control-validation-\d+$') {
        throw 'Workdir descartavel inseguro: esperado diretorio temporario feedback-control-validation-<PID>.'
    }
}

function Copy-DisposableSupabaseSource {
    param([string]$SourceRoot, [string]$TargetRoot)

    New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $SourceRoot -Force | Where-Object { $_.Name -ne '.temp' } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $TargetRoot -Recurse -Force
    }
    Assert-DisposableSourceCopyWithoutTemp -ProjectRoot $TargetRoot
}

function Assert-DisposableSourceCopyWithoutTemp {
    param([string]$ProjectRoot)

    if (Test-Path -LiteralPath (Join-Path $ProjectRoot '.temp')) {
        throw 'Copia descartavel contem estado local supabase/.temp.'
    }
}

function Assert-DisposableValidationTarget {
    param([string]$Workdir, [string]$TempRoot, [string]$ProjectId, [string]$ContainerName, [string]$RuntimeContainerName, [string]$Config)

    Assert-DisposableValidationWorkdir -Workdir $Workdir -TempRoot $TempRoot
    if ($ProjectId -ne 'feedback-control-validation' -or (Get-DisposableConfigValue $Config 'project_id') -ne $ProjectId) {
        throw 'Config temporario inseguro: project_id nao e feedback-control-validation.'
    }
    if ((Get-DisposableConfigPort $Config 'api' 'port') -ne 55421 -or (Get-DisposableConfigPort $Config 'db' 'port') -ne 55422 -or (Get-DisposableConfigPort $Config 'db' 'shadow_port') -ne 55420 -or (Get-DisposableConfigPort $Config 'studio' 'port') -ne 55423) {
        throw 'Config temporario inseguro: portas nao correspondem ao ambiente descartavel.'
    }
    if ($RuntimeContainerName -ne 'supabase_db_feedback-control' -or $ContainerName -ne 'supabase_db_feedback-control-validation' -or $ContainerName -eq $RuntimeContainerName) {
        throw 'Container de validacao inseguro: o runtime compartilhado nunca pode ser alvo.'
    }
}

function Assert-DisposableEvaluationMigrations {
    param([string[]]$MigrationFiles, [string[]]$AppliedVersions)

    if (@($MigrationFiles | Where-Object { $_ -eq '20261018000000_f6_404_evaluation_mutation_bundles.sql' }).Count -ne 1) {
        throw 'Migration #404 ausente da copia descartavel.'
    }
    if (@($MigrationFiles | Where-Object { $_ -match '^202610(?:19|2[0-6])\d{6}.*f6_414.*\.sql$' }).Count -gt 0) {
        throw 'Migration #414 encontrada na copia descartavel.'
    }
    if ($null -ne $AppliedVersions) {
        if (@($AppliedVersions | Where-Object { $_ -eq '20261018000000' }).Count -ne 1) {
            throw 'Migration #404 nao foi aplicada no banco descartavel.'
        }
        if (@($AppliedVersions | Where-Object { $_ -match '^202610(?:19|2[0-6])\d{6}$' }).Count -gt 0) {
            throw 'Migration posterior a #404 encontrada no banco descartavel.'
        }
    }
}

function Assert-NoDisposableResourceNames {
    param([string[]]$Containers, [string[]]$Volumes, [string[]]$Networks)

    if (@($Containers + $Volumes + $Networks | Where-Object { $_ -like '*feedback-control-validation' }).Count -gt 0) {
        throw 'Recursos feedback-control-validation preexistentes: diagnostique antes de iniciar; nenhuma limpeza automatica sera feita.'
    }
}

function Enter-DisposableValidationLock {
    param([string]$TempRoot)

    $root = (Resolve-Path -LiteralPath $TempRoot -ErrorAction Stop).Path
    $path = Join-Path $root 'feedback-control-validation.lock'
    try {
        return [System.IO.FileStream]::new(
            $path, [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None,
            4096, [System.IO.FileOptions]::DeleteOnClose
        )
    } catch [System.IO.IOException] {
        throw 'Outra validacao descartavel usa feedback-control-validation; aguarde seu encerramento.'
    }
}

function Assert-DisposableMainState {
    param([string]$Branch, [string]$Head, [string]$OriginMain, [string[]]$RelevantStatus)

    if ($Branch -ne 'main' -or [string]::IsNullOrWhiteSpace($Head) -or $Head -ne $OriginMain) {
        throw 'Modo interativo exige main alinhada a origin/main.'
    }
    if (@($RelevantStatus | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw 'Modo interativo exige fontes de runtime/migrations sem alteracoes locais.'
    }
}

function Get-DisposableCommitProbe {
    param([string]$RepoRoot, [string[]]$ArgumentList)

    # Sob ErrorActionPreference=Stop o stderr nativo vira erro terminante antes da
    # mensagem do guard; aqui o stderr e capturado e o exit code fica em $LASTEXITCODE.
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        return (& git -C $RepoRoot @ArgumentList 2>&1 | ForEach-Object { $_.ToString() })
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

function Get-DisposableCommitHash {
    param([string]$RepoRoot, [string[]]$ArgumentList)

    $output = @(Get-DisposableCommitProbe -RepoRoot $RepoRoot -ArgumentList $ArgumentList)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1 -or $output[0] -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Commit de referencia sem hash de arvore unico e valido.'
    }
    return $output[0]
}

function Assert-DisposableTargetCommit {
    param([string]$RepoRoot, [string]$BaselineCommit, [string]$TargetCommit)

    if ($TargetCommit -cnotmatch '^[0-9a-f]{40}$' -or $BaselineCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'TargetCommit e baseline exigem SHA completo.'
    }
    $kind = @(Get-DisposableCommitProbe -RepoRoot $RepoRoot -ArgumentList @('cat-file', '-t', $TargetCommit))
    if ($LASTEXITCODE -ne 0 -or $kind.Count -ne 1 -or $kind[0] -cne 'commit') {
        throw 'TargetCommit inexistente ou nao e commit.'
    }
    $null = Get-DisposableCommitProbe -RepoRoot $RepoRoot -ArgumentList @('merge-base', '--is-ancestor', $BaselineCommit, $TargetCommit)
    if ($LASTEXITCODE -ne 0) { throw 'TargetCommit nao inclui a main vigente.' }
    $baselineSupabase = Get-DisposableCommitHash -RepoRoot $RepoRoot -ArgumentList @('rev-parse', "${BaselineCommit}:supabase")
    $candidateSupabase = Get-DisposableCommitHash -RepoRoot $RepoRoot -ArgumentList @('rev-parse', "${TargetCommit}:supabase")
    if ($candidateSupabase -cne $baselineSupabase) {
        throw 'TargetCommit altera Supabase; este modo exige a arvore da main.'
    }
    $candidateSrc = Get-DisposableCommitHash -RepoRoot $RepoRoot -ArgumentList @('rev-parse', "${TargetCommit}:src")
    return [pscustomobject]@{
        BaselineCommit = $BaselineCommit
        TargetCommit = $TargetCommit
        BaselineSupabaseTree = $baselineSupabase
        CandidateSrcTree = $candidateSrc
    }
}

function Export-DisposableCommitPaths {
    param([string]$RepoRoot, [string]$Commit, [string]$ProjectRoot, [string[]]$Paths)

    Assert-DisposableValidationWorkdir -Workdir $ProjectRoot -TempRoot (Split-Path -Parent $ProjectRoot)
    $archive = Join-Path $ProjectRoot 'source-snapshot.zip'
    if (Test-Path -LiteralPath $archive) { throw 'Arquivo de snapshot descartavel ja existe.' }
    try {
        # `git archive` honra `core.autocrlf` e gravaria LF->CRLF no snapshot, o que
        # faria a prova de identidade por bytes crus (`hash-object --no-filters`)
        # divergir do blob sem qualquer mudanca real de conteudo. O snapshot deve
        # conter exatamente os bytes do blob; a conversao de EOL nao participa da
        # materializacao descartavel.
        git -C $RepoRoot -c core.autocrlf=false archive --format=zip "--output=$archive" $Commit -- @Paths
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao materializar o commit imutavel.' }
        Expand-Archive -LiteralPath $archive -DestinationPath $ProjectRoot -Force
    } finally {
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    }
}

function Assert-DisposableExportedTree {
    param([string]$RepoRoot, [string]$Commit, [string]$ProjectRoot, [string]$Path)

    $entries = @(git -C $RepoRoot ls-tree -r --full-tree $Commit -- $Path)
    if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) { throw "Arvore exportada ausente: $Path" }
    $expected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $entries) {
        if ($entry -cnotmatch '^100(?:644|755) blob ([0-9a-f]{40})\t(.+)$') {
            throw "Entrada Git nao suportada na arvore: $Path"
        }
        $oid = $Matches[1]
        $relative = $Matches[2]
        if (-not $relative.StartsWith("$Path/", [System.StringComparison]::Ordinal) -or
            $relative -match '(^|/)(\.\.|\.temp|start-secrets|docker\.env|\.env[^/]*)($|/)') {
            throw 'Snapshot contem path inseguro.'
        }
        $null = $expected.Add($relative)
        $file = Join-Path $ProjectRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Arquivo do commit ausente: $relative" }
        $actual = git -C $RepoRoot hash-object --no-filters -- $file
        if ($LASTEXITCODE -ne 0 -or $actual -ne $oid) { throw "Arquivo diverge do commit: $relative" }
    }
    $actualFiles = @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot $Path) -Recurse -File -Force)
    if ($actualFiles.Count -ne $expected.Count) { throw "Arquivos extras ou ausentes na arvore: $Path" }
}

function Assert-DisposableExportedFiles {
    param([string]$RepoRoot, [string]$Commit, [string]$ProjectRoot, [string[]]$Paths)

    foreach ($relative in $Paths) {
        $expected = git -C $RepoRoot rev-parse "${Commit}:$relative"
        if ($LASTEXITCODE -ne 0 -or $expected -notmatch '^[0-9a-f]{40}$') {
            throw "Arquivo do commit invalido: $relative"
        }
        $file = Join-Path $ProjectRoot $relative
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Arquivo exportado ausente: $relative" }
        $actual = git -C $RepoRoot hash-object --no-filters -- $file
        if ($LASTEXITCODE -ne 0 -or $actual -ne $expected) { throw "Arquivo diverge do commit: $relative" }
    }
}

function Assert-DisposablePortsAvailable {
    param([int[]]$Ports)

    foreach ($port in $Ports) {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
        try {
            $listener.Start()
        } catch [System.Net.Sockets.SocketException] {
            throw "Porta descartavel indisponivel: $port"
        } finally {
            $listener.Stop()
        }
    }
}

function Assert-DisposableResourceOwnership {
    param($Container, $Volume, $Network, [string]$Workdir)

    if ($Container.Name.TrimStart('/') -ne 'supabase_db_feedback-control-validation' -or
        $Container.Config.Labels.'com.supabase.cli.project' -ne 'feedback-control-validation' -or
        $Container.Config.Labels.'com.supabase.cli.workdir' -ne $Workdir -or
        @($Container.Mounts | Where-Object { $_.Name -eq 'supabase_db_feedback-control-validation' }).Count -ne 1 -or
        -not $Container.NetworkSettings.Networks.PSObject.Properties['supabase_network_feedback-control-validation']) {
        throw 'Container descartavel sem identidade/mount/rede esperados.'
    }
    if ($Volume.Name -ne 'supabase_db_feedback-control-validation' -or
        $Volume.Labels.'com.supabase.cli.project' -ne 'feedback-control-validation') {
        throw 'Volume descartavel sem identidade esperada.'
    }
    if ($Network.Name -ne 'supabase_network_feedback-control-validation' -or
        -not $Network.Containers.PSObject.Properties[$Container.Id]) {
        throw 'Rede descartavel nao contem o container esperado.'
    }
}

function Invoke-DisposableInteractiveCleanup {
    param(
        [string]$Workdir, [string]$TempRoot, [string]$ProjectId,
        [string]$ContainerName, [string]$RuntimeContainerName,
        [bool]$StartAttempted,
        [scriptblock]$GetContainers, [scriptblock]$AssertOwnership, [scriptblock]$StopStack
    )

    if (-not (Test-Path -LiteralPath $Workdir)) { return }
    Assert-DisposableValidationWorkdir -Workdir $Workdir -TempRoot $TempRoot
    if ($StartAttempted) {
        $configPath = Join-Path (Join-Path $Workdir 'supabase') 'config.toml'
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            throw "Config descartavel ausente; workdir preservado: $Workdir"
        }
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        Assert-DisposableValidationTarget -Workdir $Workdir -TempRoot $TempRoot `
            -ProjectId $ProjectId -ContainerName $ContainerName `
            -RuntimeContainerName $RuntimeContainerName -Config $config
        if (@(& $GetContainers) -contains $ContainerName) { & $AssertOwnership }
        & $StopStack
    }
    Remove-Item -LiteralPath $Workdir -Recurse -Force
}

# ============================================================================
# Modo CandidateWorktree (contrato fechado)
#
# Certifica um worktree NAO COMMITADO (src/** e supabase/**) cujo HEAD e
# exatamente origin/main. Baseline e exportado por `git archive`; as diferencas
# do candidato entram por INVENTARIO Git NUL-safe e copia dos BYTES FINAIS,
# sem patches e sem tocar o index/staging do candidato. Tudo e verificado antes
# de qualquer Docker/Supabase.
# ============================================================================

$script:DisposableCandidateRoots = @('src', 'public', 'supabase')
$script:DisposableCandidateApplicationFiles = @(
    'index.html', 'package.json', 'package-lock.json', 'vite.config.ts',
    'tsconfig.json', 'tsconfig.app.json', 'tsconfig.node.json', 'eslint.config.js'
)
# Segmentos proibidos em QUALQUER profundidade (o caso `.env*` e decidido por
# NOME, para permitir os templates versionados — ver o helper abaixo).
$script:DisposableForbiddenRelativePattern = '(^|/)(\.\.|\.temp|start-secrets|docker\.env|node_modules|\.git)(/|$)'
$script:DisposableForbiddenFullPattern = '(^|/)(\.\.|\.temp|start-secrets|docker\.env|node_modules|\.git)(/|$)'
# Templates versionados e INTENCIONAIS do repositorio: nao sao segredo.
$script:DisposableEnvTemplateNames = @('.env.example', '.env.sample', '.env.template')

<#
Regra UNICA de nome de segredo/estado local, aplicada de forma consistente pelo
inventario (path-safety), pela varredura de raiz e pela varredura recursiva:

- `.env.example`, `.env.sample` e `.env.template` sao PERMITIDOS (templates);
- `.env` e qualquer `.env.<sufixo>` (inclui `.env.local`, `.env.production` e
  `.env.production.local`) continuam PROIBIDOS;
- `.temp`, `start-secrets` e `docker.env` continuam PROIBIDOS.

A comparacao e case-insensitive (semantica do filesystem no Windows) e o
allowlist e por nome EXATO — `.env.example.local` NAO e template e segue proibido.
#>
function Test-DisposableForbiddenSecretName {
    param([string]$Name, [bool]$IsDirectory = $false)

    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    # Templates versionados sao excecao APENAS quando sao ARQUIVOS. Um DIRETORIO
    # com nome de template NAO recebe a excecao e cai na regra de `.env.*` abaixo.
    if (-not $IsDirectory) {
        foreach ($template in $script:DisposableEnvTemplateNames) {
            if ($Name.Equals($template, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
    }
    if ($Name.Equals('.env', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($Name.StartsWith('.env.', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    foreach ($estado in @('.temp', 'start-secrets', 'docker.env')) {
        if ($Name.Equals($estado, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
$script:DisposableMigrationFilePattern = '^[0-9]{14}_[a-z0-9_]+\.sql$'
$script:DisposableHistoricalMigrationException = 'Migration historica do baseline alterada/removida pelo candidato'

function Get-DisposableSha256 {
    param([string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLowerInvariant()
    } finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

function Get-DisposableRelativePath {
    param([string]$Root, [string]$FullName)

    $prefix = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $FullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path fora do workdir descartavel: $FullName"
    }
    return $FullName.Substring($prefix.Length).Replace('\', '/')
}

function Assert-DisposableCandidatePathSafe {
    param([string]$Relative)

    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative -match '[\x00-\x1f]') {
        throw 'Candidato com path vazio ou de controle.'
    }
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '\\' -or $Relative -match ':') {
        throw "Path inseguro/ambiguo no candidato: $Relative"
    }
    if ($Relative -match $script:DisposableForbiddenRelativePattern) {
        throw "Path proibido no candidato (segredo/estado local): $Relative"
    }
    foreach ($segmento in ($Relative -split '/')) {
        if (Test-DisposableForbiddenSecretName -Name $segmento) {
            throw "Path proibido no candidato (segredo/estado local): $Relative"
        }
    }
    $root = ($Relative -split '/')[0]
    if ($script:DisposableCandidateRoots -notcontains $root -and $script:DisposableCandidateApplicationFiles -notcontains $Relative) {
        throw "Path fora da allowlist do CandidateWorktree: $Relative"
    }
}

function ConvertTo-DisposableCanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonical = [IO.Path]::GetFullPath($Path).Replace([char]'/', [char]'\')
    $root = [IO.Path]::GetPathRoot($canonical)
    if ($canonical.Length -gt $root.Length) {
        $canonical = $canonical.TrimEnd([char]'\')
    }
    return $canonical
}

function Test-DisposablePathIdentity {
    param([Parameter(Mandatory = $true)][string]$Left, [Parameter(Mandatory = $true)][string]$Right)

    $canonicalLeft = ConvertTo-DisposableCanonicalPath -Path $Left
    $canonicalRight = ConvertTo-DisposableCanonicalPath -Path $Right
    return [string]::Equals($canonicalLeft, $canonicalRight, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-DisposableCandidateWorktreePath {
    param([string]$CandidateWorktree, [string]$RepoRoot)

    if ([string]::IsNullOrWhiteSpace($CandidateWorktree) -or -not [IO.Path]::IsPathRooted($CandidateWorktree)) {
        throw 'CandidateWorktree exige caminho absoluto.'
    }
    if (-not (Test-Path -LiteralPath $CandidateWorktree -PathType Container)) {
        throw "CandidateWorktree inexistente: $CandidateWorktree"
    }
    $candidate = (Resolve-Path -LiteralPath $CandidateWorktree -ErrorAction Stop).Path
    $infra = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
    if (Test-DisposablePathRedirects -Path $candidate) {
        throw 'CandidateWorktree nao pode ser link/redirecionamento de path.'
    }
    if ($candidate -eq $infra) {
        throw 'CandidateWorktree nao pode ser o proprio worktree de infraestrutura.'
    }
    if ($candidate.StartsWith($infra + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
        $infra.StartsWith($candidate + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'CandidateWorktree e o worktree de infraestrutura sao aninhados (path ambiguo).'
    }
    $top = @(Get-DisposableCommitProbe -RepoRoot $candidate -ArgumentList @('rev-parse', '--show-toplevel'))
    if ($LASTEXITCODE -ne 0 -or $top.Count -ne 1 -or -not (Test-DisposablePathIdentity -Left $top[0].Trim() -Right $candidate)) {
        throw 'CandidateWorktree nao e a raiz de um worktree Git.'
    }
    return $candidate
}

function Assert-DisposableCandidateWorktreeCheckout {
    param([string]$RepoRoot, [string]$CandidateWorktree)

    $baseline = Get-DisposableCommitHash -RepoRoot $RepoRoot -ArgumentList @('rev-parse', 'refs/remotes/origin/main')
    if ($baseline -cnotmatch '^[0-9a-f]{40}$') { throw 'origin/main invalido para o baseline.' }
    $headProbe = @(Get-DisposableCommitProbe -RepoRoot $CandidateWorktree -ArgumentList @('rev-parse', 'HEAD'))
    if ($LASTEXITCODE -ne 0 -or $headProbe.Count -ne 1) { throw 'Nao foi possivel ler HEAD do CandidateWorktree.' }
    $head = $headProbe[0].Trim()
    if ($head -cne $baseline) {
        throw "HEAD do CandidateWorktree diverge do baseline (origin/main): $head <> $baseline"
    }
    $branchProbe = @(Get-DisposableCommitProbe -RepoRoot $CandidateWorktree -ArgumentList @('branch', '--show-current'))
    $branch = if ($branchProbe.Count -eq 1) { $branchProbe[0].Trim() } else { '' }
    return [pscustomobject]@{
        BaselineCommit  = $baseline
        CandidatePath   = $CandidateWorktree
        CandidateHead   = $head
        CandidateBranch = $branch
    }
}

function Get-DisposableCandidateStatusEntries {
    param([string]$CandidateWorktree)

    $pathSpecs = @($script:DisposableCandidateRoots) + @($script:DisposableCandidateApplicationFiles)
    # Saida NUL-safe capturada como STRING unica: o formato `-z` nao usa newlines e
    # preserva os NUL, sem redirecionamento de processo nem arquivo temporario.
    $text = (& git -C $CandidateWorktree -c core.quotePath=false status --porcelain=v1 -z --untracked-files=all -- @pathSpecs) -join ''
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel inventariar o CandidateWorktree.' }
    $tokens = @($text.Split([char]0) | Where-Object { $_ -ne '' })
    $entries = [System.Collections.Generic.List[object]]::new()
    $index = 0
    while ($index -lt $tokens.Count) {
        $token = $tokens[$index]
        if ($token.Length -lt 4 -or $token[2] -ne ' ') { throw "Entrada de status invalida: $token" }
        $status = $token.Substring(0, 2)
        $path = $token.Substring(3)
        $original = $null
        $index++
        if ($status[0] -eq 'R' -or $status[0] -eq 'C') {
            if ($index -ge $tokens.Count) { throw 'Entrada de rename/copy sem origem.' }
            $original = $tokens[$index]
            $index++
        }
        $entries.Add([pscustomobject]@{ Status = $status; Path = $path; OriginalPath = $original })
    }
    return $entries
}

# Tags cloud do Windows/OneDrive (placeholders). SOMENTE estas sao permitidas
# quando o item tem o atributo ReparsePoint. Qualquer outra tag — SymbolicLink
# (0xa000000c), MountPoint/Junction (0xa0000003), LX_SYMLINK/WSL (0xa000001d),
# APPEXECLINK (0x8000001b), desconhecida, ilegivel ou nao determinavel — => DENY.
# Armazenadas como HEX CANONICO (8 digitos, minusculas): evita a ambiguidade de
# sinal do literal `0x…` do PowerShell (que vira Int32 negativo quando > 0x7FFFFFFF).
$script:DisposableCloudReparseTags = @(
    '9000001a',   # IO_REPARSE_TAG_CLOUD
    '9000101a', '9000201a', '9000301a', '9000401a', '9000501a', '9000601a',
    '9000701a', '9000801a', '9000901a', '9000a01a', '9000b01a', '9000c01a',
    '9000e01a'    # IO_REPARSE_TAG_CLOUD_14 (placeholder de DIRETORIO do OneDrive)
)

function Test-DisposableCloudReparseTag {
    param($Tag)

    # Classificacao PURA e deterministica: aceita SOMENTE tags cloud conhecidas.
    # Entrada numerica ou string hex ("0x9000601a"); qualquer outra => false.
    if ($null -eq $Tag) { return $false }
    if ($Tag -is [int] -or $Tag -is [long] -or $Tag -is [int64] -or $Tag -is [uint32] -or $Tag -is [uint64]) {
        $hex = ('{0:x}' -f ([uint64][long]$Tag)).PadLeft(8, '0')
    } else {
        $texto = ([string]$Tag).Trim()
        if ($texto -notmatch '^(0x)?[0-9a-fA-F]{1,16}$') { return $false }
        $hex = ($texto -replace '^0[xX]', '').ToLowerInvariant().PadLeft(8, '0')
    }
    return ($script:DisposableCloudReparseTags -contains $hex)
}

function Get-DisposableReparseTag {
    param([string]$Path)

    # Obtencao NATIVA e deterministica da tag via `fsutil reparsepoint query`
    # (leitura nao exige elevacao). Funciona no Windows PowerShell 5.1. A saida e
    # localizada; extraimos o PRIMEIRO `0x<hex>` da PRIMEIRA linha (que e sempre a
    # "Reparse Tag"), sem depender de rotulo. Falha, saida vazia, ausencia de tag ou
    # formato inesperado => $null (o chamador nega — fail-closed).
    try { $saida = @(& fsutil reparsepoint query $Path 2>&1) } catch { return $null }
    if ($LASTEXITCODE -ne 0 -or $saida.Count -eq 0) { return $null }
    $primeira = [string]$saida[0]
    $m = [regex]::Match($primeira, '0x[0-9a-fA-F]+')
    if (-not $m.Success) { return $null }
    return $m.Value
}

function Test-DisposablePathRedirects {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    # E reparse: so e seguro se a TAG for positivamente cloud. LinkType/Target e
    # ResolveLinkTarget NAO estabelecem seguranca (o host 5.1 nao tem a API e nao
    # preenche LinkType para tags desconhecidas — por isso a decisao e pela tag).
    $tag = Get-DisposableReparseTag -Path $Path
    if ($null -eq $tag) { return $true }
    if (Test-DisposableCloudReparseTag -Tag $tag) { return $false }
    return $true
}

function Assert-DisposablePathComponentsResolve {
    param([string]$Root, [string]$Relative)

    # Nenhum componente do caminho — inclusive diretorios INTERMEDIARIOS — pode
    # redirecionar a resolucao para outro alvo (symlink/junction de diretorio). Um
    # junction no meio do caminho levaria bytes de fora do worktree para dentro do
    # snapshot, entao a checagem e por componente, nao apenas no arquivo final.
    $current = $Root
    foreach ($segmento in ($Relative -split '/')) {
        $current = Join-Path $current $segmento
        if (-not (Test-Path -LiteralPath $current)) { continue }
        if (Test-DisposablePathRedirects -Path $current) {
            throw "CandidateWorktree contem link/redirecionamento de path: $Relative"
        }
    }
}

function Copy-DisposableCandidateFileBytes {
    param([string]$SourcePath, [string]$TargetPath)

    $targetDir = Split-Path -Parent $TargetPath
    if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    # Leitura INTEGRAL do arquivo do candidato (hidrata placeholder de nuvem sob
    # demanda). Se a leitura falhar ou vier parcial, reprova fail-closed; o arquivo
    # do candidato NAO e alterado.
    try { $bytes = [IO.File]::ReadAllBytes($SourcePath) } catch { throw "CandidateWorktree ilegivel (falha de leitura/hidratacao): $SourcePath" }
    if ($bytes.Length -ne (Get-Item -LiteralPath $SourcePath -Force).Length) { throw "CandidateWorktree com leitura parcial: $SourcePath" }
    [IO.File]::WriteAllBytes($TargetPath, $bytes)
    # Alteracao durante a captura: o arquivo do candidato precisa continuar
    # identico ao que foi materializado.
    $after = Get-DisposableSha256 -Path $SourcePath
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $materialized = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant() } finally { $sha.Dispose() }
    if ($after -ne $materialized) { throw "CandidateWorktree alterado durante a captura: $SourcePath" }
    if ((Get-DisposableSha256 -Path $TargetPath) -ne $materialized) { throw "Snapshot divergente do candidato: $TargetPath" }
    return [pscustomobject]@{ Size = $bytes.Length; Sha256 = $materialized }
}

function Assert-DisposableCandidateNoForbiddenPaths {
    param([string]$CandidateWorktree)

    # (1) RAIZ do worktree: segredo/estado local presente no candidato reprova a
    # certificacao MESMO quando o Git o ignora (o host pode ter ignore global de
    # `.env*`, o que o esconderia do inventario). Templates versionados
    # (`.env.example`/`.env.sample`/`.env.template`) sao permitidos.
    $rootEntries = @(Get-ChildItem -LiteralPath $CandidateWorktree -Force -ErrorAction SilentlyContinue |
        Where-Object { Test-DisposableForbiddenSecretName -Name $_.Name -IsDirectory $_.PSIsContainer })
    if ($rootEntries.Count -gt 0) {
        throw "CandidateWorktree contem path proibido (segredo/estado local): $($rootEntries[0].Name)"
    }
    # (2) Roots allowlisted (recursivo): mesma regra de nome + segmentos proibidos
    # de materializacao (`..`, `.temp`, `start-secrets`, `docker.env`,
    # `node_modules`, `.git`).
    foreach ($root in $script:DisposableCandidateRoots) {
        $rootPath = Join-Path $CandidateWorktree $root
        if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { continue }
        $found = @(Get-ChildItem -LiteralPath $rootPath -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object {
                (Test-DisposableForbiddenSecretName -Name $_.Name -IsDirectory $_.PSIsContainer) -or
                ($_.FullName.Replace('\', '/') -match $script:DisposableForbiddenFullPattern)
            })
        if ($found.Count -gt 0) {
            throw "CandidateWorktree contem path proibido (segredo/estado local): $(Get-DisposableRelativePath -Root $CandidateWorktree -FullName $found[0].FullName)"
        }
    }
}

function Get-DisposableBaselineMigrationNames {
    param([string]$RepoRoot, [string]$BaselineCommit)

    $entries = @(git -C $RepoRoot ls-tree -r --name-only $BaselineCommit -- supabase/migrations)
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel listar migrations do baseline.' }
    return @($entries | ForEach-Object { $_.Trim() } | Where-Object { $_ -like 'supabase/migrations/*.sql' } | ForEach-Object { ($_ -split '/')[-1] })
}

function Assert-DisposableSnapshotMigrations {
    param([string]$ProjectRoot, [string[]]$BaselineMigrationNames)

    $migrationDir = Join-Path $ProjectRoot 'migrations'
    if (-not (Test-Path -LiteralPath $migrationDir -PathType Container)) { throw 'Snapshot sem supabase/migrations.' }
    $snapshotNames = @(Get-ChildItem -LiteralPath $migrationDir -File -Filter '*.sql' | ForEach-Object { $_.Name })
    $missing = @($BaselineMigrationNames | Where-Object { $snapshotNames -notcontains $_ })
    if ($missing.Count -gt 0) { throw "Migration historica ausente do snapshot: $($missing -join ', ')" }
    $historicais = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($name in $BaselineMigrationNames) { $null = $historicais.Add($name) }
    $novas = @($snapshotNames | Where-Object { -not $historicais.Contains($_) })
    foreach ($name in $novas) {
        if ($name -notmatch $script:DisposableMigrationFilePattern) { throw "Migration nova com versao/nome invalido: $name" }
    }
    $versoes = @{}
    foreach ($name in $snapshotNames) {
        $version = $name.Substring(0, 14)
        if ($versoes.ContainsKey($version)) { throw "Versao de migration duplicada no snapshot: $version" }
        $versoes[$version] = $name
    }
    Assert-DisposableEvaluationMigrations -MigrationFiles $snapshotNames
    return [pscustomobject]@{ Historical = @($BaselineMigrationNames | Sort-Object); New = @($novas | Sort-Object) }
}

function Invoke-DisposableCandidateWorktreeMaterialization {
    param(
        [string]$RepoRoot,
        [string]$BaselineCommit,
        [string]$CandidateWorktree,
        [string]$ProjectRoot,
        [string]$CandidateBranch
    )

    $paths = @($script:DisposableCandidateRoots) + @($script:DisposableCandidateApplicationFiles)
    Export-DisposableCommitPaths -RepoRoot $RepoRoot -Commit $BaselineCommit -ProjectRoot $ProjectRoot -Paths $paths
    foreach ($root in $script:DisposableCandidateRoots) {
        Assert-DisposableExportedTree -RepoRoot $RepoRoot -Commit $BaselineCommit -ProjectRoot $ProjectRoot -Path $root
    }
    Assert-DisposableExportedFiles -RepoRoot $RepoRoot -Commit $BaselineCommit -ProjectRoot $ProjectRoot -Paths $script:DisposableCandidateApplicationFiles
    Assert-DisposableSourceCopyWithoutTemp -ProjectRoot (Join-Path $ProjectRoot 'supabase')

    $baselineMigrations = Get-DisposableBaselineMigrationNames -RepoRoot $RepoRoot -BaselineCommit $BaselineCommit
    $historicais = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($name in $baselineMigrations) { $null = $historicais.Add($name) }

    Assert-DisposableCandidateNoForbiddenPaths -CandidateWorktree $CandidateWorktree
    $entries = Get-DisposableCandidateStatusEntries -CandidateWorktree $CandidateWorktree
    $operations = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $entries) {
        Assert-DisposableCandidatePathSafe -Relative $entry.Path
        $isMigrationPath = $entry.Path -like 'supabase/migrations/*.sql'
        $isHistoricalNew = $isMigrationPath -and $historicais.Contains(($entry.Path -split '/')[-1])
        $original = $entry.OriginalPath
        if ($null -ne $original) {
            Assert-DisposableCandidatePathSafe -Relative $original
            $originalName = ($original -split '/')[-1]
            if ($original -like 'supabase/migrations/*.sql' -and $historicais.Contains($originalName)) { throw "$($script:DisposableHistoricalMigrationException): $original" }
            $sourceOriginal = Join-Path $ProjectRoot ($original.Replace('/', [IO.Path]::DirectorySeparatorChar))
            if (Test-Path -LiteralPath $sourceOriginal) {
                Remove-Item -LiteralPath $sourceOriginal -Force
                # Rename/copy: a origem entra no manifesto como `delete` para que o
                # delta do snapshot fique COMPLETO e verificavel.
                $operations.Add([pscustomobject]@{ Path = $original; Operation = 'delete'; Size = 0; Sha256 = '' })
            }
        }
        $source = Join-Path $CandidateWorktree ($entry.Path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $target = Join-Path $ProjectRoot ($entry.Path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $existed = Test-Path -LiteralPath $target -PathType Leaf
        if (-not (Test-Path -LiteralPath $source)) {
            if ($isHistoricalNew) { throw "$($script:DisposableHistoricalMigrationException): $($entry.Path)" }
            if ($existed) { Remove-Item -LiteralPath $target -Force }
            $operations.Add([pscustomobject]@{ Path = $entry.Path; Operation = 'delete'; Size = 0; Sha256 = '' })
            continue
        }
        $item = Get-Item -LiteralPath $source -Force
        Assert-DisposablePathComponentsResolve -Root $CandidateWorktree -Relative $entry.Path
        if ($item.PSIsContainer) { throw "CandidateWorktree contem diretorio nao suportado: $($entry.Path)" }
        if ($isHistoricalNew) { throw "$($script:DisposableHistoricalMigrationException): $($entry.Path)" }
        $bytes = Copy-DisposableCandidateFileBytes -SourcePath $source -TargetPath $target
        $operations.Add([pscustomobject]@{
            Path = $entry.Path
            Operation = if ($existed) { 'modify' } else { 'add' }
            Size = $bytes.Size
            Sha256 = $bytes.Sha256
        })
    }

    $ordered = @($operations | Sort-Object -Property Path)
    # Verificacao INTEGRAL do snapshot, por bytes, antes de qualquer Docker/Supabase.
    foreach ($operation in $ordered) {
        $target = Join-Path $ProjectRoot ($operation.Path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if ($operation.Operation -eq 'delete') {
            if (Test-Path -LiteralPath $target) { throw "Falha ao remover path do snapshot: $($operation.Path)" }
            continue
        }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Path materializado ausente: $($operation.Path)" }
        if ((Get-Item -LiteralPath $target).Length -ne $operation.Size) { throw "Tamanho divergente no snapshot: $($operation.Path)" }
        if ((Get-DisposableSha256 -Path $target) -ne $operation.Sha256) { throw "Hash divergente no snapshot: $($operation.Path)" }
    }

    $migrations = Assert-DisposableSnapshotMigrations -ProjectRoot (Join-Path $ProjectRoot 'supabase') -BaselineMigrationNames $baselineMigrations

    # Fingerprint DETERMINISTICO do snapshot INTEGRAL (baseline + bytes finais do
    # candidato), por path|tamanho|SHA-256 ordenado. A transformacao controlada
    # de config.toml acontece DEPOIS e e registrada separadamente.
    $snapshotFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($root in $script:DisposableCandidateRoots) {
        $rootPath = Join-Path $ProjectRoot $root
        if (Test-Path -LiteralPath $rootPath -PathType Container) {
            foreach ($file in Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force) { $snapshotFiles.Add($file) }
        }
    }
    foreach ($name in $script:DisposableCandidateApplicationFiles) {
        $file = Join-Path $ProjectRoot $name
        if (Test-Path -LiteralPath $file -PathType Leaf) { $snapshotFiles.Add((Get-Item -LiteralPath $file -Force)) }
    }
    $canonical = (($snapshotFiles | ForEach-Object {
        "$(Get-DisposableRelativePath -Root $ProjectRoot -FullName $_.FullName)|$($_.Length)|$(Get-DisposableSha256 -Path $_.FullName)"
    }) | Sort-Object) -join "`n"
    $fingerprintSha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = ([BitConverter]::ToString($fingerprintSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))) -replace '-', '').ToLowerInvariant()
    } finally { $fingerprintSha.Dispose() }

    return [pscustomobject]@{
        Mode                 = 'CandidateWorktree'
        BaselineCommit       = $BaselineCommit
        Candidate            = [pscustomobject]@{
            Path   = $CandidateWorktree
            Head   = $BaselineCommit
            Branch = $CandidateBranch
        }
        Policy               = [pscustomobject]@{
            AllowlistRoots     = @($script:DisposableCandidateRoots)
            ApplicationFiles   = @($script:DisposableCandidateApplicationFiles)
            ForbiddenPattern   = $script:DisposableForbiddenRelativePattern
            AllowedEnvTemplates = @($script:DisposableEnvTemplateNames)
        }
        Operations           = $ordered
        HistoricalMigrations = $migrations.Historical
        NewMigrations        = $migrations.New
        RequiredMigration    = '20261018000000_f6_404_evaluation_mutation_bundles.sql'
        SnapshotFileCount    = $snapshotFiles.Count
        SnapshotFingerprint  = $fingerprint
    }
}
