[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$expectedProjectId = 'feedback-control'
$expectedAdminId = 'b0000000-0000-0000-0000-000000000001'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$supabaseRoot = Join-Path $repoRoot 'supabase'
$configPath = Join-Path $supabaseRoot 'config.toml'
$containerName = 'supabase_db_feedback-control'
$email = [Environment]::GetEnvironmentVariable('VIRTUS_LOCAL_ADMIN_EMAIL')
$password = [Environment]::GetEnvironmentVariable('VIRTUS_LOCAL_ADMIN_PASSWORD')
$sqlPath = Join-Path $env:TEMP "virtus-local-admin-bootstrap-$PID.sql"

function Fail([string]$Message) {
    throw "Bootstrap local recusado: $Message"
}

function Invoke-Checked([string]$FilePath, [string[]]$ArgumentList) {
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        Fail "comando falhou ($LASTEXITCODE): $FilePath $($ArgumentList -join ' ')"
    }
}

function Get-LocalFingerprint {
    $query = @'
select 'organizations=' || count(*) || ':' || md5(coalesce(string_agg(id::text || ':' || coalesce(name, ''), '|' order by id), '')) from public.organizations;
select 'memberships=' || count(*) || ':' || md5(coalesce(string_agg(user_profile_id::text || ':' || organization_id::text || ':' || status, '|' order by user_profile_id, organization_id), '')) from public.user_organization_memberships;
select 'collaborators=' || count(*) || ':' || md5(coalesce(string_agg(id::text || ':' || organization_id::text || ':' || coalesce(full_name, ''), '|' order by id), '')) from public.collaborators;
select 'positions=' || count(*) || ':' || md5(coalesce(string_agg(id::text || ':' || organization_id::text, '|' order by id), '')) from public.organizational_positions;
'@
    $result = docker exec $containerName psql -U postgres -d postgres -At -X -v ON_ERROR_STOP=1 -c $query
    if ($LASTEXITCODE -ne 0) { Fail 'nao foi possivel capturar o fingerprint funcional local.' }
    return (@($result) | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) -join "`n"
}

try {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { Fail 'config.toml ausente.' }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $projectMatch = [regex]::Match($config, '(?m)^project_id\s*=\s*"([^"]+)"\s*$')
    if (-not $projectMatch.Success -or $projectMatch.Groups[1].Value -ne $expectedProjectId) {
        Fail "project_id diferente de $expectedProjectId."
    }
    $allowlistMatch = [regex]::Match($config, '(?m)^INVITE_ADMIN_USER_IDS\s*=\s*"([^"]*)"\s*$')
    if (-not $allowlistMatch.Success -or
        -not (($allowlistMatch.Groups[1].Value -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -eq $expectedAdminId })) {
        Fail "allowlist nao contem o UUID esperado $expectedAdminId."
    }
    if (-not ((docker ps --format '{{.Names}}') -contains $containerName)) {
        Fail "container local esperado ausente: $containerName."
    }
    if ([string]::IsNullOrWhiteSpace($email) -or $email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        Fail 'VIRTUS_LOCAL_ADMIN_EMAIL ausente ou invalido.'
    }
    if ([string]::IsNullOrWhiteSpace($password) -or $password.Length -lt 12 -or $password -match '[\r\n]') {
        Fail 'VIRTUS_LOCAL_ADMIN_PASSWORD ausente, curta ou com quebra de linha.'
    }

    $before = Get-LocalFingerprint
    Write-Host "Fingerprint funcional BEFORE:`n$before"

    $sqlEmail = $email.Replace("'", "''")
    $sqlPassword = $password.Replace("'", "''")
    $sql = @"
begin;
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token,
  reauthentication_token, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000', '$expectedAdminId', 'authenticated',
  'authenticated', '$sqlEmail', crypt('$sqlPassword', gen_salt('bf')), now(),
  '', '', '', '', '', '', '', '',
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
)
on conflict (id) do update set
  email = excluded.email,
  encrypted_password = excluded.encrypted_password,
  email_confirmed_at = excluded.email_confirmed_at,
  updated_at = now();

update auth.identities
   set provider_id = '$expectedAdminId',
       identity_data = jsonb_build_object('sub', '$expectedAdminId', 'email', '$sqlEmail'),
       updated_at = now()
 where user_id = '$expectedAdminId' and provider = 'email';

insert into auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at)
select gen_random_uuid(), '$expectedAdminId', '$expectedAdminId',
       jsonb_build_object('sub', '$expectedAdminId', 'email', '$sqlEmail'),
       'email', now(), now()
where not exists (
  select 1 from auth.identities where user_id = '$expectedAdminId' and provider = 'email'
);
commit;
"@
    Set-Content -LiteralPath $sqlPath -Value $sql -Encoding UTF8 -NoNewline
    Get-Content -LiteralPath $sqlPath -Raw -Encoding UTF8 |
        docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { Fail 'escrita local da identidade falhou.' }

    $after = Get-LocalFingerprint
    Write-Host "Fingerprint funcional AFTER:`n$after"
    if ($before -ne $after) { Fail 'dados funcionais foram alterados.' }

    $check = docker exec $containerName psql -U postgres -d postgres -At -X -v ON_ERROR_STOP=1 -c "select count(*) from auth.users where id = '$expectedAdminId'; select count(*) from auth.identities where user_id = '$expectedAdminId' and provider = 'email';"
    $checkLines = (($check -join "`n") -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0 -or $checkLines.Count -ne 2 -or $checkLines[0] -ne '1' -or $checkLines[1] -ne '1') {
        Fail 'a identidade ou sua identity email nao foi confirmada.'
    }
    Write-Host "Admin Virtus local pronto: $expectedAdminId ($email); nenhuma organizacao/membership/colaborador/posicao foi criada."
}
finally {
    if (Test-Path -LiteralPath $sqlPath) {
        Remove-Item -LiteralPath $sqlPath -Force -ErrorAction SilentlyContinue
    }
}
