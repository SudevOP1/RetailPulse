# One-time setup, run as the Postgres superuser: creates the project role and database
# from PGUSER / PGPASSWORD / PGDATABASE in .env. Safe to re-run (skips what exists and
# resets the role password to the .env value).
#
#     .\scripts\setup_postgres.ps1                 # prompts for the 'postgres' superuser password
#     .\scripts\setup_postgres.ps1 -Superuser me

param([string]$Superuser = 'postgres')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1')

$role = $env:PGUSER
$db = $env:PGDATABASE
$rolePassword = $env:PGPASSWORD
if (-not $role -or -not $db -or -not $rolePassword) { throw 'PGUSER, PGDATABASE and PGPASSWORD must be set in .env' }
if ($role -notmatch '^[a-z_][a-z0-9_]*$' -or $db -notmatch '^[a-z_][a-z0-9_]*$') {
    throw 'PGUSER and PGDATABASE must be lowercase identifiers (letters, digits, underscore)'
}

# Connect as the superuser without clobbering the project's PG* values.
$saved = @{ PGUSER = $env:PGUSER; PGPASSWORD = $env:PGPASSWORD; PGDATABASE = $env:PGDATABASE }
$env:PGUSER = $Superuser
$env:PGDATABASE = 'postgres'
$secure = Read-Host "Password for Postgres superuser '$Superuser'" -AsSecureString
$env:PGPASSWORD = [System.Net.NetworkCredential]::new('', $secure).Password

try {
    # format(%I, %L) quotes identifiers/literals safely; \gexec runs the generated statement.
    $sql = @"
\set ON_ERROR_STOP on
select format('create role %I login password %L', :'role', :'pw')
where not exists (select from pg_roles where rolname = :'role') \gexec
select format('alter role %I login password %L', :'role', :'pw') \gexec
select format('create database %I owner %I encoding ''UTF8'' template template0', :'db', :'role')
where not exists (select from pg_database where datname = :'db') \gexec
"@
    $sql | psql -X -q -v role=$role -v pw=$rolePassword -v db=$db
    if ($LASTEXITCODE -ne 0) { throw "psql failed (exit $LASTEXITCODE)" }
    Write-Host "Role '$role' and database '$db' ready."
} finally {
    foreach ($k in $saved.Keys) { Set-Item -Path "Env:$k" -Value $saved[$k] }
}
