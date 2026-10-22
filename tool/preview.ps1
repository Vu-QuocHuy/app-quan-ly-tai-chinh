# Finmi Mobile Preview Studio Launcher
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Finmi Mobile Preview Studio - Multi-Instance Demo" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Đang mở Finmi Mobile Preview Studio trên trình duyệt..." -ForegroundColor Yellow
Start-Process "http://localhost:8080/preview.html"

Write-Host "Đã mở thành công tại: http://localhost:8080/preview.html" -ForegroundColor Green
Write-Host "• Thiết bị 1 (User A): http://localhost:8080/" -ForegroundColor Gray
Write-Host "• Thiết bị 2 (User B): http://127.0.0.1:8080/" -ForegroundColor Gray
