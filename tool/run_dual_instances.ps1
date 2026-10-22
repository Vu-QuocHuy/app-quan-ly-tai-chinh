# Finmi Dual Web Instance Launcher
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "  KHOI CHAY 2 INSTANCE FINMI (PORT 8080 & PORT 8081)" -ForegroundColor Green
Write-Host "  Moi may tu dong khung dien thoai, mo 2 tab canh nhau de so sanh!" -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Split-Path -Parent $scriptDir

Write-Host "`n[1/2] Dang khoi dong May 1 (Port 8080)..." -ForegroundColor White
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$projectDir'; flutter run -d web-server --web-port=8080 --web-hostname=localhost --dart-define=APP_ENV=dev --dart-define-from-file=config/supabase.local.json"

Write-Host "[2/2] Dang khoi dong May 2 (Port 8081)..." -ForegroundColor White
Start-Process powershell -ArgumentList "-NoExit", "-Command", "Set-Location '$projectDir'; flutter run -d web-server --web-port=8081 --web-hostname=localhost --dart-define=APP_ENV=dev --dart-define-from-file=config/supabase.local.json"

Write-Host "`nDang doi web server khoi dong truoc khi mo trinh duyet..." -ForegroundColor Gray
Start-Sleep -Seconds 5

Start-Process "http://localhost:8080/"
Start-Process "http://localhost:8081/"

Write-Host "`nDa mo 2 tab: http://localhost:8080/ va http://localhost:8081/" -ForegroundColor Green
Write-Host "Meo: Nhan Win + Mui ten Trai / Win + Mui ten Phai de xep 2 tab nam canh nhau!`n" -ForegroundColor Yellow
