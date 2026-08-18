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
else {
    $Current = "demo-v2"
    $New = "demo-v1"
}

Write-Host "Current version: $Current"
Write-Host "New version: $New"

# --------------------------------------------------
# 2. Make sure Docker network exists
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
# 3. Make sure current version exists
# --------------------------------------------------

Write-Host "[3/6] Checking current application..."

$CurrentContainer = & $Docker ps -aq --filter "name=^$Current$"

if ($CurrentContainer) {

    $CurrentRunning = & $Docker ps -q --filter "name=^$Current$"

    if ($CurrentRunning) {
        Write-Host "$Current is already running."
    }
    else {
        Write-Host "$Current exists but is stopped. Starting it..."

        & $Docker start $Current

        if ($LASTEXITCODE -ne 0) {
            throw "Could not start existing $Current container."
        }
    }

}
else {

    Write-Host "$Current does not exist. Creating it..."

    & $Docker run -d `
        --name $Current `
        --network $Network `
        -e VERSION=$Current `
        $Image

    if ($LASTEXITCODE -ne 0) {
        throw "Could not create $Current container."
    }
}

Start-Sleep -Seconds 3

Write-Host "$Current is ready."
# --------------------------------------------------
# 4. Start new version
# --------------------------------------------------

Write-Host "[4/6] Starting $New..."

$existing = & $Docker ps -aq --filter "name=^$New$"

if ($existing) {
    Write-Host "Removing existing $New container..."
    & $Docker rm -f $New
}

& $Docker run -d `
    --name $New `
    --network $Network `
    -e VERSION=$New `
    $Image

if ($LASTEXITCODE -ne 0) {
    throw "Could not start $New"
}

Write-Host "$New container started."

# --------------------------------------------------
# 5. Health check
# --------------------------------------------------

Write-Host "[5/6] Health checking $New..."

$Healthy = $false

for ($i = 1; $i -le 30; $i++) {

    # Check that container is still running
    $Running = & $Docker ps -q --filter "name=^$New$"

    if (-not $Running) {
        Write-Host "$New container is not running."
        break
    }

    # Check application health endpoint
    $healthResult = & $Docker exec $New python -c "import urllib.request; r=urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=5); print(r.status)" 2>&1

    $exitCode = $LASTEXITCODE

    Write-Host "Health check response: $healthResult"

    if ($exitCode -eq 0 -and "$healthResult" -match "200") {
        $Healthy = $true
        Write-Host "$New is healthy!"
        break
    }

    Write-Host "Waiting for application... ($i/30)"
    Start-Sleep -Seconds 2
}

if (-not $Healthy) {

    Write-Host "Health check failed."
    Write-Host "Container logs:"
    & $Docker logs $New

    Write-Host "Rolling back..."

    & $Docker rm -f $New

    throw "Deployment failed because health check failed."
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
    Write-Host "Rolling back..."

    Copy-Item $Backup $NginxConfig -Force

    & $Docker exec $NginxContainer nginx -s reload

    & $Docker rm -f $New

    throw "Nginx configuration test failed."
}

# Reload Nginx
& $Docker exec $NginxContainer nginx -s reload

if ($LASTEXITCODE -ne 0) {

    Write-Host "Nginx reload failed."
    Write-Host "Rolling back..."

    Copy-Item $Backup $NginxConfig -Force

    & $Docker exec $NginxContainer nginx -s reload

    & $Docker rm -f $New

    throw "Nginx reload failed."
}

Write-Host "Traffic switched to $New."

# --------------------------------------------------
# Test application through Nginx
# --------------------------------------------------

Write-Host "Testing application through Nginx..."

& $Docker run --rm `
    --network $Network `
    python:3.12-slim `
    python -c "import urllib.request; r=urllib.request.urlopen('http://$NginxContainer/', timeout=5); print('HTTP STATUS:', r.status); print(r.read().decode()); exit(0 if r.status == 200 else 1)"

if ($LASTEXITCODE -ne 0) {

    Write-Host "Application test failed."
    Write-Host "Rolling back..."

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

& $Docker rm -f $Current 2>$null

Remove-Item $Backup -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "======================================"
Write-Host " Deployment Successful!"
Write-Host " Live version: $New"
Write-Host "======================================"
