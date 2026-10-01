[CmdletBinding()]
param()

# ============================================================================
# Testes do modo CandidateWorktree (contrato fechado).
#
# Estaticos: NAO exigem Docker/Supabase. Cobrem staged/unstaged, add/delete/
# rename, untracked allowlisted, migration historica alterada/removida, migration
# nova/duplicada/invalida, #404/#414, segredo/.temp, ignored relevante, path
# inseguro, baseline divergente, bytes finais com core.autocrlf=true, e a
# exclusividade/opt-in dos modos. A regressao dos modos atuais roda no gate
# (Test-DisposableValidationGuard.Tests.ps1).
# ============================================================================

$ErrorActionPreference = 'Stop'
$psscriptRoot = $PSScriptRoot
$runner = Join-Path $psscriptRoot 'Invoke-DisposableValidation.ps1'
. (Join-Path $psscriptRoot 'DisposableValidationSafety.ps1')

$tempRoot = [IO.Path]::GetTempPath().TrimEnd('\')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) "feedback-control-candidate-tests-$PID"
Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$script:workdirCounter = 80000
$script:fixtureCounter = 0

function New-CandidateFixture {
    param([string]$Name, [string[]]$ExtraGitignore = @())

    $script:fixtureCounter = $script:fixtureCounter + 1
    $root = Join-Path $testRoot $Name
    $repo = Join-Path $root 'infra'
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    git -C $repo init --quiet --initial-branch=main
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: git init do fixture.' }
    $files = @{
        'supabase/config.toml'                                              = "project_id = `"feedback-control`"`n[api]`nport = 54321`n[db]`nport = 54322`nshadow_port = 54320`n[studio]`nport = 54323`n[local_smtp]`nenabled = true`n"
        'supabase/migrations/20261018000000_f6_404_evaluation_mutation_bundles.sql' = "-- 404 baseline`nselect 1;`n"
        'supabase/seed.sql'                                                 = "-- seed`n"
        'src/app.ts'                                                        = "export const valor = 'baseline';`n"
        'src/legacy.ts'                                                     = "export const legacy = true;`n"
        'src/rename-me.ts'                                                  = "export const renomeado = 'antes';`n"
        'public/index.html'                                                 = "<html>baseline</html>`n"
        'index.html'                                                        = "<html>app</html>`n"
        'package.json'                                                      = "{`"name`": `"fixture`"}`n"
        'package-lock.json'                                                 = "{`"lockfileVersion`": 3}`n"
        'vite.config.ts'                                                    = "export default {};`n"
        'tsconfig.json'                                                     = "{ `"files`": [] }`n"
        'tsconfig.app.json'                                                 = "{ `"compilerOptions`": {} }`n"
        'tsconfig.node.json'                                                = "{ `"compilerOptions`": {} }`n"
        'eslint.config.js'                                                  = "export default [];`n"
    }
    if (@($ExtraGitignore).Count -gt 0) { $files['.gitignore'] = (($ExtraGitignore -join "`n") + "`n") }
    foreach ($entry in $files.GetEnumerator()) {
        $path = Join-Path $repo $entry.Key
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        Set-Content -LiteralPath $path -Value $entry.Value -Encoding UTF8 -NoNewline
    }
    git -C $repo -c user.name=Fixture -c user.email=fixture@example.test add -A
    git -C $repo -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -m 'baseline'
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: commit baseline do fixture.' }
    $baseline = (git -C $repo rev-parse HEAD).Trim()
    git -C $repo update-ref refs/remotes/origin/main $baseline
    $candidate = Join-Path $root 'candidate'
    git -C $repo worktree add --quiet --detach $candidate $baseline
    if ($LASTEXITCODE -ne 0) { throw 'FAIL: worktree do candidato.' }
    return [pscustomobject]@{ Root = $root; Repo = $repo; Candidate = $candidate; Baseline = $baseline }
}

function New-MaterializationWorkdir {
    $script:workdirCounter = $script:workdirCounter + 1
    $workdir = Join-Path ([IO.Path]::GetTempPath()) "feedback-control-validation-$($script:workdirCounter)"
    Remove-Item -LiteralPath $workdir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $workdir -Force | Out-Null
    return $workdir
}

function Invoke-Materialization {
    param($Fixture, [string]$Workdir = '')

    if ([string]::IsNullOrWhiteSpace($Workdir)) { $Workdir = New-MaterializationWorkdir }
    return Invoke-DisposableCandidateWorktreeMaterialization -RepoRoot $Fixture.Repo `
        -BaselineCommit $Fixture.Baseline -CandidateWorktree $Fixture.Candidate `
        -CandidateBranch 'feat/fixture' -ProjectRoot $Workdir
}

function Assert-FailsClosed {
    param([scriptblock]$Action, [string]$ExpectedMessage, [string]$Name)

    try {
        $null = & $Action
        throw "FAIL: $Name aceitou entrada invalida."
    } catch {
        $message = $_.Exception.Message
        if ($message -eq "FAIL: $Name aceitou entrada invalida.") { throw }
        if ($message -notlike "*$ExpectedMessage*") { throw "FAIL: $Name falhou com mensagem divergente: $message" }
    }
    Write-Host "PASS: $Name falha fechado."
}

function Set-CandidateFile {
    param([string]$Candidate, [string]$Relative, [string]$Value)

    $path = Join-Path $Candidate $Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    Set-Content -LiteralPath $path -Value $Value -Encoding UTF8 -NoNewline
}

try {
    # ------------------------------------------------------------------ positivo
    $fixture = New-CandidateFixture -Name 'positivo'
    $candidate = $fixture.Candidate
    Set-CandidateFile $candidate 'src/app.ts' "export const valor = 'candidato';`n"
    Set-CandidateFile $candidate 'src/staged.ts' "export const staged = true;`n"
    git -C $candidate add -- src/staged.ts
    Remove-Item -LiteralPath (Join-Path $candidate 'src/legacy.ts') -Force
    git -C $candidate mv -- src/rename-me.ts src/renamed.ts
    Set-CandidateFile $candidate 'src/untracked.ts' "export const untracked = true;`n"
    Set-CandidateFile $candidate 'supabase/migrations/20261027000000_f6_inc1_fronteiras_leitura.sql' "-- inc1`nselect 2;`n"
    Set-CandidateFile $candidate 'supabase/config.toml' "project_id = `"feedback-control`"`n[api]`nport = 54321`n[db]`nport = 54322`nshadow_port = 54320`n[studio]`nport = 54323`n[local_smtp]`nenabled = true`n# candidato`n"

    $workdir = New-MaterializationWorkdir
    $manifest = Invoke-Materialization -Fixture $fixture -Workdir $workdir
    $operations = @{}
    foreach ($operation in $manifest.Operations) { $operations[$operation.Path] = $operation }
    foreach ($expected in @(
        @{ Path = 'src/app.ts'; Operation = 'modify' },
        @{ Path = 'src/staged.ts'; Operation = 'add' },
        @{ Path = 'src/legacy.ts'; Operation = 'delete' },
        @{ Path = 'src/rename-me.ts'; Operation = 'delete' },
        @{ Path = 'src/renamed.ts'; Operation = 'add' },
        @{ Path = 'src/untracked.ts'; Operation = 'add' },
        @{ Path = 'supabase/config.toml'; Operation = 'modify' },
        @{ Path = 'supabase/migrations/20261027000000_f6_inc1_fronteiras_leitura.sql'; Operation = 'add' }
    )) {
        if (-not $operations.ContainsKey($expected.Path)) { throw "FAIL: operacao ausente no manifesto: $($expected.Path)" }
        if ($operations[$expected.Path].Operation -ne $expected.Operation) { throw "FAIL: operacao divergente em $($expected.Path): $($operations[$expected.Path].Operation)" }
    }
    Write-Host 'PASS: staged/unstaged/add/delete/rename/untracked/migration/config materializados com operacao correta.'
    if (-not (Test-Path -LiteralPath (Join-Path $workdir 'src/renamed.ts'))) { throw 'FAIL: rename nao materializado.' }
    if (Test-Path -LiteralPath (Join-Path $workdir 'src/rename-me.ts')) { throw 'FAIL: origem do rename permaneceu no snapshot.' }
    if (Test-Path -LiteralPath (Join-Path $workdir 'src/legacy.ts')) { throw 'FAIL: delete nao aplicado.' }
    $snapshotApp = Get-Content -LiteralPath (Join-Path $workdir 'src/app.ts') -Raw
    if ($snapshotApp -notlike "*candidato*") { throw 'FAIL: bytes finais do candidato nao aplicados.' }
    if ((Get-DisposableSha256 -Path (Join-Path $workdir 'src/app.ts')) -ne $operations['src/app.ts'].Sha256) { throw 'FAIL: hash do snapshot diverge do manifesto.' }
    if ($manifest.Candidate.Path -ne $candidate -or $manifest.Candidate.Head -ne $fixture.Baseline -or $manifest.BaselineCommit -ne $fixture.Baseline) { throw 'FAIL: manifesto sem baseline/candidato corretos.' }
    if ($manifest.SnapshotFingerprint -notmatch '^[0-9a-f]{64}$' -or $manifest.SnapshotFileCount -lt 1) { throw 'FAIL: fingerprint do snapshot ausente.' }
    if (@($manifest.HistoricalMigrations) -notcontains '20261018000000_f6_404_evaluation_mutation_bundles.sql') { throw 'FAIL: migration historica nao verificada.' }
    if (@($manifest.NewMigrations) -notcontains '20261027000000_f6_inc1_fronteiras_leitura.sql') { throw 'FAIL: migration nova nao identificada.' }
    Write-Host 'PASS: manifesto deterministico com baseline, candidato, hashes, migrations e fingerprint.'
    $manifestAgain = Invoke-Materialization -Fixture $fixture
    if ($manifestAgain.SnapshotFingerprint -ne $manifest.SnapshotFingerprint) { throw 'FAIL: fingerprint nao deterministico entre materializacoes.' }
    Write-Host 'PASS: fingerprint do snapshot e determinisitico (mesma entrada, mesmo hash).'

    # ------------------------------------------- bytes finais com autocrlf=true
    $crlfFixture = New-CandidateFixture -Name 'crlf'
    git -C $crlfFixture.Repo config core.autocrlf true
    $crlfCandidate = $crlfFixture.Candidate
    $crlfBytes = [Text.Encoding]::UTF8.GetBytes("export const crlf = 'x';`r`nexport const y = 2;`r`n")
    [IO.File]::WriteAllBytes((Join-Path $crlfCandidate 'src/app.ts'), $crlfBytes)
    $crlfWorkdir = New-MaterializationWorkdir
    $crlfManifest = Invoke-Materialization -Fixture $crlfFixture -Workdir $crlfWorkdir
    $materialized = [IO.File]::ReadAllBytes((Join-Path $crlfWorkdir 'src/app.ts'))
    if ([Convert]::ToBase64String($materialized) -ne [Convert]::ToBase64String($crlfBytes)) { throw 'FAIL: snapshot nao preservou os bytes finais com core.autocrlf=true.' }
    if (@($crlfManifest.Operations | Where-Object { $_.Path -eq 'src/app.ts' }).Count -ne 1) { throw 'FAIL: alteracao CRLF nao inventariada.' }
    Write-Host 'PASS: core.autocrlf=true preserva os bytes finais do candidato (sem conversao de EOL).'

    # ------------------------------------------------------- baseline divergente
    $divergent = New-CandidateFixture -Name 'divergente'
    Set-CandidateFile $divergent.Candidate 'src/app.ts' "export const valor = 'x';`n"
    git -C $divergent.Candidate -c user.name=Fixture -c user.email=fixture@example.test commit --quiet -am 'commit no candidato'
    Assert-FailsClosed -Name 'baseline divergente (HEAD <> origin/main)' -ExpectedMessage 'diverge do baseline' -Action {
        Assert-DisposableCandidateWorktreeCheckout -RepoRoot $divergent.Repo -CandidateWorktree $divergent.Candidate
    }

    # ------------------------------------------------------------- path inseguro
    $unsafe = New-CandidateFixture -Name 'inseguro'
    Set-CandidateFile $unsafe.Candidate '.env.local' "SEGREDO=1`n"
    Assert-FailsClosed -Name 'segredo .env* no candidato' -ExpectedMessage 'proibido' -Action { Invoke-Materialization -Fixture $unsafe }
    $tempState = New-CandidateFixture -Name 'temp-state'
    Set-CandidateFile $tempState.Candidate 'supabase/.temp/estado.txt' "estado local`n"
    Assert-FailsClosed -Name 'supabase/.temp no candidato' -ExpectedMessage 'proibido' -Action { Invoke-Materialization -Fixture $tempState }
    # Path FORA da allowlist: NAO e materializado (semantica de allowlist) e nao
    # entra no inventario — o snapshot certifica apenas src/public/supabase/app.
    $outsideAllowlist = New-CandidateFixture -Name 'fora-allowlist'
    Set-CandidateFile $outsideAllowlist.Candidate 'scripts/pwn.ps1' "Write-Host 'x'`n"
    Set-CandidateFile $outsideAllowlist.Candidate 'src/app.ts' "export const valor = 'allowlist';`n"
    $outsideWorkdir = New-MaterializationWorkdir
    $outsideManifest = Invoke-Materialization -Fixture $outsideAllowlist -Workdir $outsideWorkdir
    if (Test-Path -LiteralPath (Join-Path $outsideWorkdir 'scripts/pwn.ps1')) { throw 'FAIL: path fora da allowlist foi materializado.' }
    if (@($outsideManifest.Operations | Where-Object { $_.Path -like 'scripts/*' }).Count -ne 0) { throw 'FAIL: path fora da allowlist entrou no inventario.' }
    Write-Host 'PASS: path fora da allowlist nao entra no inventario nem no snapshot.'
    # Path PROIBIDO dentro da allowlist: reprova fail-closed.
    $forbiddenInside = New-CandidateFixture -Name 'proibido-dentro'
    Set-CandidateFile $forbiddenInside.Candidate 'src/node_modules/pwn.js' "module.exports = 1;`n"
    Assert-FailsClosed -Name 'node_modules dentro da allowlist' -ExpectedMessage 'proibido' -Action { Invoke-Materialization -Fixture $forbiddenInside }

    # ------------------------------------------------------------ ignored relevante
    # Path IGNORADO nao proibido: nao entra no inventario nem no snapshot.
    $ignored = New-CandidateFixture -Name 'ignored' -ExtraGitignore @('src/gerado.local')
    Set-CandidateFile $ignored.Candidate 'src/gerado.local' "gerado`n"
    Set-CandidateFile $ignored.Candidate 'src/app.ts' "export const valor = 'ignorado-ok';`n"
    $ignoredWorkdir = New-MaterializationWorkdir
    $ignoredManifest = Invoke-Materialization -Fixture $ignored -Workdir $ignoredWorkdir
    foreach ($path in @('src/gerado.local')) {
        if (Test-Path -LiteralPath (Join-Path $ignoredWorkdir $path)) { throw "FAIL: path ignorado foi materializado: $path" }
        if (@($ignoredManifest.Operations | Where-Object { $_.Path -eq $path }).Count -ne 0) { throw "FAIL: path ignorado entrou no inventario: $path" }
    }
    Write-Host 'PASS: arquivo ignorado relevante NAO entra no inventario nem no snapshot.'

    # ------------------- hotfix: templates .env* permitidos / segredos negados
    # (regra UNICA de nome aplicada por varredura de raiz, varredura recursiva,
    # inventario e materializacao)
    $templates = New-CandidateFixture -Name 'env-templates'
    foreach ($template in @('.env.example', '.env.sample', '.env.template')) {
        Set-CandidateFile $templates.Candidate $template "TEMPLATE=1`n"
    }
    Set-CandidateFile $templates.Candidate 'src/app.ts' "export const valor = 'templates';`n"
    $templatesWorkdir = New-MaterializationWorkdir
    $templatesManifest = Invoke-Materialization -Fixture $templates -Workdir $templatesWorkdir
    foreach ($template in @('.env.example', '.env.sample', '.env.template')) {
        if (Test-Path -LiteralPath (Join-Path $templatesWorkdir $template)) { throw "FAIL: template foi materializado: $template" }
        if (@($templatesManifest.Operations | Where-Object { $_.Path -eq $template }).Count -ne 0) { throw "FAIL: template entrou no inventario: $template" }
    }
    Write-Host 'PASS: .env.example/.env.sample/.env.template PERMITIDOS na raiz (nao materializados).'

    $insideTemplate = New-CandidateFixture -Name 'env-template-inside'
    Set-CandidateFile $insideTemplate.Candidate 'supabase/.env.example' "TEMPLATE=1`n"
    git -C $insideTemplate.Candidate add -f -- supabase/.env.example
    $insideTemplateWorkdir = New-MaterializationWorkdir
    $insideTemplateManifest = Invoke-Materialization -Fixture $insideTemplate -Workdir $insideTemplateWorkdir
    if (@($insideTemplateManifest.Operations | Where-Object { $_.Path -eq 'supabase/.env.example' -and $_.Operation -eq 'add' }).Count -ne 1) {
        throw 'FAIL: template dentro da allowlist nao foi materializado (regra inconsistente).'
    }
    Write-Host 'PASS: template permitido tambem dentro da allowlist (varredura+inventario+materializacao consistentes).'

    foreach ($segredo in @('.env', '.env.local', '.env.production', '.env.production.local')) {
        $fixtureSegredo = New-CandidateFixture -Name ("env-negado-" + ($segredo -replace '[^a-z]', ''))
        Set-CandidateFile $fixtureSegredo.Candidate $segredo "SEGREDO=1`n"
        Assert-FailsClosed -Name "segredo $segredo no candidato" -ExpectedMessage 'proibido' -Action { Invoke-Materialization -Fixture $fixtureSegredo }
    }
    $naoTemplate = New-CandidateFixture -Name 'env-nao-template'
    Set-CandidateFile $naoTemplate.Candidate '.env.example.local' "SEGREDO=1`n"
    Assert-FailsClosed -Name 'segredo .env.example.local' -ExpectedMessage 'proibido' -Action { Invoke-Materialization -Fixture $naoTemplate }
    $insideSecret = New-CandidateFixture -Name 'env-negado-inside'
    Set-CandidateFile $insideSecret.Candidate 'supabase/.env.production' "SEGREDO=1`n"
    Assert-FailsClosed -Name 'segredo dentro da allowlist' -ExpectedMessage 'proibido' -Action { Invoke-Materialization -Fixture $insideSecret }
    # Path PROIBIDO e ignorado pelo Git: a varredura explicita reprova mesmo assim.
    $ignoredSecret = New-CandidateFixture -Name 'ignored-secret' -ExtraGitignore @('.env.local')
    Set-CandidateFile $ignoredSecret.Candidate '.env.local' "SEGREDO=1`n"
    Assert-FailsClosed -Name 'segredo ignorado pelo Git no candidato' -ExpectedMessage 'path proibido' -Action { Invoke-Materialization -Fixture $ignoredSecret }

    # ------------------------------------------ migration historica alterada/removida
    $historic = New-CandidateFixture -Name 'historica-alterada'
    Set-CandidateFile $historic.Candidate 'supabase/migrations/20261018000000_f6_404_evaluation_mutation_bundles.sql' "-- alterada`n"
    Assert-FailsClosed -Name 'migration historica alterada' -ExpectedMessage 'Migration historica' -Action { Invoke-Materialization -Fixture $historic }
    $historicRemoved = New-CandidateFixture -Name 'historica-removida'
    Remove-Item -LiteralPath (Join-Path $historicRemoved.Candidate 'supabase/migrations/20261018000000_f6_404_evaluation_mutation_bundles.sql') -Force
    Assert-FailsClosed -Name 'migration historica removida' -ExpectedMessage 'Migration historica' -Action { Invoke-Materialization -Fixture $historicRemoved }

    # ------------------------------------------------ migration nova invalida/duplicada/#414
    $invalidMigration = New-CandidateFixture -Name 'migration-invalida'
    Set-CandidateFile $invalidMigration.Candidate 'supabase/migrations/2026_curta.sql' "-- x`n"
    Assert-FailsClosed -Name 'migration nova com versao/nome invalido' -ExpectedMessage 'invalido' -Action { Invoke-Materialization -Fixture $invalidMigration }
    $duplicateMigration = New-CandidateFixture -Name 'migration-duplicada'
    Set-CandidateFile $duplicateMigration.Candidate 'supabase/migrations/20261018000000_f6_outra.sql' "-- dup`n"
    Assert-FailsClosed -Name 'migration nova com versao duplicada' -ExpectedMessage 'duplicada' -Action { Invoke-Materialization -Fixture $duplicateMigration }
    $migration414 = New-CandidateFixture -Name 'migration-414'
    Set-CandidateFile $migration414.Candidate 'supabase/migrations/20261019000000_f6_414_company_admin_lifecycle.sql' "-- 414`n"
    Assert-FailsClosed -Name 'migration #414 no candidato' -ExpectedMessage '#414' -Action { Invoke-Materialization -Fixture $migration414 }

    # --------------------------------------------------- #404 obrigatoria (funcao)
    Assert-FailsClosed -Name '#404 ausente na lista de migrations' -ExpectedMessage '#404' -Action {
        Assert-DisposableEvaluationMigrations -MigrationFiles @('20261001000000_outra.sql')
    }

    # --------------------------------------------------- guards de modo (sem Docker)
    $exclusive = $false
    try {
        & $runner -Interactive -TargetCommit ('f' * 40) -CandidateWorktree $fixture.Candidate 2>&1 | Out-Null
    } catch { $exclusive = $_.Exception.Message -like '*mutuamente exclusivos*' }
    if (-not $exclusive) { throw 'FAIL: runner aceitou CandidateWorktree + TargetCommit.' }
    Write-Host 'PASS: CandidateWorktree e TargetCommit sao mutuamente exclusivos no runner.'
    $optIn = $false
    try { & $runner -CandidateWorktree $fixture.Candidate 2>&1 | Out-Null } catch { $optIn = $_.Exception.Message -like '*exige o modo Interactive*' }
    if (-not $optIn) { throw 'FAIL: runner aceitou CandidateWorktree sem Interactive.' }
    Write-Host 'PASS: CandidateWorktree exige o modo Interactive.'

    # --------------------------------------------------- guards de captura (texto)
    $safetyText = Get-Content -LiteralPath (Join-Path $psscriptRoot 'DisposableValidationSafety.ps1') -Raw -Encoding UTF8
    foreach ($needle in @('CandidateWorktree alterado durante a captura', 'Hash divergente no snapshot', 'Tamanho divergente no snapshot',
                          'Migration historica do baseline alterada/removida pelo candidato', 'Versao de migration duplicada no snapshot',
                          'Path proibido no candidato', 'Path fora da allowlist do CandidateWorktree',
                          'CandidateWorktree contem link/redirecionamento de path', 'Test-DisposableCloudReparseTag',
                          'Get-DisposableReparseTag', 'Assert-DisposablePathComponentsResolve',
                          'CandidateWorktree ilegivel (falha de leitura/hidratacao)', 'CandidateWorktree com leitura parcial')) {
        if ($safetyText -notmatch [regex]::Escape($needle)) { throw "FAIL: guard ausente no modulo de seguranca: $needle" }
    }
    Write-Host 'PASS: guards de captura/verificacao/seguranca presentes no modulo.'

    # ------------------- classificacao por TAG de reparse (determinista e fail-closed)
    # Seguranca e estabelecida SOMENTE por identificacao POSITIVA da tag cloud; a
    # ausencia de metadata de link (LinkType/Target/ResolveLinkTarget) NAO torna
    # nada seguro (host 5.1 nao preenche LinkType para tags desconhecidas).
    foreach ($tagAllow in @('0x9000601a', '0x9000001a', '0x9000101a', '0x9000e01a')) {
        if (-not (Test-DisposableCloudReparseTag -Tag $tagAllow)) { throw "FAIL: tag cloud $tagAllow deveria ser ALLOW." }
    }
    Write-Host 'PASS: tags cloud permitidas => ALLOW.'
    $casosDeny = @(
        @{ Nome = 'SymbolicLink'; Tag = '0xa000000c' },
        @{ Nome = 'Junction/MountPoint'; Tag = '0xa0000003' },
        @{ Nome = 'LX_SYMLINK (WSL)'; Tag = '0xa000001d' },
        @{ Nome = 'APPEXECLINK'; Tag = '0x8000001b' },
        @{ Nome = 'tag desconhecida'; Tag = '0xdeadbeef' },
        @{ Nome = 'texto nao-hex'; Tag = 'nao-eh-hex' },
        @{ Nome = 'string vazia'; Tag = '' },
        @{ Nome = 'nulo'; Tag = $null }
    )
    foreach ($caso in $casosDeny) {
        if (Test-DisposableCloudReparseTag -Tag $caso.Tag) { throw "FAIL: $($caso.Nome) deveria ser DENY." }
    }
    Write-Host 'PASS: SymbolicLink/Junction/LX_SYMLINK/APPEXECLINK/desconhecida/invalida/nula => DENY.'

    # --------------- excecao de template restrita a ARQUIVOS (nao diretorios)
    $envDir = New-CandidateFixture -Name 'env-template-dir'
    Set-CandidateFile $envDir.Candidate 'supabase/.env.example/interno.txt' "x`n"
    Assert-FailsClosed -Name 'diretorio .env.example nao recebe a excecao' -ExpectedMessage 'proibido' -Action { Invoke-Materialization -Fixture $envDir }

    # Comportamental: arquivo regular real nao redireciona e nao tem tag.
    $realFile = Join-Path $env:TEMP ('redirect-probe-' + [guid]::NewGuid().ToString('N') + '.txt')
    Set-Content -LiteralPath $realFile -Value 'conteudo regular'
    try {
        if (Test-DisposablePathRedirects -Path $realFile) { throw 'FAIL: arquivo regular classificado como redirecionamento.' }
        if ($null -ne (Get-DisposableReparseTag -Path $realFile)) { throw 'FAIL: arquivo regular nao deveria ter tag (leitor nao fail-closed).' }
        Write-Host 'PASS: arquivo regular real nao redireciona e leitor de tag retorna nulo (fail-closed).'
        # Comportamental: junction real (nao exige privilegio) redireciona e e DENY.
        $alvoDir = Join-Path $env:TEMP ('redirect-alvo-' + [guid]::NewGuid().ToString('N'))
        $junctionDir = Join-Path $env:TEMP ('redirect-junction-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $alvoDir -Force | Out-Null
        New-Item -ItemType Directory -Path $junctionDir -Force | Out-Null
        $junction = Join-Path $junctionDir 'link'
        $criou = $true
        try { New-Item -ItemType Junction -Path $junction -Target $alvoDir -ErrorAction Stop | Out-Null } catch { $criou = $false }
        if ($criou) {
            $tagJunction = Get-DisposableReparseTag -Path $junction
            if ($tagJunction -ine '0xa0000003') { throw "FAIL: tag da junction inesperada: '$tagJunction'." }
            if (-not (Test-DisposablePathRedirects -Path $junction)) { throw 'FAIL: junction real nao classificada como redirecionamento.' }
            Write-Host 'PASS: junction real => tag 0xa0000003 => DENY.'
            $linkCandidate = New-CandidateFixture -Name 'junction-candidato'
            Set-Content -LiteralPath (Join-Path $alvoDir 'arquivo.ts') -Value 'export {};'
            New-Item -ItemType Junction -Path (Join-Path $linkCandidate.Candidate 'src\redireciona') -Target $alvoDir -ErrorAction Stop | Out-Null
            $mensagem = ''
            try { Assert-DisposablePathComponentsResolve -Root $linkCandidate.Candidate -Relative 'src/redireciona/arquivo.ts' } catch { $mensagem = $_.Exception.Message }
            if ($mensagem -notmatch 'redirecionamento') { throw "FAIL: junction intermediaria nao reprovada (mensagem: '$mensagem')." }
            Write-Host 'PASS: junction INTERMEDIARIA no caminho do candidato reprova fail-closed.'
        } else {
            Write-Host 'PASS (parcial): criacao de junction indisponivel neste host; DENY de Junction coberto pela classificacao determinista.'
        }
        Remove-Item -LiteralPath $junctionDir, $alvoDir -Recurse -Force -ErrorAction SilentlyContinue
    } finally { Remove-Item -LiteralPath $realFile -Force -ErrorAction SilentlyContinue }

    Write-Host 'PASS: suíte CandidateWorktree concluída.'
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
