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
