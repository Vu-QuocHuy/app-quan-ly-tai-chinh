# Finmi Dual Web Instance Launcher
# -Metrics : also open the realtime metrics page (http://localhost:8090/metrics.html)
param([switch]$Metrics)
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "  KHOI CHAY 2 INSTANCE FINMI (PORT 8080 & PORT 8081) + TRANG DIEU KHIEN (PORT 8090)" -ForegroundColor Green
Write-Host "  Port 8080 = B0 (GOC, moi toi uu TAT) | Port 8081 = B1 (TOI UU, bat het)" -ForegroundColor Yellow
Write-Host "  Hai ban dung cung Supabase; AI_FLAG_PROFILE ep bo co tung ban (chi o debug)." -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $scriptDir

Write-Host "`n[1/3] Dang khoi dong B0 - GOC (Port 8080)..." -ForegroundColor White
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$projectDir'; flutter run -d web-server --web-port=8080 --web-hostname=localhost --dart-define=APP_ENV=dev --dart-define=AI_FLAG_PROFILE=b0 --dart-define=AI_LAB=true --dart-define-from-file=config/supabase.local.json"

Write-Host "[2/3] Dang khoi dong B1 - TOI UU (Port 8081)..." -ForegroundColor White
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$projectDir'; flutter run -d web-server --web-port=8081 --web-hostname=localhost --dart-define=APP_ENV=dev --dart-define=AI_FLAG_PROFILE=b1 --dart-define=AI_LAB=true --dart-define-from-file=config/supabase.local.json"

$controllerDir = Join-Path $projectDir "tool\demo\controller"
Write-Host "[3/3] Dang khoi dong trang dieu khien (Port 8090)..." -ForegroundColor White
Start-Process python -WindowStyle Minimized -ArgumentList "-m", "http.server", "8090", "--directory", "`"$controllerDir`""

Write-Host "`nDang doi web server khoi dong truoc khi mo trinh duyet..." -ForegroundColor Gray
Start-Sleep -Seconds 5

Start-Process "http://localhost:8090/"
if ($Metrics) { Start-Process "http://localhost:8090/metrics.html" }

Write-Host "`nDa mo trang dieu khien: http://localhost:8090/ (1 nut -> ca 2 ban)" -ForegroundColor Green
Write-Host "Trang so lieu realtime: http://localhost:8090/metrics.html (them -Metrics de tu mo, hoac bam nut 'Mo trang so lieu')" -ForegroundColor Green
Write-Host "Du phong (2 tab rieng): http://localhost:8080/ va http://localhost:8081/" -ForegroundColor Yellow
Write-Host "Meo: Nhan Win + Mui ten Trai / Win + Mui ten Phai de xep 2 tab nam canh nhau!`n" -ForegroundColor Yellow
