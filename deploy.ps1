$ErrorActionPreference = "Stop"

# ============================================
# Zero Downtime Deployment
# ============================================

$imageName = "zero-downtime-demo-app:latest"
$networkName = "zero-downtime-demo_default"
$nginxContainer = "demo-nginx"

Write-Host "======================================"
Write-Host " Zero Downtime Deployment"
Write-Host "======================================"

# --------------------------------------------
# 1. Detect current active version
# --------------------------------------------

Write-Host "[1/6] Detecting current version..."

$currentVersion = $null

try {
    $nginxConfig = docker exec $nginxContainer cat /etc/nginx/conf.d/default.conf 2>$null

    if ($nginxConfig -match "demo-v1:5000") {
        $currentVersion = "demo-v1"
    }
    elseif ($nginxConfig -match "demo-v2:5000") {
        $currentVersion = "demo-v2"
    }
}
catch {
    $currentVersion = $null
}

# If nginx config doesn't tell us, detect running app
if (-not $currentVersion) {

    $v1Running = docker inspect -f "{{.State.Running}}" demo-v1 2>$null
    $v2Running = docker inspect -f "{{.State.Running}}" demo-v2 2>$null

    if ($v1Running -eq "true" -and $v2Running -ne "true") {
        $currentVersion = "demo-v1"
    }
    elseif ($v2Running -eq "true" -and $v1Running -ne "true") {
        $currentVersion = "demo-v2"
    }
    else {
        # First deployment
        $currentVersion = "demo-v1"
    }
}

if ($currentVersion -eq "demo-v1") {
    $newVersion = "demo-v2"
}
else {
    $newVersion = "demo-v1"
}

Write-Host "Current version: $currentVersion"
Write-Host "New version: $newVersion"

# --------------------------------------------
# 2. Check Docker network
# --------------------------------------------

Write-Host "[2/6] Checking Docker network..."

docker network inspect $networkName 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating Docker network..."
    docker network create $networkName
}

# Make sure nginx is connected
docker network connect $networkName $nginxContainer 2>$null

# --------------------------------------------
# 3. Check Nginx
# --------------------------------------------

Write-Host "[3/6] Checking Nginx..."

$nginxRunning = docker inspect -f "{{.State.Running}}" $nginxContainer 2>$null

if ($nginxRunning -ne "true") {
    throw "Nginx container is not running."
}

Write-Host "Nginx is running."

# --------------------------------------------
# 4. Create new application
# --------------------------------------------

Write-Host "[4/6] Starting $newVersion..."

# Remove old container with same version
docker rm -f $newVersion 2>$null

docker run -d `
    --name $newVersion `
    --network $networkName `
    -e VERSION=$newVersion `
    $imageName

if ($LASTEXITCODE -ne 0) {
    throw "Failed to start $newVersion."
}

Write-Host "$newVersion started."

# --------------------------------------------
# 5. Health check
# --------------------------------------------

Write-Host "[5/6] Health checking $newVersion..."

$healthy = $false

for ($i = 1; $i -le 12; $i++) {

    Write-Host "Health check attempt $i/12..."

    $health = docker exec $nginxContainer wget -qO- "http://${newVersion}:5000/health" 2>$null

    if ($LASTEXITCODE -eq 0 -and $health -match '"status"\s*:\s*"healthy"') {

        Write-Host "Health check passed!"
        Write-Host "Response: $health"

        $healthy = $true
        break
    }

    Write-Host "Health check failed. Retrying..."

    Start-Sleep -Seconds 5
}

if (-not $healthy) {

    Write-Host "Health check failed after 12 attempts."

    Write-Host "Container logs for $newVersion:"

    docker logs $newVersion

    docker rm -f $newVersion 2>$null

    throw "New version failed health check."
}

# --------------------------------------------
# 6. Switch Nginx
# --------------------------------------------

Write-Host "[6/6] Switching Nginx to $newVersion..."

$nginxConfig = @"
server {
    listen 80;

    location / {
        proxy_pass http://${newVersion}:5000;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }
}
"@

$nginxConfig | docker exec -i $nginxContainer sh -c "cat > /etc/nginx/conf.d/default.conf"

if ($LASTEXITCODE -ne 0) {
    docker rm -f $newVersion 2>$null
    throw "Failed to update Nginx configuration."
}

docker exec $nginxContainer nginx -t

if ($LASTEXITCODE -ne 0) {
    Write-Host "Nginx configuration test failed."
    docker exec $nginxContainer cat /etc/nginx/conf.d/default.conf

    docker rm -f $newVersion 2>$null

    throw "Nginx configuration is invalid."
}

docker exec $nginxContainer nginx -s reload

if ($LASTEXITCODE -ne 0) {
    docker rm -f $newVersion 2>$null
    throw "Failed to reload Nginx."
}

Write-Host "Nginx switched to $newVersion."

# --------------------------------------------
# Remove old version
# --------------------------------------------

if ($currentVersion -ne $newVersion) {

    Write-Host "Removing old version: $currentVersion"

    docker rm -f $currentVersion 2>$null
}

Write-Host ""
Write-Host "======================================"
Write-Host " Deployment Successful"
Write-Host " Active version: $newVersion"
Write-Host "======================================"
