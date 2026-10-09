# Load the 9 Olist CSVs from data/raw/ into the raw schema (all-text tables from
# scripts/00_create_raw_schema.sql). Truncate + \copy per table, all in one transaction,
# so a failed load leaves the previous data intact. Prints row counts at the end.
#
#     .\scripts\load_raw.ps1                 # assumes the raw schema exists
#     .\scripts\load_raw.ps1 -CreateSchema   # (re)create the raw schema first
#
# Note: the reviews CSV has newlines inside quoted comment fields. \copy in CSV mode
# parses them correctly (99,224 rows), unlike a naive line count.

param([switch]$CreateSchema)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$rawDir = Join-Path $repoRoot 'data\raw'

$tables = [ordered]@{
    'orders'                            = 'olist_orders_dataset.csv'
    'customers'                         = 'olist_customers_dataset.csv'
    'order_items'                       = 'olist_order_items_dataset.csv'
    'order_payments'                    = 'olist_order_payments_dataset.csv'
    'order_reviews'                     = 'olist_order_reviews_dataset.csv'
    'products'                          = 'olist_products_dataset.csv'
    'sellers'                           = 'olist_sellers_dataset.csv'
    'geolocation'                       = 'olist_geolocation_dataset.csv'
    'product_category_name_translation' = 'product_category_name_translation.csv'
}

foreach ($file in $tables.Values) {
    if (-not (Test-Path (Join-Path $rawDir $file))) {
        throw "Missing data\raw\$file. Run: python scripts/download_data.py"
    }
}

if ($CreateSchema) {
    psql -X -q -f (Join-Path $PSScriptRoot '00_create_raw_schema.sql')
    if ($LASTEXITCODE -ne 0) { throw "creating raw schema failed (exit $LASTEXITCODE)" }
}

$lines = @('\set ON_ERROR_STOP on', 'begin;')
foreach ($t in $tables.Keys) {
    # Forward slashes and doubled single quotes keep paths with spaces safe inside \copy.
    $path = (Join-Path $rawDir $tables[$t]).Replace('\', '/').Replace("'", "''")
    $lines += "truncate raw.$t;"
    $lines += "\copy raw.$t from '$path' with (format csv, header true, encoding 'UTF8')"
}
$lines += 'commit;'
$union = ($tables.Keys | ForEach-Object { "select '$_' as table_name, count(*) as row_count from raw.$_" }) -join ' union all '
$lines += "$union order by 1;"

$tmp = [System.IO.Path]::GetTempFileName()
try {
    # UTF-8 without BOM: psql would otherwise choke on a BOM before the first command.
    [System.IO.File]::WriteAllLines($tmp, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    psql -X -f $tmp
    if ($LASTEXITCODE -ne 0) { throw "load failed (exit $LASTEXITCODE); transaction rolled back" }
    Write-Host ("Loaded 9 tables in {0:N1}s" -f $sw.Elapsed.TotalSeconds)
} finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}
