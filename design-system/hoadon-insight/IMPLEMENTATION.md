# Implementation decisions

UI production dùng Material 3 với system sans-serif để chữ tiếng Việt ổn định trên Android/iOS, thay cho font display trong bản gợi ý ban đầu. Màu xanh dương biểu thị tin cậy, xanh lá cho trạng thái ngân sách an toàn và màu error chỉ dành cho lỗi/hành động phá hủy.

Các nguyên tắc đã áp dụng: touch target tối thiểu 48dp, label luôn hiện trên form, validation inline kèm summary live-region, không dùng màu làm tín hiệu duy nhất, responsive NavigationBar/NavigationRail, loading/empty/error/recovery cho các màn hình dữ liệu và motion tiết chế theo Material.
