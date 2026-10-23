@echo off
chcp 65001 >nul
pushd "%~dp0.."

echo ====================================================================
echo   Khoi chay 2 Instance Finmi [Port 8080 va Port 8081]
echo   Moi instance deu duoc dong khung dien thoai tu dong!
echo ====================================================================
echo.
echo [1/2] Dang mo Terminal cho May 1 [Port 8080]...
start "Finmi - May 1 [Port 8080]" cmd /k flutter run -d web-server --web-port=8080 --web-hostname=localhost --dart-define=APP_ENV=dev --dart-define-from-file=config/supabase.local.json

echo [2/2] Dang mo Terminal cho May 2 [Port 8081]...
start "Finmi - May 2 [Port 8081]" cmd /k flutter run -d web-server --web-port=8081 --web-hostname=localhost --dart-define=APP_ENV=dev --dart-define-from-file=config/supabase.local.json

echo.
echo Dang mo 2 tab tren trinh duyet...
start http://localhost:8080/
start http://localhost:8081/

popd

