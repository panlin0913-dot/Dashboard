param(
  [string]$HostName = "localhost",
  [int]$Port = 8788,
  [string]$MySqlHost = "127.0.0.1",
  [int]$MySqlPort = 3306,
  [string]$MySqlUser = "root",
  [string]$MySqlPassword = "Rm200509",
  [string]$Database = "demo_payments"
)

$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$uiDir = Join-Path $rootDir "ui"
$mysqlExe = "mysql"

function Send-Json {
  param(
    [Parameter(Mandatory=$true)] $Context,
    [Parameter(Mandatory=$true)] $Object,
    [int]$StatusCode = 200
  )

  $json = $Object | ConvertTo-Json -Depth 8
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = "application/json; charset=utf-8"
  $Context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
  $Context.Response.ContentLength64 = $bytes.Length
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Context.Response.Close()
}

function Send-File {
  param(
    [Parameter(Mandatory=$true)] $Context,
    [Parameter(Mandatory=$true)] [string]$FilePath
  )

  if (-not (Test-Path $FilePath)) {
    Send-Json -Context $Context -StatusCode 404 -Object @{
      error = "NotFound"
      message = "File not found."
    }
    return
  }

  $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
  $contentType = switch ($ext) {
    ".html" { "text/html; charset=utf-8" }
    ".css"  { "text/css; charset=utf-8" }
    ".js"   { "application/javascript; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    default { "application/octet-stream" }
  }

  $bytes = [System.IO.File]::ReadAllBytes($FilePath)
  $Context.Response.StatusCode = 200
  $Context.Response.ContentType = $contentType
  $Context.Response.ContentLength64 = $bytes.Length
  $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $Context.Response.Close()
}

function Invoke-MySqlQuery {
  param(
    [Parameter(Mandatory=$true)] [string]$Query
  )

  $env:MYSQL_PWD = $MySqlPassword
  try {
    $output = & $mysqlExe "-h$MySqlHost" "-P$MySqlPort" "-u$MySqlUser" "-D$Database" "--batch" "--raw" "--skip-column-names" "-e" $Query 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw ("MySQL query failed: " + ($output -join "`n"))
    }
    return $output
  }
  finally {
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
  }
}

function Parse-MetricsRows {
  param(
    [Parameter(Mandatory=$true)] [string[]]$Lines
  )

  $rows = @()
  foreach ($line in $Lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    $parts = $line -split "`t"
    if ($parts.Length -lt 12) {
      continue
    }
    $rows += [PSCustomObject]@{
      period = $parts[0]
      txCount = [int64]$parts[1]
      volume = [double]$parts[2]
      refundAmount = [double]$parts[3]
      refundCount = [int64]$parts[4]
      chargebackAmount = [double]$parts[5]
      chargebackCount = [int64]$parts[6]
      fraudAmount = [double]$parts[7]
      fraudCount = [int64]$parts[8]
      refundRate = [double]$parts[9]
      chargebackRate = [double]$parts[10]
      fraudRate = [double]$parts[11]
    }
  }
  return $rows
}

function Handle-Api {
  param(
    [Parameter(Mandatory=$true)] $Context
  )

  $request = $Context.Request
  $path = $request.Url.AbsolutePath.ToLowerInvariant()
  $query = [System.Web.HttpUtility]::ParseQueryString($request.Url.Query)

  if ($path -eq "/api/health") {
    Send-Json -Context $Context -Object @{
      ok = $true
      service = "payment-monitor-api"
    }
    return
  }

  if ($path -eq "/api/merchants") {
    $sql = @"
SELECT merchant_id, merchant_name, mcc
FROM merchants
ORDER BY merchant_id;
"@
    $lines = Invoke-MySqlQuery -Query $sql
    $rows = @()
    foreach ($line in $lines) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $parts = $line -split "`t"
      if ($parts.Length -lt 3) { continue }
      $rows += [PSCustomObject]@{
        merchant_id = $parts[0]
        merchant_name = $parts[1]
        mcc = $parts[2]
      }
    }
    Send-Json -Context $Context -Object @{ rows = $rows }
    return
  }

  if ($path -eq "/api/platform") {
    $sql = @"
SELECT DATE_FORMAT(stat_month, '%Y-%m') AS period,
       tx_success_count,
       tx_success_amount,
       refund_amount,
       refund_count,
       chargeback_amount,
       chargeback_count,
       fraud_amount,
       fraud_count,
       refund_rate,
       chargeback_rate,
       fraud_rate
FROM vw_platform_monthly_metrics
ORDER BY stat_month DESC
LIMIT 6;
"@

    $rows = Parse-MetricsRows -Lines (Invoke-MySqlQuery -Query $sql)
    Send-Json -Context $Context -Object @{ rows = $rows }
    return
  }

  if ($path -eq "/api/merchant") {
    $merchantId = $query["merchant_id"]
    if ([string]::IsNullOrWhiteSpace($merchantId)) {
      Send-Json -Context $Context -StatusCode 400 -Object @{
        error = "BadRequest"
        message = "merchant_id is required."
      }
      return
    }

    $safeMerchant = $merchantId.Replace("'", "''")
    $metaSql = @"
SELECT merchant_name, mcc
FROM merchants
WHERE merchant_id = '$safeMerchant'
LIMIT 1;
"@
    $metaLines = Invoke-MySqlQuery -Query $metaSql
    $merchantName = ""
    $merchantMcc = ""
    $metaLine = ""
    if ($metaLines -is [array]) {
      if ($metaLines.Length -gt 0) { $metaLine = [string]$metaLines[0] }
    } else {
      $metaLine = [string]$metaLines
    }
    if (-not [string]::IsNullOrWhiteSpace($metaLine)) {
      $metaParts = $metaLine -split "`t"
      if ($metaParts.Length -ge 2) {
        $merchantName = $metaParts[0]
        $merchantMcc = $metaParts[1]
      }
    }
    $sql = @"
SELECT DATE_FORMAT(stat_month, '%Y-%m') AS period,
       tx_success_count,
       tx_success_amount,
       refund_amount,
       refund_count,
       chargeback_amount,
       chargeback_count,
       fraud_amount,
       fraud_count,
       refund_rate,
       chargeback_rate,
       fraud_rate
FROM vw_merchant_monthly_metrics
WHERE merchant_id = '$safeMerchant'
ORDER BY stat_month DESC
LIMIT 6;
"@

    $rows = Parse-MetricsRows -Lines (Invoke-MySqlQuery -Query $sql)
    Send-Json -Context $Context -Object @{
      merchant_id = $merchantId
      merchant_name = $merchantName
      mcc = $merchantMcc
      rows = $rows
    }
    return
  }

  if ($path -eq "/api/details") {
    $detailType = $query["type"]
    $scope = $query["scope"]
    $safeScope = if ($scope -eq "merchant") { "merchant" } else { "platform" }
    $merchantId = $query["merchant_id"]
    $period = $query["period"]
    $page = [int]($query["page"])
    if ($page -le 0) { $page = 1 }
    $pageSize = [int]($query["page_size"])
    if ($pageSize -le 0) { $pageSize = 50 }
    if ($pageSize -gt 50) { $pageSize = 50 }

    $merchantFilter = ""
    if ($safeScope -eq "merchant") {
      if ([string]::IsNullOrWhiteSpace($merchantId)) {
        Send-Json -Context $Context -StatusCode 400 -Object @{
          error = "BadRequest"
          message = "merchant_id is required for merchant scope."
        }
        return
      }
      $safeMerchant = $merchantId.Replace("'", "''")
      $merchantFilter = " AND t.merchant_id = '$safeMerchant' "
    }

    $periodFilter = ""
    if (-not [string]::IsNullOrWhiteSpace($period) -and $period -match '^\d{4}-\d{2}$') {
      $safePeriod = $period.Replace("'", "''")
      if ($detailType -eq "transaction") {
        $periodFilter = " AND DATE_FORMAT(t.txn_time, '%Y-%m') = '$safePeriod' "
      } elseif ($detailType -eq "refund") {
        $periodFilter = " AND DATE_FORMAT(r.refund_time, '%Y-%m') = '$safePeriod' "
      } elseif ($detailType -eq "chargeback") {
        $periodFilter = " AND DATE_FORMAT(c.chargeback_time, '%Y-%m') = '$safePeriod' "
      } elseif ($detailType -eq "fraud") {
        $periodFilter = " AND DATE_FORMAT(f.fraud_time, '%Y-%m') = '$safePeriod' "
      }
    }
    $offset = ($page - 1) * $pageSize

    if ($detailType -eq "transaction") {
      $countSql = @"
SELECT COUNT(*)
FROM transactions t
WHERE 1=1
  $merchantFilter
  $periodFilter;
"@
      $sql = @"
SELECT
  t.merchant_id,
  t.order_id,
  t.mcc,
  t.currency,
  t.amount,
  t.payment_status AS detail_status,
  DATE_FORMAT(t.txn_time, '%Y-%m-%d %H:%i:%s') AS event_time
FROM transactions t
WHERE 1=1
  $merchantFilter
  $periodFilter
ORDER BY t.txn_time DESC
LIMIT $offset, $pageSize;
"@
    } elseif ($detailType -eq "refund") {
      $countSql = @"
SELECT COUNT(*)
FROM refunds r
JOIN transactions t ON t.order_id = r.original_order_id
WHERE 1=1
  $merchantFilter
  $periodFilter;
"@
      $sql = @"
SELECT
  t.merchant_id,
  t.order_id,
  t.mcc,
  r.refund_currency AS currency,
  r.refund_amount AS amount,
  r.refund_status AS detail_status,
  DATE_FORMAT(r.refund_time, '%Y-%m-%d %H:%i:%s') AS event_time
FROM refunds r
JOIN transactions t ON t.order_id = r.original_order_id
WHERE 1=1
  $merchantFilter
  $periodFilter
ORDER BY r.refund_time DESC
LIMIT $offset, $pageSize;
"@
    } elseif ($detailType -eq "chargeback") {
      $countSql = @"
SELECT COUNT(*)
FROM chargebacks c
JOIN transactions t ON t.order_id = c.original_order_id
WHERE 1=1
  $merchantFilter
  $periodFilter;
"@
      $sql = @"
SELECT
  t.merchant_id,
  t.order_id,
  c.mcc,
  c.chargeback_currency AS currency,
  c.chargeback_amount AS amount,
  c.chargeback_reason AS detail_status,
  DATE_FORMAT(c.chargeback_time, '%Y-%m-%d %H:%i:%s') AS event_time
FROM chargebacks c
JOIN transactions t ON t.order_id = c.original_order_id
WHERE 1=1
  $merchantFilter
  $periodFilter
ORDER BY c.chargeback_time DESC
LIMIT $offset, $pageSize;
"@
    } elseif ($detailType -eq "fraud") {
      $countSql = @"
SELECT COUNT(*)
FROM fraud_events f
JOIN transactions t ON t.order_id = f.original_order_id
WHERE 1=1
  $merchantFilter
  $periodFilter;
"@
      $sql = @"
SELECT
  t.merchant_id,
  t.order_id,
  f.mcc,
  f.currency,
  f.amount,
  'FRAUD' AS detail_status,
  DATE_FORMAT(f.fraud_time, '%Y-%m-%d %H:%i:%s') AS event_time
FROM fraud_events f
JOIN transactions t ON t.order_id = f.original_order_id
WHERE 1=1
  $merchantFilter
  $periodFilter
ORDER BY f.fraud_time DESC
LIMIT $offset, $pageSize;
"@
    } else {
      Send-Json -Context $Context -StatusCode 400 -Object @{
        error = "BadRequest"
        message = "type must be transaction, refund, chargeback, or fraud."
      }
      return
    }

    $countLine = Invoke-MySqlQuery -Query $countSql
    $total = 0
    if ($countLine -is [array]) {
      if ($countLine.Length -gt 0) { $total = [int]$countLine[0] }
    } else {
      $total = [int]$countLine
    }
    $totalPages = [Math]::Ceiling($total / [double]$pageSize)
    if ($totalPages -lt 1) { $totalPages = 1 }

    $lines = Invoke-MySqlQuery -Query $sql
    $rows = @()
    foreach ($line in $lines) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $parts = $line -split "`t"
      if ($parts.Length -lt 7) { continue }
      $rows += [PSCustomObject]@{
        merchant_id = $parts[0]
        order_id = $parts[1]
        mcc = $parts[2]
        currency = $parts[3]
        amount = [double]$parts[4]
        detail_status = $parts[5]
        event_time = $parts[6]
      }
    }

    Send-Json -Context $Context -Object @{
      type = $detailType
      scope = $safeScope
      merchant_id = $merchantId
      page = $page
      page_size = $pageSize
      total = $total
      total_pages = $totalPages
      rows = $rows
    }
    return
  }

  Send-Json -Context $Context -StatusCode 404 -Object @{
    error = "NotFound"
    message = "API route not found."
  }
}

Add-Type -AssemblyName System.Web

$listener = [System.Net.HttpListener]::new()
$prefix = "http://${HostName}:${Port}/"
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host "Server started at $prefix"
Write-Host "UI: ${prefix} (platform + merchant monitor)"
Write-Host "API health: ${prefix}api/health"

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    try {
      $path = $context.Request.Url.AbsolutePath
      if ($path.StartsWith("/api/", [System.StringComparison]::OrdinalIgnoreCase)) {
        Handle-Api -Context $context
        continue
      }

      if ($path -eq "/" -or $path -eq "") {
        Send-File -Context $context -FilePath (Join-Path $uiDir "login.html")
        continue
      }

      if ($path -eq "/dashboard") {
        Send-File -Context $context -FilePath (Join-Path $uiDir "index.html")
        continue
      }

      $relativePath = $path.TrimStart("/").Replace("/", [System.IO.Path]::DirectorySeparatorChar)
      $filePath = Join-Path $uiDir $relativePath
      Send-File -Context $context -FilePath $filePath
    } catch {
      Send-Json -Context $context -StatusCode 500 -Object @{
        error = "ServerError"
        message = $_.Exception.Message
      }
    }
  }
}
finally {
  $listener.Stop()
  $listener.Close()
}
