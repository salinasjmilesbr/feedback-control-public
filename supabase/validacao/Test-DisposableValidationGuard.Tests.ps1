[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$guard = Join-Path $PSScriptRoot 'Test-DisposableValidationGuard.ps1'
. (Join-Path $PSScriptRoot 'DisposableValidationSafety.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "feedback-control-validation-guard-$PID"
$workdir = $null
$candidateWorkdir = $null
$dangerous = $null
$crlfWorkdir = $null
function Invoke-GuardFixture {
    param([hashtable]$Files, [bool]$ShouldPass, [string]$Name)
    $fixture = Join-Path $testRoot $Name
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    foreach ($entry in $Files.GetEnumerator()) { $path = Join-Path $fixture $entry.Key; New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null; Set-Content -LiteralPath $path -Value $entry.Value -Encoding UTF8 -NoNewline }
    $passed = $true; try { & $guard -Root $fixture } catch { $passed = $false; $failure = $_.Exception.Message }
    if (-not $passed) { Write-Host "Guard output ($Name): $failure" }
    if ($passed -ne $ShouldPass) { throw "FAIL: $Name" }; Write-Host "PASS: $Name"
}
function Add-FixtureCommit {
    param([string]$RepoRoot, [string]$Message, [scriptblock]$Changes)
    & $Changes $RepoRoot
    git -C $RepoRoot -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m $Message
    if ($LASTEXITCODE -ne 0) { throw "FAIL: commit de fixture: $Message" }
    return (git -C $RepoRoot rev-parse HEAD)
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
    if ($runnerText -notmatch '\[string\]\$TargetCommit' -or
        $runnerText -notmatch "TargetCommit exige o modo Interactive" -or
        $runnerText -notmatch "Assert-DisposableTargetCommit -RepoRoot \`$repoRoot" -or
        $runnerText -notmatch "Commit \`$baselineCommit" -or
        $runnerText -notmatch "Commit \`$TargetCommit" -or
        $runnerText -notmatch 'Export-DisposableCommitPaths -RepoRoot \$repoRoot -Commit \$baselineCommit[^\r\n]*`[\r\n]+\s*-ProjectRoot \$validationRoot -Paths @\(.supabase.\)' -or
        $runnerText -notmatch 'Export-DisposableCommitPaths -RepoRoot \$repoRoot -Commit \$TargetCommit[^\r\n]*`[\r\n]+\s*-ProjectRoot \$validationRoot -Paths \(@\(.src., .public.\) \+ \$applicationFiles\)' -or
        $runnerText -notmatch [regex]::Escape("aplicacao candidata: `$TargetCommit")) {
        throw 'FAIL: wiring de TargetCommit ausente ou divergente no runner.'
    }
    $targetGuardIndex = $runnerText.IndexOf('Assert-DisposableTargetCommit -RepoRoot')
    $startIndex = $runnerText.IndexOf('Invoke-Checked $cli ($cliArgs + @(''start''))')
    if ($targetGuardIndex -lt 0 -or $startIndex -lt 0 -or $targetGuardIndex -ge $startIndex) {
        throw 'FAIL: o guard de TargetCommit precisa preceder qualquer start do stack descartavel.'
    }
    $workdirIndex = $runnerText.IndexOf('New-Item -ItemType Directory -Path $validationRoot')
    if ($workdirIndex -lt 0 -or $targetGuardIndex -ge $workdirIndex) {
        throw 'FAIL: o guard de TargetCommit precisa preceder a criacao do workdir descartavel.'
    }
    # Ancoras sao trechos de chamada (definicoes de funcao vem antes das chamadas).
    $orderedMarkers = @(
        '$baselineCommit = Assert-InteractiveMainCheckout',
        'Assert-DisposableTargetCommit -RepoRoot $repoRoot',
        '-Ports @(55420, 55421, 55422, 55423)',
        'New-Item -ItemType Directory -Path $validationRoot',
        'Export-DisposableCommitPaths -RepoRoot $repoRoot -Commit $baselineCommit',
        'Export-DisposableCommitPaths -RepoRoot $repoRoot -Commit $TargetCommit',
        'Assert-DisposableExportedTree -RepoRoot $repoRoot -Commit $baselineCommit',
        'Assert-DisposableExportedTree -RepoRoot $repoRoot -Commit $TargetCommit',
        'Assert-DisposableExportedFiles -RepoRoot $repoRoot -Commit $TargetCommit',
        'Assert-DisposableSourceCopyWithoutTemp -ProjectRoot $validationProjectRoot',
        'Invoke-Checked $cli ($cliArgs + @(''start''))'
    )
    $previousIndex = -1
    foreach ($marker in $orderedMarkers) {
        $index = $runnerText.IndexOf($marker)
        if ($index -lt 0 -or $index -le $previousIndex) {
            throw "FAIL: ordem das chamadas do runner diverge em [$marker]."
        }
        $previousIndex = $index
    }
    Write-Host 'PASS: ordem baseline -> TargetCommit -> recursos/portas -> materializacao -> verificacao -> start.'
    $baselineExportIndex = $runnerText.IndexOf('-Commit $baselineCommit')
    $targetExportIndex = $runnerText.IndexOf('-Commit $TargetCommit')
    if ($baselineExportIndex -lt 0 -or $targetExportIndex -lt 0 -or $baselineExportIndex -ge $targetExportIndex) {
        throw 'FAIL: Supabase baseline deve ser materializada antes da aplicacao candidata.'
    }
    Write-Host 'PASS: TargetCommit opt-in, separacao baseline/candidato e guard antes do start.'
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

    $candidateRepo = Join-Path $testRoot 'candidate-repo'
    New-Item -ItemType Directory -Path (Join-Path $candidateRepo 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $candidateRepo 'public') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $candidateRepo 'supabase/.temp/start-secrets') -Force | Out-Null
    git -C $candidateRepo init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: git init da fixture.' }
    Set-Content -LiteralPath (Join-Path $candidateRepo 'src/marker.txt') -Value 'antigo' -NoNewline
    Set-Content -LiteralPath (Join-Path $candidateRepo 'public/asset.txt') -Value 'asset' -NoNewline
    Set-Content -LiteralPath (Join-Path $candidateRepo 'supabase/config.toml') -Value 'main' -NoNewline
    git -C $candidateRepo add -- src public supabase/config.toml
    git -C $candidateRepo -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m antigo
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: commit antigo da fixture.' }
    $oldCommit = git -C $candidateRepo rev-parse HEAD
    Set-Content -LiteralPath (Join-Path $candidateRepo 'src/marker.txt') -Value 'baseline' -NoNewline
    git -C $candidateRepo add -- src/marker.txt
    git -C $candidateRepo -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m baseline
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: commit baseline da fixture.' }
    $baseCommit = git -C $candidateRepo rev-parse HEAD
    Set-Content -LiteralPath (Join-Path $candidateRepo 'src/marker.txt') -Value 'candidato' -NoNewline
    git -C $candidateRepo add -- src/marker.txt
    git -C $candidateRepo -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m candidato
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: commit candidato da fixture.' }
    $validCommit = git -C $candidateRepo rev-parse HEAD
    $candidateSupabaseExpected = git -C $candidateRepo rev-parse "${baseCommit}:supabase"
    $manifest = Assert-DisposableTargetCommit -RepoRoot $candidateRepo -BaselineCommit $baseCommit -TargetCommit $validCommit
    if ($manifest.BaselineCommit -ne $baseCommit -or $manifest.TargetCommit -ne $validCommit -or
        $manifest.BaselineSupabaseTree -ne (git -C $candidateRepo rev-parse "${baseCommit}:supabase") -or
        $manifest.CandidateSrcTree -ne (git -C $candidateRepo rev-parse "${validCommit}:src")) {
        throw 'FAIL: manifesto do candidato incorreto.'
    }
    Write-Host 'PASS: SHA valido aceito com manifesto baseline/candidato.'
    $abbreviated = $validCommit.Substring(0, 8)
    $shaMessage = 'TargetCommit e baseline exigem SHA completo.'
    $expected = [pscustomobject]@{ target = $abbreviated; message = $shaMessage }
    $denied = $false
    try { $null = Assert-DisposableTargetCommit -RepoRoot $candidateRepo -BaselineCommit $baseCommit -TargetCommit $expected.target } catch { $denied = $_.Exception.Message -eq $expected.message }
    if (-not $denied) { throw 'FAIL: SHA abreviado aceito ou falhou por mensagem alheia ao guard.' }
    Write-Host 'PASS: SHA abreviado rejeitado.'
    foreach ($invalid in @('invalido', ('z' * 40), ('0' * 39), $validCommit.ToUpperInvariant(), $abbreviated + 'zzzz')) {
        $denied = $false
        try { $null = Assert-DisposableTargetCommit -RepoRoot $candidateRepo -BaselineCommit $baseCommit -TargetCommit $invalid } catch { $denied = $_.Exception.Message -eq $shaMessage }
        if (-not $denied) { throw "FAIL: TargetCommit invalido aceito (ou mensagem divergente): $invalid" }
    }
    Write-Host 'PASS: formatos invalidos rejeitados (nao-SHA, 39 caracteres, maiusculo, nao hexadecimal).'
    $expected = [pscustomobject]@{ target = ('f' * 40); message = 'TargetCommit inexistente ou nao e commit.' }
    $denied = $false
    try { $null = Assert-DisposableTargetCommit -RepoRoot $candidateRepo -BaselineCommit $baseCommit -TargetCommit $expected.target } catch { $denied = $_.Exception.Message -eq $expected.message }
    if (-not $denied) { throw 'FAIL: TargetCommit de 40 caracteres inexistente aceito.' }
    $expected = [pscustomobject]@{ target = ('f' * 40).ToUpperInvariant(); message = $shaMessage }
    $denied = $false
    try { $null = Assert-DisposableTargetCommit -RepoRoot $candidateRepo -BaselineCommit $baseCommit -TargetCommit $expected.target } catch { $denied = $_.Exception.Message -eq $expected.message }
    if (-not $denied) { throw 'FAIL: TargetCommit inexistente em maiusculo aceito.' }
    Write-Host 'PASS: SHA completo inexistente rejeitado.'
    $expected = [pscustomobject]@{ target = $oldCommit; message = 'TargetCommit nao inclui a main vigente.' }
    $denied = $false
    try { $null = Assert-DisposableTargetCommit -RepoRoot $candidateRepo -BaselineCommit $baseCommit -TargetCommit $expected.target } catch { $denied = $_.Exception.Message -eq $expected.message }
    if (-not $denied) { throw 'FAIL: candidato obsoleto (anterior a baseline) aceito.' }
    Write-Host 'PASS: candidato obsoleto que nao inclui a main rejeitado.'
    Set-Content -LiteralPath (Join-Path $candidateRepo 'supabase/config.toml') -Value 'alterado' -NoNewline
    git -C $candidateRepo add -- supabase/config.toml
    git -C $candidateRepo -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m incompativel
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: commit incompativel da fixture.' }
    $incompatibleCommit = git -C $candidateRepo rev-parse HEAD
    $incompatibleMessage = ''
    try { $null = Assert-DisposableTargetCommit -RepoRoot $candidateRepo -BaselineCommit $baseCommit -TargetCommit $incompatibleCommit } catch { $incompatibleMessage = $_.Exception.Message }
    if ($incompatibleMessage -ne 'TargetCommit altera Supabase; este modo exige a arvore da main.') {
        throw "FAIL: candidato que altera Supabase nao falhou pela mensagem do guard (mensagem: $incompatibleMessage)."
    }
    if ($manifest.BaselineSupabaseTree -ne $candidateSupabaseExpected) { throw 'FAIL: Supabase baseline incorreta no manifesto.' }
    Write-Host 'PASS: Supabase alterada no candidato rejeitada fail-closed.'

    $dangerousCandidate = Add-FixtureCommit -RepoRoot $candidateRepo -Message 'segredo' -Changes { param($repo) Set-Content -LiteralPath (Join-Path $repo 'supabase/.env.local') -Value 'fixture' -NoNewline; git -C $repo add -f -- supabase/.env.local }
    $dangerous = Join-Path ([IO.Path]::GetTempPath()) "feedback-control-validation-$($PID + 400000)"
    New-Item -ItemType Directory -Path $dangerous -Force | Out-Null
    Export-DisposableCommitPaths -RepoRoot $candidateRepo -Commit $dangerousCandidate -ProjectRoot $dangerous -Paths @('supabase')
    $dangerAccepted = $false
    try { Assert-DisposableExportedTree -RepoRoot $candidateRepo -Commit $dangerousCandidate -ProjectRoot $dangerous -Path 'supabase'; $dangerAccepted = $true } catch { }
    if ($dangerAccepted) { throw 'FAIL: snapshot com .env/segredo aceito.' }
    Write-Host 'PASS: snapshot com .env/segredo rejeitado pela arvore exportada.'

    $candidateWorkdir = Join-Path ([IO.Path]::GetTempPath()) "feedback-control-validation-$($PID + 300000)"
    New-Item -ItemType Directory -Path $candidateWorkdir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $candidateRepo 'src/untracked.txt') -Value 'fora do commit' -NoNewline
    Set-Content -LiteralPath (Join-Path $candidateRepo 'supabase/.temp/start-secrets/docker.env') -Value 'fixture' -NoNewline
    Export-DisposableCommitPaths -RepoRoot $candidateRepo -Commit $baseCommit -ProjectRoot $candidateWorkdir -Paths @('supabase')
    Export-DisposableCommitPaths -RepoRoot $candidateRepo -Commit $validCommit -ProjectRoot $candidateWorkdir -Paths @('src', 'public')
    Assert-DisposableExportedTree -RepoRoot $candidateRepo -Commit $baseCommit -ProjectRoot $candidateWorkdir -Path 'supabase'
    Assert-DisposableExportedTree -RepoRoot $candidateRepo -Commit $validCommit -ProjectRoot $candidateWorkdir -Path 'src'
    Assert-DisposableExportedTree -RepoRoot $candidateRepo -Commit $validCommit -ProjectRoot $candidateWorkdir -Path 'public'
    Assert-DisposableSourceCopyWithoutTemp -ProjectRoot (Join-Path $candidateWorkdir 'supabase')
    if ((Get-Content -LiteralPath (Join-Path $candidateWorkdir 'src/marker.txt') -Raw) -ne 'candidato' -or
        (Get-Content -LiteralPath (Join-Path $candidateWorkdir 'supabase/config.toml') -Raw) -ne 'main' -or
        (Test-Path -LiteralPath (Join-Path $candidateWorkdir 'src/untracked.txt')) -or
        (Test-Path -LiteralPath (Join-Path $candidateWorkdir 'supabase/.temp'))) {
        throw 'FAIL: snapshot misturou working tree, segredo ou Supabase candidata.'
    }
    Write-Host 'PASS: snapshot materializa Supabase baseline e src candidata sem estado local.'
    Set-Content -LiteralPath (Join-Path $candidateWorkdir 'src/extra.txt') -Value 'extra' -NoNewline
    $extraAccepted = $false
    try { Assert-DisposableExportedTree -RepoRoot $candidateRepo -Commit $validCommit -ProjectRoot $candidateWorkdir -Path 'src'; $extraAccepted = $true } catch { }
    if ($extraAccepted) { throw 'FAIL: arquivo extra no workdir aceito.' }
    Remove-Item -LiteralPath (Join-Path $candidateWorkdir 'src/extra.txt') -Force
    Write-Host 'PASS: arquivo extra no workdir descartavel rejeitado.'

    $oldHead = git -C $candidateRepo rev-parse HEAD
    git -C $candidateRepo checkout --quiet $validCommit
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: checkout da fixture para o candidato valido.' }
    git -C $candidateRepo rm -r --quiet --cached src
    Remove-Item -LiteralPath (Join-Path $candidateRepo 'src/untracked.txt') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $candidateRepo 'src') -Recurse -Force
    git -C $candidateRepo -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m sem-src
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: commit sem src da fixture.' }
    $noSrcCommit = git -C $candidateRepo rev-parse HEAD
    $noSrcMessage = ''
    try { $null = Assert-DisposableTargetCommit -RepoRoot $candidateRepo -BaselineCommit $baseCommit -TargetCommit $noSrcCommit } catch { $noSrcMessage = $_.Exception.Message }
    if ($noSrcMessage -ne 'Commit de referencia sem hash de arvore unico e valido.') {
        throw "FAIL: candidato sem src nao falhou pela mensagem do guard (mensagem: $noSrcMessage)."
    }
    git -C $candidateRepo checkout --quiet $oldHead
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: restauracao do HEAD da fixture.' }
    Write-Host 'PASS: candidato sem codigo de aplicacao (src) rejeitado fail-closed.'

    # Regressao (smoke real, supabase/.gitignore): `git archive` honra
    # `core.autocrlf` e grava LF->CRLF no ZIP, o que fazia a prova de identidade
    # (`hash-object --no-filters`) divergir do blob sem qualquer mudanca real.
    git -C $candidateRepo config core.autocrlf true
    $multiLinha = Join-Path $candidateRepo 'src/multilinha.txt'
    [System.IO.File]::WriteAllText($multiLinha, "linha-um`nlinha-dois`nlinha-tres`n", (New-Object System.Text.UTF8Encoding($false)))
    git -C $candidateRepo add -- src/multilinha.txt
    git -C $candidateRepo -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m multilinha
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: commit multilinha da fixture.' }
    $multilinhaCommit = git -C $candidateRepo rev-parse HEAD
    $multilinhaOid = git -C $candidateRepo rev-parse "${multilinhaCommit}:src/multilinha.txt"
    $multilinhaBlobSize = [int](git -C $candidateRepo cat-file -s $multilinhaOid)
    $crlfWorkdir = Join-Path ([IO.Path]::GetTempPath()) "feedback-control-validation-$($PID + 500000)"
    New-Item -ItemType Directory -Path $crlfWorkdir -Force | Out-Null
    Export-DisposableCommitPaths -RepoRoot $candidateRepo -Commit $multilinhaCommit -ProjectRoot $crlfWorkdir -Paths @('src')
    Assert-DisposableExportedTree -RepoRoot $candidateRepo -Commit $multilinhaCommit -ProjectRoot $crlfWorkdir -Path 'src'
    $materializado = [System.IO.File]::ReadAllBytes((Join-Path $crlfWorkdir 'src/multilinha.txt'))
    if ($materializado.Length -ne $multilinhaBlobSize) {
        throw "FAIL: materializacao alterou o tamanho do arquivo ($($materializado.Length) != $multilinhaBlobSize)."
    }
    if (@($materializado | Where-Object { $_ -eq 13 }).Count -ne 0) {
        throw 'FAIL: materializacao introduziu CR (conversao de EOL).'
    }
    Write-Host 'PASS: materializacao preserva os bytes do blob mesmo com core.autocrlf=true.'

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
    if ($null -ne $candidateWorkdir -and (Test-Path -LiteralPath $candidateWorkdir)) {
        Assert-DisposableValidationWorkdir -Workdir $candidateWorkdir -TempRoot ([IO.Path]::GetTempPath().TrimEnd('\'))
        Remove-Item -LiteralPath $candidateWorkdir -Recurse -Force
    }
    if ($null -ne $dangerous -and (Test-Path -LiteralPath $dangerous)) {
        Assert-DisposableValidationWorkdir -Workdir $dangerous -TempRoot ([IO.Path]::GetTempPath().TrimEnd('\'))
        Remove-Item -LiteralPath $dangerous -Recurse -Force
    }
    if ($null -ne $crlfWorkdir -and (Test-Path -LiteralPath $crlfWorkdir)) {
        Assert-DisposableValidationWorkdir -Workdir $crlfWorkdir -TempRoot ([IO.Path]::GetTempPath().TrimEnd('\'))
        Remove-Item -LiteralPath $crlfWorkdir -Recurse -Force
    }
}
