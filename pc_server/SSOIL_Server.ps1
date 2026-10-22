# SS OIL - Windows PowerShell 5.1 LAN API. Python/EXE gerekmez.
# SQL tarafinda yalnizca SELECT kullanilir.
$ErrorActionPreference = 'Stop'
$hostIp = if ($env:SSOIL_HOST) { $env:SSOIL_HOST } else { '+' }
$port = if ($env:SSOIL_PORT) { [int]$env:SSOIL_PORT } else { 8765 }
$token = $env:SSOIL_API_TOKEN
$odbc = $env:SSOIL_ODBC_CONNECTION
if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($odbc)) {
    Write-Host 'HATA: AYARLAR.bat icinde API TOKEN ve ODBC CONNECTION tanimli olmali.' -ForegroundColor Red
    exit 1
}
Add-Type -AssemblyName System.Data
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://$($hostIp):$port/")
try { $listener.Start() } catch {
    Write-Host "HATA: Port $port acilamadi: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Gerekirse yonetici CMD ile: netsh http add urlacl url=http://+:8765/ user=Everyone'
    exit 1
}
Write-Host "SS OIL sunucusu hazir. Port: $port (CTRL+C ile durdur)"
function Get-Data($sql, $id) {
    $db = New-Object System.Data.Odbc.OdbcConnection($odbc)
    try {
        $db.Open()
        $cmd = $db.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.CommandTimeout = 15
        if ($null -ne $id) {
            $p = $cmd.Parameters.Add('@id', [System.Data.Odbc.OdbcType]::Int)
            $p.Value = [int]$id
        }
        $reader = $cmd.ExecuteReader()
        try {
            $list = New-Object System.Collections.ArrayList
            while ($reader.Read()) {
                $row = @()
                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    if ($reader.IsDBNull($i)) { $row += $null } else { $row += $reader.GetValue($i) }
                }
                [void]$list.Add($row)
            }
            return ,$list
        } finally { $reader.Close() }
    } finally { $db.Dispose() }
}
function NumStr($x) {
    if ($null -eq $x) { return '0' }
    return [Convert]::ToString($x, [Globalization.CultureInfo]::InvariantCulture)
}
function Reply($ctx, [int]$status, $body) {
    $json = ConvertTo-Json -InputObject $body -Depth 12 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $ctx.Response.StatusCode = $status
    $ctx.Response.ContentType = 'application/json; charset=utf-8'
    $ctx.Response.Headers['Cache-Control'] = 'no-store'
    $ctx.Response.ContentLength64 = $bytes.Length
    try { $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length) } finally { $ctx.Response.Close() }
}
while ($listener.IsListening) {
    try { $ctx = $listener.GetContext() } catch { break }
    try {
        if ($ctx.Request.HttpMethod -ne 'GET') {
            Reply $ctx 405 @{error='read only'}
            continue
        }
        if ($ctx.Request.Headers['X-SSOIL-Token'] -cne $token) {
            Reply $ctx 401 @{error='unauthorized'}
            continue
        }
        $path = $ctx.Request.Url.AbsolutePath
        if ($path -eq '/snapshot') {
            $rows = Get-Data 'SELECT Art_ID, Naziv, PCena, Kolicina FROM dbo.ART' $null
            $products = @{}
            foreach ($r in $rows) {
                $id = [string]$r[0]
                $products[$id] = @{
                    id=$id; name=[string]$r[1]; price=(NumStr $r[2]);
                    stock=(NumStr $r[3]); barcodes=(New-Object System.Collections.ArrayList)
                }
            }
            $barcodes = Get-Data 'SELECT Art_ID, BKod_ID FROM dbo.ART_BK' $null
            foreach ($r in $barcodes) {
                $id = [string]$r[0]; $bc = [string]$r[1]
                if ($products.ContainsKey($id) -and -not [string]::IsNullOrWhiteSpace($bc)) {
                    if (-not $products[$id].barcodes.Contains($bc.Trim())) {
                        [void]$products[$id].barcodes.Add($bc.Trim())
                    }
                }
            }
            $items = @($products.Values | ForEach-Object {
                @{id=$_.id; name=$_.name; price=$_.price; stock=$_.stock; barcodes=@($_.barcodes.ToArray())}
            })
            Reply $ctx 200 @{products=$items}
        } elseif ($path -eq '/sales') {
            # Daily sales aggregated once for the whole product catalog.
            $rows = Get-Data 'SELECT Art_ID, COALESCE(SUM(Kolicina), 0) FROM dbo.SmP_S GROUP BY Art_ID' $null
            $sales = @{}
            foreach ($r in $rows) { $sales[[string]$r[0]] = (NumStr $r[1]) }
            Reply $ctx 200 @{sales=$sales}
        } elseif ($path -match '^/product/([0-9]+)$') {
            $id = $matches[1]
            $rows = Get-Data 'SELECT Art_ID, PCena, Kolicina FROM dbo.ART WHERE Art_ID = ?' $id
            if ($rows.Count -eq 0) {
                Reply $ctx 404 @{error='not found'}
                continue
            }
            $r = $rows[0]
            $soldRows = Get-Data 'SELECT COALESCE(SUM(Kolicina), 0) FROM dbo.SmP_S WHERE Art_ID = ?' $id
            $sold = [decimal]($soldRows[0][0])
            $base = [decimal]$r[2]
            $net = $base - $sold
            Reply $ctx 200 @{
                id=[string]$r[0]; price=(NumStr $r[1]); stock=(NumStr $net);
                art_stock=(NumStr $base); sales=(NumStr $sold)
            }
        } else {
            Reply $ctx 404 @{error='not found'}
        }
    } catch {
        Write-Host ("HATA [{0}]: {1}" -f $ctx.Request.Url.AbsolutePath, $_.Exception.Message) -ForegroundColor Red
        try { Reply $ctx 503 @{error='database unavailable or schema mismatch'} } catch {}
    }
}
