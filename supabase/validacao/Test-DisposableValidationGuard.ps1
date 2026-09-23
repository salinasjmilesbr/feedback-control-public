[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$allowedRunner = 'supabase/validacao/Invoke-DisposableValidation.ps1'
$allowedCi = '.github/workflows/ci.yml'
$resetPattern = '(?i)\bsupabase(?:@[^\s]+)?\s+db\s+reset\s+--local\b'
$files = Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|dist)[\\/]' } | Where-Object { $_.Extension -in '.ps1', '.yml', '.yaml', '.json' }
$violations = [System.Collections.Generic.List[string]]::new()
foreach ($file in $files) {
    $relative = $file.FullName.Substring($Root.TrimEnd('\', '/').Length).TrimStart('\', '/').Replace('\', '/')
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    if ($text -notmatch $resetPattern) { continue }
    if ($relative -eq $allowedRunner) {
        $targetGuardIndex = $text.IndexOf('Assert-DisposableValidationTarget')
        $resetIndex = [regex]::Match($text, $resetPattern).Index
        if ($targetGuardIndex -lt 0 -or $targetGuardIndex -gt $resetIndex -or $text -notmatch '--workdir'', \$validationRoot') { $violations.Add("${relative}: reset permitido somente com Assert-DisposableValidationTarget anterior e --workdir descartavel.") }
        continue
    }
    if ($relative -eq $allowedCi -and $text -match '(?m)^\s*# disposable-validation-guard: isolated-github-runner\s*$' -and $text -match '(?m)^\s*runs-on:\s*ubuntu-latest\s*$') { continue }
    $violations.Add("${relative}: db reset --local direto e proibido; use Invoke-DisposableValidation.ps1.")
}
if ($violations.Count -gt 0) { throw ("Guard de reset destrutivo falhou:`n" + ($violations -join "`n")) }
Write-Host 'PASS: nenhum gate versionado reseta o runtime local compartilhado.'
