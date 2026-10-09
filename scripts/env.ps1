# Dot-source to load .env into the current PowerShell session and put psql on PATH:
#     . .\scripts\env.ps1
# psql, dbt (profiles.yml uses env_var('PG...')) and Python all read the same PG* variables.

$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repoRoot '.env'

if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $value = $Matches[2].Trim('"').Trim("'")
            Set-Item -Path "Env:$($Matches[1])" -Value $value
        }
    }
} else {
    Write-Warning ".env not found at $envFile (copy .env.example to .env and fill it in)"
}

# The EDB installer does not add psql to PATH; find the newest install if needed.
if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
    $pgBin = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue |
        Sort-Object { [int]($_.Directory.Parent.Name -replace '\D', '') } -Descending |
        Select-Object -First 1
    if ($pgBin) {
        $env:Path = "$($pgBin.DirectoryName);$env:Path"
    } else {
        Write-Warning 'psql not found on PATH or under C:\Program Files\PostgreSQL\*\bin'
    }
}
