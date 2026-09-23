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

function Assert-DisposableValidationTarget {
    param([string]$Workdir, [string]$TempRoot, [string]$ProjectId, [string]$ContainerName, [string]$RuntimeContainerName, [string]$Config)

    $resolvedWorkdir = (Resolve-Path -LiteralPath $Workdir -ErrorAction Stop).Path
    $resolvedTempRoot = (Resolve-Path -LiteralPath $TempRoot -ErrorAction Stop).Path
    if ((Split-Path -Parent $resolvedWorkdir) -ne $resolvedTempRoot -or (Split-Path -Leaf $resolvedWorkdir) -notmatch '^feedback-control-validation-\d+$') {
        throw 'Workdir descartavel inseguro: esperado diretorio temporario feedback-control-validation-<PID>.'
    }
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
