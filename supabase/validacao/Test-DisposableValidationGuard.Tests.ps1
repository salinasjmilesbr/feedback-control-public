[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$guard = Join-Path $PSScriptRoot 'Test-DisposableValidationGuard.ps1'
. (Join-Path $PSScriptRoot 'DisposableValidationSafety.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "feedback-control-validation-guard-$PID"
function Invoke-GuardFixture {
    param([hashtable]$Files, [bool]$ShouldPass, [string]$Name)
    $fixture = Join-Path $testRoot $Name
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    foreach ($entry in $Files.GetEnumerator()) { $path = Join-Path $fixture $entry.Key; New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null; Set-Content -LiteralPath $path -Value $entry.Value -Encoding UTF8 -NoNewline }
    $passed = $true; try { & $guard -Root $fixture } catch { $passed = $false; $failure = $_.Exception.Message }
    if (-not $passed) { Write-Host "Guard output ($Name): $failure" }
    if ($passed -ne $ShouldPass) { throw "FAIL: $Name" }; Write-Host "PASS: $Name"
}
try {
    $directReset = 'npx --yes supabase@2.116.0 db ' + 'reset --local --yes'
    Invoke-GuardFixture @{ 'gate.ps1' = $directReset } $false 'root-reset-fails'
    Invoke-GuardFixture @{ 'supabase/validacao/Invoke-DisposableValidation.ps1' = "Assert-DisposableValidationTarget`n`$cliArgs = @('--yes', 'supabase@2.116.0', '--workdir', `$validationRoot)`n$directReset" } $true 'runner-passes'
    Invoke-GuardFixture @{ '.github/workflows/ci.yml' = "# disposable-validation-guard: isolated-github-runner`nruns-on: ubuntu-latest`nrun: $directReset" } $true 'isolated-ci-passes'
    $workdir = Join-Path ([IO.Path]::GetTempPath()) 'feedback-control-validation-99999'; New-Item -ItemType Directory -Path $workdir -Force | Out-Null
    $config = "project_id = `"feedback-control-validation`"`n[api]`nport = 55421`n[db]`nport = 55422`nshadow_port = 55420`n[studio]`nport = 55423"
    $copySource = Join-Path $testRoot 'copy-source'
    $copyTarget = Join-Path $testRoot 'copy-target'
    $fakeSecretsDir = Join-Path $copySource '.temp/start-secrets'
    New-Item -ItemType Directory -Path $fakeSecretsDir -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $fakeSecretsDir 'docker.env') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $copySource 'migrations') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $copySource 'migrations/fixture.sql') -Force | Out-Null
    Copy-DisposableSupabaseSource -SourceRoot $copySource -TargetRoot $copyTarget
    if (-not (Test-Path -LiteralPath (Join-Path $copyTarget 'migrations/fixture.sql')) -or
        (Test-Path -LiteralPath (Join-Path $copyTarget '.temp')) -or
        (Test-Path -LiteralPath (Join-Path $copyTarget '.temp/start-secrets/docker.env'))) {
        throw 'FAIL: copia descartavel incluiu estado local ou perdeu migration.'
    }
    Write-Host 'PASS: copia inclui migration e exclui .temp/start-secrets/docker.env sintetico.'
    New-Item -ItemType Directory -Path (Join-Path $copyTarget '.temp') -Force | Out-Null
    $tempAccepted = $false
    try { Assert-DisposableSourceCopyWithoutTemp -ProjectRoot $copyTarget; $tempAccepted = $true } catch { }
    if ($tempAccepted) { throw 'FAIL: guard aceitou .temp na copia.' }
    Write-Host 'PASS: guard rejeita .temp no workdir.'
    try { Assert-DisposableValidationTarget -Workdir $workdir -TempRoot ([IO.Path]::GetTempPath().TrimEnd('\')) -ProjectId 'feedback-control-validation' -ContainerName 'supabase_db_feedback-control' -RuntimeContainerName 'supabase_db_feedback-control' -Config $config; throw 'FAIL: runtime container fails' } catch { if ($_.Exception.Message -eq 'FAIL: runtime container fails') { throw }; Write-Host 'PASS: runtime container fails' }
    Assert-NoDisposableResourceNames -Containers @('supabase_db_feedback-control') -Volumes @('supabase_db_feedback-control') -Networks @('supabase_network_feedback-control')
    foreach ($resource in @('supabase_db_feedback-control-validation', 'supabase_edge_runtime_feedback-control-validation', 'supabase_network_feedback-control-validation')) {
        try { Assert-NoDisposableResourceNames -Containers @($resource); throw "FAIL: $resource" }
        catch { if ($_.Exception.Message -eq "FAIL: $resource") { throw }; Write-Host "PASS: preexisting $resource fails closed" }
    }
    $migration404 = '20261018000000_f6_404_evaluation_mutation_bundles.sql'
    Assert-DisposableEvaluationMigrations -MigrationFiles @($migration404) -AppliedVersions @('20261018000000')
    Write-Host 'PASS: #404 presente e aplicada; #414 ausente.'
    foreach ($case in @(
        @{ Files = @(); Versions = @(); Name = 'missing-404-file' },
        @{ Files = @($migration404, '20261019000000_f6_414_company_admin_lifecycle.sql'); Versions = @(); Name = '414-file' },
        @{ Files = @($migration404); Versions = @(); Name = 'missing-404-version' },
        @{ Files = @($migration404); Versions = @('20261018000000', '20261025000000'); Name = '414-version' }
    )) {
        try {
            Assert-DisposableEvaluationMigrations -MigrationFiles $case.Files -AppliedVersions $case.Versions
            throw "FAIL: $($case.Name)"
        } catch {
            if ($_.Exception.Message -eq "FAIL: $($case.Name)") { throw }
            Write-Host "PASS: $($case.Name) fails closed"
        }
    }
    $runnerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-DisposableValidation.ps1') -Raw -Encoding UTF8
    if ($runnerText -notmatch '\[switch\]\$Interactive' -or $runnerText -notmatch 'if \(\$Interactive\)' -or $runnerText -notmatch "Read-Host 'Comando de encerramento'" -or $runnerText -notmatch 'Invoke-DisposableInteractiveCleanup') {
        throw 'FAIL: contrato interativo/cleanup ausente no runner.'
    }
    Write-Host 'PASS: modo interativo opt-in e cleanup explicito presentes.'
    Assert-DisposableMainState -Branch 'main' -Head 'abc' -OriginMain 'abc' -RelevantStatus @()
    foreach ($case in @(
        @{ Branch = 'feature'; Head = 'abc'; OriginMain = 'abc'; Status = @() },
        @{ Branch = 'main'; Head = 'abc'; OriginMain = 'def'; Status = @() },
        @{ Branch = 'main'; Head = 'abc'; OriginMain = 'abc'; Status = @(' M supabase/config.toml') }
    )) {
        $denied = $false
        try { Assert-DisposableMainState -Branch $case.Branch -Head $case.Head -OriginMain $case.OriginMain -RelevantStatus $case.Status } catch { $denied = $true }
        if (-not $denied) { throw 'FAIL: checkout interativo inseguro foi aceito.' }
    }
    Write-Host 'PASS: main/origin/main/fontes locais guardados.'

    $occupied = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 0)
    $occupied.Start()
    $occupiedPort = $occupied.LocalEndpoint.Port
    try {
        $denied = $false
        try { Assert-DisposablePortsAvailable -Ports @($occupiedPort) } catch { $denied = $true }
        if (-not $denied) { throw 'FAIL: porta ocupada aceita.' }
    } finally { $occupied.Stop() }
    Assert-DisposablePortsAvailable -Ports @($occupiedPort)
    Write-Host 'PASS: preflight de portas ocupadas/livres.'

    $safetyPath = Join-Path $PSScriptRoot 'DisposableValidationSafety.ps1'
    $lock = Enter-DisposableValidationLock -TempRoot $testRoot
    try {
        $job = Start-Job -ScriptBlock {
            param($Path, $Root)
            . $Path
            try { $other = Enter-DisposableValidationLock -TempRoot $Root; $other.Dispose(); 'ACQUIRED' }
            catch { 'BUSY' }
        } -ArgumentList $safetyPath, $testRoot
        try {
            $null = Wait-Job $job -Timeout 15
            if ($job.State -ne 'Completed' -or (Receive-Job $job) -ne 'BUSY') { throw 'FAIL: lock concorrente nao excluiu segunda sessao.' }
        } finally { Remove-Job $job -Force }
    } finally { $lock.Dispose() }
    $job = Start-Job -ScriptBlock {
        param($Path, $Root)
        . $Path
        try { $other = Enter-DisposableValidationLock -TempRoot $Root; $other.Dispose(); 'ACQUIRED' }
        catch { 'BUSY' }
    } -ArgumentList $safetyPath, $testRoot
    try {
        $null = Wait-Job $job -Timeout 15
        if ($job.State -ne 'Completed' -or (Receive-Job $job) -ne 'ACQUIRED') { throw 'FAIL: lock nao foi liberado no finally.' }
    } finally { Remove-Job $job -Force }
    Write-Host 'PASS: lock exclusivo entre processos e liberacao segura.'

    $containerId = 'fixture-container-id'
    $ownedContainer = [pscustomobject]@{
        Id = $containerId
        Name = '/supabase_db_feedback-control-validation'
        Config = [pscustomobject]@{ Labels = [pscustomobject]@{ 'com.supabase.cli.project' = 'feedback-control-validation'; 'com.supabase.cli.workdir' = $workdir } }
        Mounts = @([pscustomobject]@{ Name = 'supabase_db_feedback-control-validation' })
        NetworkSettings = [pscustomobject]@{ Networks = [pscustomobject]@{ 'supabase_network_feedback-control-validation' = [pscustomobject]@{} } }
    }
    $ownedVolume = [pscustomobject]@{ Name = 'supabase_db_feedback-control-validation'; Labels = [pscustomobject]@{ 'com.supabase.cli.project' = 'feedback-control-validation' } }
    $ownedNetwork = [pscustomobject]@{ Name = 'supabase_network_feedback-control-validation'; Containers = [pscustomobject]@{ 'fixture-container-id' = [pscustomobject]@{} } }
    Assert-DisposableResourceOwnership -Container $ownedContainer -Volume $ownedVolume -Network $ownedNetwork -Workdir $workdir
    foreach ($invalid in @(
        @{ Container = $ownedContainer; Volume = $ownedVolume; Network = $ownedNetwork; Workdir = 'wrong-workdir' },
        @{ Container = $ownedContainer; Volume = ([pscustomobject]@{ Name = 'supabase_db_feedback-control'; Labels = $ownedVolume.Labels }); Network = $ownedNetwork; Workdir = $workdir },
        @{ Container = $ownedContainer; Volume = $ownedVolume; Network = ([pscustomobject]@{ Name = $ownedNetwork.Name; Containers = [pscustomobject]@{} }); Workdir = $workdir }
    )) {
        $denied = $false
        try { Assert-DisposableResourceOwnership -Container $invalid.Container -Volume $invalid.Volume -Network $invalid.Network -Workdir $invalid.Workdir } catch { $denied = $true }
        if (-not $denied) { throw 'FAIL: recurso sem ownership aceito.' }
    }
    Write-Host 'PASS: ownership de container, volume, rede e workdir.'
    foreach ($failure in @('erro', 'interrupcao')) {
        $cleanupWorkdir = Join-Path ([IO.Path]::GetTempPath()) "feedback-control-validation-$($PID + $(if ($failure -eq 'erro') { 100000 } else { 200000 }))"
        $cleanupProject = Join-Path $cleanupWorkdir 'supabase'
        New-Item -ItemType Directory -Path $cleanupProject -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $cleanupProject 'config.toml') -Value $config -Encoding UTF8 -NoNewline
        $calls = [pscustomobject]@{ Stop = 0; Ownership = 0 }
        try {
            try {
                if ($failure -eq 'erro') { throw 'erro sintetico apos start' }
                throw [System.OperationCanceledException]::new('interrupcao sintetica')
            } finally {
                Invoke-DisposableInteractiveCleanup -Workdir $cleanupWorkdir -TempRoot ([IO.Path]::GetTempPath().TrimEnd('\')) `
                    -ProjectId 'feedback-control-validation' -ContainerName 'supabase_db_feedback-control-validation' `
                    -RuntimeContainerName 'supabase_db_feedback-control' -StartAttempted $true `
                    -GetContainers { 'supabase_db_feedback-control-validation' } `
                    -AssertOwnership { $calls.Ownership++ } -StopStack { $calls.Stop++ }
            }
        } catch {
            if ($_.Exception.Message -notmatch 'sintetic') { throw }
        }
        if ((Test-Path -LiteralPath $cleanupWorkdir) -or $calls.Stop -ne 1 -or $calls.Ownership -ne 1) {
            throw "FAIL: cleanup apos $failure"
        }
        Write-Host "PASS: cleanup apos $failure, com ownership antes de stop."
    }
    & $guard -Root $repoRoot
    Write-Host 'PASS: guard repository and targeted fixtures.'
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    if ($null -ne $workdir -and (Test-Path -LiteralPath $workdir)) {
        Assert-DisposableValidationWorkdir -Workdir $workdir -TempRoot ([IO.Path]::GetTempPath().TrimEnd('\'))
        Remove-Item -LiteralPath $workdir -Recurse -Force
    }
}
