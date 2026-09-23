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
    try { Assert-DisposableValidationTarget -Workdir $workdir -TempRoot ([IO.Path]::GetTempPath().TrimEnd('\')) -ProjectId 'feedback-control-validation' -ContainerName 'supabase_db_feedback-control' -RuntimeContainerName 'supabase_db_feedback-control' -Config $config; throw 'FAIL: runtime container fails' } catch { if ($_.Exception.Message -eq 'FAIL: runtime container fails') { throw }; Write-Host 'PASS: runtime container fails' }
    & $guard -Root $repoRoot
    Write-Host 'PASS: guard repository and targeted fixtures.'
} finally { if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force } }
