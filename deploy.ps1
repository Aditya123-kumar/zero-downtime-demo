$ErrorActionPreference = "Stop"

$Docker = "C:\Users\CEREBRENT PC\AppData\Local\Programs\DockerDesktop\resources\bin\docker.exe"

$Image = "zero-downtime-demo-app:latest"
$Network = "zero-downtime-demo_default"
$NginxConfig = "nginx/nginx.conf"
$NginxContainer = "demo-nginx"

Write-Host "======================================"
Write-Host " Zero Downtime Deployment"
Write-Host "======================================"

# --------------------------------------------------
# 1. Detect current and new version
# --------------------------------------------------

Write-Host "[1/6] Detecting current version..."

$config = Get-Content $NginxConfig -Raw

if ($config -match "server demo-v1:5000;") {
    $Current = "demo-v1"
    $New = "demo-v2"
}
elseif ($config -match "server demo-v2:5000;") {
    $Current = "demo-v2"
    $New = "demo-v1"
}
else {
    throw "Could not detect current application version from nginx.conf"
}

Write-Host "Current version: $Current"
Write-Host "New version: $New"

# --------------------------------------------------
# 2. Check network
# --------------------------------------------------

Write-Host "[2/6] Checking Docker network..."

& $Docker network inspect $Network *> $null

if ($LASTEXITCODE -ne 0) {

    Write-Host "Creating Docker network..."

    & $Docker network create $Network

    if ($LASTEXITCODE -ne 0) {
        throw "Could not create Docker network."
    }
}

# --------------------------------------------------
# 3. Make sure Nginx is running
# --------------------------------------------------

Write-Host "[3/6] Checking Nginx..."

$NginxRunning = & $Docker ps -q --filter "name=^$NginxContainer$"

if (-not $NginxRunning) {

    Write-Host "Nginx is not running."

    & $Docker ps -a --filter "name=^$NginxContainer$"

    throw "Nginx container is not running. Please start demo-nginx first."
}

Write-Host "Nginx is running."
# --------------------------------------------------
# 4. Start current version if required
# --------------------------------------------------

Write-Host "[4/6] Checking current application..."

$CurrentExists = & $Docker ps -aq --filter "name=^$Current$"

if (-not $CurrentExists) {

    Write-Host "$Current does not exist. Creating it..."

    & $Docker run -d `
        --name $Current `
        --network $Network `
        -e VERSION=$Current `
        $Image

    if ($LASTEXITCODE -ne 0) {
        throw "Could not create $Current."
    }

}
else {

    $CurrentRunning = & $Docker ps -q --filter "name=^$Current$"

    if (-not $CurrentRunning) {

        Write-Host "$Current exists but is stopped."
        Write-Host "Starting $Current..."

        & $Docker start $Current

        if ($LASTEXITCODE -ne 0) {
            throw "Could not start $Current."
        }
    }
}

Write-Host "$Current is ready."

# --------------------------------------------------
# 5. Start new version and health check
# --------------------------------------------------

Write-Host "Health checking $New..."

$MaxRetries = 12
$RetryDelay = 2
$Healthy = $false

for ($i = 1; $i -le $MaxRetries; $i++) {

    Write-Host "Health check attempt $i/$MaxRetries..."

    try {
        $healthResult = & $Docker exec $New python -c "import urllib.request; r=urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=5); print(r.status); print(r.read().decode())" 2>&1

        if ($LASTEXITCODE -eq 0 -and $healthResult -match "200") {
            Write-Host "Health check passed!"
            Write-Host $healthResult
            $Healthy = $true
            break
        }
    }
    catch {
        Write-Host "Health check failed. Retrying..."
    }

    Start-Sleep -Seconds $RetryDelay
}

if (-not $Healthy) {
    Write-Host "Health check failed after $MaxRetries attempts."
    Write-Host "Container logs:"
    & $Docker logs $New
    throw "New version failed health check."
}
# --------------------------------------------------
# 6. Switch Nginx traffic
# --------------------------------------------------

Write-Host "[6/6] Switching traffic to $New..."

$Backup = "$NginxConfig.backup"

Copy-Item $NginxConfig $Backup -Force

$config = Get-Content $NginxConfig -Raw

$config = $config -replace "server $Current`:5000;", "server $New`:5000;"

Set-Content $NginxConfig $config -NoNewline

Write-Host "Testing Nginx configuration..."

& $Docker exec $NginxContainer nginx -t

if ($LASTEXITCODE -ne 0) {

    Write-Host "Nginx configuration failed."

    & $Docker logs $NginxContainer

    Write-Host "Rolling back..."

    Copy-Item $Backup $NginxConfig -Force

    & $Docker exec $NginxContainer nginx -s reload

    & $Docker rm -f $New

    throw "Nginx configuration test failed."
}

Write-Host "Nginx configuration is valid."

# --------------------------------------------------
# Reload Nginx
# --------------------------------------------------

Write-Host "Reloading Nginx..."

& $Docker exec $NginxContainer nginx -s reload

if ($LASTEXITCODE -ne 0) {

    Write-Host "Nginx reload failed."

    Copy-Item $Backup $NginxConfig -Force

    & $Docker exec $NginxContainer nginx -s reload

    & $Docker rm -f $New

    throw "Nginx reload failed."
}

Write-Host "Traffic switched to $New."

# --------------------------------------------------
# Test through Nginx
# --------------------------------------------------

Write-Host "Testing application through Nginx..."

$TestResult = & $Docker run --rm `
    --network $Network `
    python:3.12-slim `
    python -c "import urllib.request; r=urllib.request.urlopen('http://$NginxContainer/', timeout=5); print('HTTP STATUS:', r.status); print(r.read().decode()); exit(0 if r.status == 200 else 1)"

if ($LASTEXITCODE -ne 0) {

    Write-Host "Application test failed."

    Copy-Item $Backup $NginxConfig -Force

    & $Docker exec $NginxContainer nginx -s reload

    & $Docker rm -f $New

    throw "Application test failed."
}

Write-Host "Application is responding through Nginx."

# --------------------------------------------------
# Remove old version
# --------------------------------------------------

Write-Host "Removing old version: $Current..."

& $Docker rm -f $Current

Remove-Item $Backup -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "======================================"
Write-Host " Deployment Successful!"
Write-Host " Live version: $New"
Write-Host "======================================"
