import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocaleNotifier extends Notifier<Locale> {
  static const _prefKey = 'finmi.app_language.v1';

  @override
  Locale build() {
    _loadFromPrefs();
    return const Locale('vi');
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefKey);
      if (code != null && (code == 'en' || code == 'vi')) {
        state = Locale(code);
      }
    } catch (_) {}
  }

  Future<void> setLocale(String languageCode) async {
    if (languageCode != 'en' && languageCode != 'vi') return;
    state = Locale(languageCode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, languageCode);
    } catch (_) {}
  }

  Future<void> toggle() async {
    final next = state.languageCode == 'vi' ? 'en' : 'vi';
    await setLocale(next);
  }
}

final appLocaleProvider = NotifierProvider<AppLocaleNotifier, Locale>(() {
  return AppLocaleNotifier();
});

class AppStrings {
  const AppStrings(this.locale);
  final Locale locale;

  bool get isEn => locale.languageCode == 'en';

  static AppStrings of(BuildContext context) {
    final loc = Localizations.maybeLocaleOf(context) ?? const Locale('vi');
    return AppStrings(loc);
  }

  // Common
  String get appName => 'Finmi';
  String get cancel => isEn ? 'Cancel' : 'Hủy';
  String get save => isEn ? 'Save' : 'Lưu';
  String get delete => isEn ? 'Delete' : 'Xóa';
  String get edit => isEn ? 'Edit' : 'Sửa';
  String get confirm => isEn ? 'Confirm' : 'Xác nhận';
  String get close => isEn ? 'Close' : 'Đóng';
  String get retry => isEn ? 'Retry' : 'Thử lại';
  String get back => isEn ? 'Back' : 'Quay lại';
  String get search => isEn ? 'Search' : 'Tìm kiếm';
  String get all => isEn ? 'All' : 'Tất cả';
  String get other => isEn ? 'Other' : 'Khác';
  String get loading => isEn ? 'Loading…' : 'Đang tải…';
  String get success => isEn ? 'Success' : 'Thành công';

  // Navigation
  String get navOverview => isEn ? 'Overview' : 'Tổng quan';
  String get navBudgets => isEn ? 'Budgets' : 'Ngân sách';
  String get navGroups => isEn ? 'Groups' : 'Nhóm';
  String get navSettings => isEn ? 'Settings' : 'Cài đặt';
  String get navScanTooltip => isEn ? 'Scan QR or receipt' : 'Quét QR thanh toán hoặc hóa đơn';
  String get navCancelImport => isEn ? 'Cancel import' : 'Hủy nhập';
  String get navTransaction => isEn ? 'Transaction' : 'Giao dịch';

  // Overview / Home
  String greeting(String name) => isEn ? 'Hello $name,' : 'Chào $name,';
  String get trackDaily => isEn ? 'Track your daily finances' : 'Theo dõi chi tiêu mỗi ngày';
  String monthLabel(int month, int year) => isEn ? 'Month $month, $year' : 'Tháng $month, $year';
  String get totalBalance => isEn ? 'Total Balance' : 'Tổng số dư';
  String get monthlyIncome => isEn ? 'Income this month' : 'Thu nhập tháng này';
  String get monthlyExpense => isEn ? 'Expense this month' : 'Chi tiêu tháng này';
  String get netDebts => isEn ? 'Debts' : 'Khoản nợ';
  String get toCollect => isEn ? 'To collect' : 'Cần thu';
  String get toPay => isEn ? 'To pay' : 'Cần trả';
  String get noActiveDebts => isEn ? 'No active debts' : 'Không có nợ';
  String get balanceTooltip => isEn
      ? 'Income minus expenses recorded in the selected month'
      : 'Thu nhập trừ chi tiêu đã ghi nhận trong tháng đang chọn';
  String get showAmount => isEn ? 'Show amount' : 'Hiện số tiền';
  String get hideAmount => isEn ? 'Hide amount' : 'Ẩn số tiền';
  String get utilities => isEn ? 'Utilities' : 'Tiện ích';
  String get manageYourWay => isEn ? 'Manage finances your way' : 'Quản lý theo cách của bạn';
  String get utilAdd => isEn ? 'Add +/-' : 'Thêm thu/chi';
  String get utilStats => isEn ? 'Statistics' : 'Thống kê';
  String get utilPlans => isEn ? 'Recurring' : 'Thu chi định kỳ';
  String get utilBudgets => isEn ? 'Budgets' : 'Ngân sách';
  String get utilGroups => isEn ? 'Groups' : 'Nhóm';
  String get utilDebts => isEn ? 'Debts' : 'Quản lý nợ';
  String get utilCategories => isEn ? 'Categories' : 'Danh mục';
  String get utilReports => isEn ? 'Export' : 'Xuất báo cáo';
  String get recentTransactions => isEn ? 'Recent Transactions' : 'Giao dịch gần đây';
  String get history => isEn ? 'History' : 'Lịch sử';
  String get viewHistory => isEn ? 'History ›' : 'Lịch sử ›';
  String get notifications => isEn ? 'Notifications' : 'Thông báo';
  String get noTransactionsYet => isEn ? 'No transactions yet' : 'Chưa có khoản chi nào';
  String get addFirstTransaction => isEn ? 'Add your first transaction or scan a receipt.' : 'Thêm khoản chi đầu tiên hoặc quét một hóa đơn.';
  String get addExpenseBtn => isEn ? 'Add expense' : 'Thêm khoản chi';

  // Debts
  String get debtManagement => isEn ? 'Debt Management' : 'Quản lý nợ';
  String get debtAll => isEn ? 'All' : 'Tất cả';
  String get debtToCollect => isEn ? 'To collect' : 'Cần thu';
  String get debtToPay => isEn ? 'To pay' : 'Cần trả';
  String get debtSettled => isEn ? 'Settled' : 'Đã xong';
  String get debtSearchHint => isEn ? 'Search by name or note…' : 'Tìm theo tên hoặc ghi chú...';
  String get debtTheyOwe => isEn ? 'They owe you' : 'Người khác nợ bạn';
  String get debtYouOwe => isEn ? 'You owe them' : 'Bạn nợ người khác';
  String get debtRemaining => isEn ? 'Remaining' : 'Còn lại';
  String get debtCollectAction => isEn ? 'Collect' : 'Thu hồi';
  String get debtPayAction => isEn ? 'Pay' : 'Thanh toán';
  String get debtPaidTag => isEn ? 'Paid' : 'Đã thanh toán';
  String get debtAddTooltip => isEn ? 'Add debt record' : 'Thêm khoản nợ';
  String get debtNotificationsTitle => isEn ? 'Debt Notifications' : 'Thông báo nợ';
  String get debtNoNotifications => isEn ? 'No debt notifications yet.' : 'Chưa có thông báo nợ nào.';
  String get debtPersonalPhone => isEn ? 'Personal Phone Number' : 'Số điện thoại cá nhân';
  String get debtPhoneRegistered => isEn ? 'Used to receive in-app debt notifications.' : 'Dùng để nhận thông báo nợ trong app.';
  String get debtSettleTitle => isEn ? 'Confirm Payment' : 'Xác nhận thanh toán';

  // Planning (Thu chi định kỳ)
  String get planTitle => isEn ? 'Recurring Plans' : 'Thu chi định kỳ';
  String get planSubtitle => isEn
      ? 'Fixed income and expenses that repeat periodically.'
      : 'Các khoản thu nhập và chi tiêu cố định lặp lại theo chu kỳ.';
  String get recurringIncomeSection => isEn ? '↓ Recurring Income' : '↓ Khoản thu định kỳ';
  String get recurringExpenseSection => isEn ? '↑ Recurring Bills' : '↑ Khoản chi định kỳ';
  String get savingsGoalSection => isEn ? 'Savings Goals' : 'Mục tiêu tiết kiệm';
  String get noRecurringIncome => isEn ? 'No recurring income yet' : 'Chưa có khoản thu định kỳ';
  String get noRecurringIncomeDesc => isEn
      ? 'Add your monthly salary or regular income sources to monitor cash flow.'
      : 'Thêm lương hoặc các nguồn thu nhập cố định hàng tháng để theo dõi dòng tiền ổn định.';
  String get addRecurringIncomeBtn => isEn ? 'Add income' : 'Thêm khoản thu';
  String get noRecurringExpense => isEn ? 'No recurring bills yet' : 'Chưa có khoản chi định kỳ';
  String get noRecurringExpenseDesc => isEn
      ? 'Add rent, internet, phone bills... to get automatic due reminders.'
      : 'Thêm tiền thuê nhà, internet, gói cước... để được Finmi nhắc nhở khi đến hạn thanh toán.';
  String get addRecurringExpenseBtn => isEn ? 'Add bill' : 'Thêm khoản chi';
  String get noSavingsGoal => isEn ? 'No savings goals yet' : 'Chưa có mục tiêu tiết kiệm';
  String get noSavingsGoalDesc => isEn
      ? 'Set goals for shopping, emergency funds or travel to track progress.'
      : 'Đặt mục tiêu mua sắm, tích lũy khẩn cấp hoặc du lịch để kiểm soát tiến độ để dành tiền.';
  String get addSavingsGoalBtn => isEn ? 'Add goal' : 'Thêm mục tiêu';

  // Assistant & Floating
  String get aiAssistant => isEn ? 'AI Assistant' : 'Trợ lý AI';

  // Overview / Home extras
  String get todaySpending => isEn ? 'Today’s Spending' : 'Chi tiêu hôm nay';
  String todaySpent(String amount) => isEn ? 'Spent $amount · Tap to view' : 'Đã chi $amount · Chạm để xem';
  String get bannerSemantics => isEn
      ? 'Track daily finances. Scan receipts and log expenses. Tap to scan.'
      : 'Theo dõi chi tiêu mỗi ngày. Quét hóa đơn, ghi lại khoản chi. Chạm để quét hóa đơn.';
  String get viewHistoryPage => isEn ? 'History page ›' : 'Trang lịch sử ›';
  String get openHistoryTransactions => isEn ? 'View all transaction history' : 'Xem toàn bộ lịch sử thu chi';
  String get markAllRead => isEn ? 'Mark all read' : 'Đã đọc tất cả';
  String get noNotifications => isEn ? 'No notifications at this time.' : 'Hiện không có thông báo nào.';
  String receiptsNeedReview(int count) => isEn ? '$count receipt(s) need review' : '$count hóa đơn cần kiểm tra';
  String get tapToVerifyAndApprove => isEn ? 'Tap to verify and approve' : 'Chạm để rà soát và lưu hóa đơn';
  String get duePrefix => isEn ? 'Due: ' : 'Hạn: ';

  // Budgets
  String get budgetLimits => isEn ? 'Budget Limits' : 'Hạn mức ngân sách';
  String get manageCategories => isEn ? 'Manage categories' : 'Quản lý danh mục';
  String get monthlySpending => isEn ? 'Monthly Spending' : 'Chi tiêu tháng này';
  String get hideOverBudget => isEn ? 'Hide over-budget categories' : 'Ẩn danh mục vượt hạn mức';
  String get showOverBudget => isEn ? 'Show over-budget categories' : 'Xem danh mục vượt hạn mức';
  String overBudgetCategoriesCount(int count) => isEn ? '$count categories over budget' : '$count danh mục vượt hạn mức';
  String get overBudgetCategories => isEn ? 'Over-budget categories' : 'Danh mục vượt hạn mức';
  String get noOverBudgetCategories => isEn ? 'No categories over budget.' : 'Chưa có danh mục nào vượt hạn mức.';
  String overBy(String amount) => isEn ? 'Over by $amount' : 'Vượt $amount';
  String get unlimited => isEn ? 'Unlimited' : 'Không giới hạn';
  String unlimitedSpent(String spent) => isEn ? 'Unlimited · Spent $spent' : 'Không giới hạn · Đã chi $spent';
  String budgetLimitSpent(String limit, String spent, int percent) =>
      isEn ? 'Limit: $limit · Spent $spent ($percent%)' : 'Hạn mức: $limit · Đã chi $spent ($percent%)';
  String editBudgetFor(String category) => isEn ? 'Edit budget for $category' : 'Sửa ngân sách $category';
  String budgetFor(String category) => isEn ? 'Budget: $category' : 'Ngân sách $category';
  String get monthlyLimit => isEn ? 'Monthly limit' : 'Hạn mức tháng';
  String get budgetInputHelper => isEn ? 'Leave empty or 0 for unlimited.' : 'Để trống hoặc nhập 0 để không giới hạn.';
  String get deleteBudgetTitle => isEn ? 'Delete budget limit?' : 'Xóa hạn mức ngân sách?';
  String deleteBudgetDesc(String category) => isEn
      ? 'Category “$category” will reset to unlimited.'
      : 'Danh mục “$category” sẽ trở về không giới hạn.';
  String get deleteLimitBtn => isEn ? 'Delete limit' : 'Xóa hạn mức';

  // Month navigation
  String get previousMonth => isEn ? 'Previous month' : 'Tháng trước';
  String get nextMonth => isEn ? 'Next month' : 'Tháng sau';
  String get selectMonth => isEn ? 'Select Month' : 'Chọn tháng';
  String get previousYear => isEn ? 'Previous year' : 'Năm trước';
  String get nextYear => isEn ? 'Next year' : 'Năm sau';
  String get thisMonth => isEn ? 'This month' : 'Tháng này';
  String monthShort(int m) => isEn ? 'M$m' : 'Th $m';

  // History & Invoices Tabs
  String get tabAll => isEn ? 'All' : 'Tất cả';
  String get tabExpenses => isEn ? 'Expenses' : 'Khoản chi';
  String get tabIncome => isEn ? 'Income' : 'Khoản thu';
  String get tabDebts => isEn ? 'Debts' : 'Thông báo nợ';
  String get tabNeedsReview => isEn ? 'Needs review' : 'Cần kiểm tra';
  String get filterBtn => isEn ? 'Filter' : 'Lọc';
  String get searchTransactionsHint => isEn ? 'Search income or expense transactions' : 'Tìm giao dịch thu hoặc chi';
  String get transactionsNeedReviewTitle => isEn ? 'Transactions need review' : 'Giao dịch cần kiểm tra';
  String get transactionsNeedReviewDesc => isEn
      ? 'Some receipts need confirmation before being included in reports and budgets.'
      : 'Có khoản chi chưa được xác nhận. Kiểm tra trước khi tính vào báo cáo và ngân sách.';
  String get viewNeedsReviewBtn => isEn ? 'View transactions to review' : 'Xem các khoản cần kiểm tra';

  // Groups
  String get myGroups => isEn ? 'My Groups' : 'Nhóm của tôi';
  String get createGroup => isEn ? 'Create Group' : 'Tạo nhóm';
  String get joinGroup => isEn ? 'Join' : 'Tham gia';
  String get refreshGroups => isEn ? 'Refresh groups' : 'Làm mới nhóm';
  String get groupNeedsAuth => isEn ? 'Sign in to create or join groups.' : 'Đăng nhập tài khoản để tạo hoặc tham gia nhóm.';
  String get noGroupsYet => isEn ? 'No groups or shared funds yet' : 'Chưa có nhóm hoặc quỹ chung';
  String get noGroupsDesc => isEn
      ? 'Create a family group, invite members to share expenses.'
      : 'Tạo nhóm gia đình, mời mọi người cùng ghi thu chi vào quỹ.';
  String get groupNameLabel => isEn ? 'Group name' : 'Tên nhóm';
  String get groupNameHint => isEn ? 'e.g. Family Fund' : 'Ví dụ: Quỹ gia đình';
  String get groupFund => isEn ? 'Group Fund' : 'Quỹ chung';
  String get splitBill => isEn ? 'Split Bill' : 'Chia tiền';
  String membersCount(int count) => isEn ? 'Members ($count)' : 'Thành viên ($count)';
  String get inviteViaQr => isEn ? 'Invite via QR' : 'Mời thành viên bằng QR';
  String get collapseMembers => isEn ? 'Collapse members' : 'Thu gọn thành viên';
  String viewAllMembers(int count) => isEn ? 'View all $count members' : 'Xem tất cả $count thành viên';
  String sharedBillsCount(int count) => isEn ? 'Shared Bills ($count)' : 'Chia tiền ($count)';
  String get noSharedBills => isEn ? 'No shared bills in this group yet.' : 'Chưa có lần chia tiền nào trong nhóm.';
  String get collapse => isEn ? 'Collapse' : 'Thu gọn';
  String viewAllCount(int count) => isEn ? 'View all ($count)' : 'Xem tất cả ($count)';
  String get scanQrCode => isEn ? 'Scan QR code' : 'Quét mã QR';
  String get enterInviteCode => isEn ? 'Enter invite code' : 'Nhập mã mời';
  String get scanInviteQr => isEn ? 'Scan invite QR' : 'Quét mã mời';
  String get invalidQrInvite => isEn
      ? 'This QR code is not a valid invite link.'
      : 'Mã QR này không phải mã mời nhóm hoặc bill.';
  String get joinGroupOrBill => isEn ? 'Join Group or Bill' : 'Tham gia nhóm hoặc bill';
  String get inviteCodeLabel => isEn ? 'Invite code' : 'Mã mời';
  String get inviteCodeHint => isEn
      ? '8-character group code or 10-character bill code'
      : 'Mã nhóm 8 ký tự hoặc mã bill 10 ký tự';
  String get groupRoleOwner => isEn ? 'Owner' : 'Chủ nhóm';
  String get groupRoleMember => isEn ? 'Member' : 'Thành viên';
  String get groupRoleGuest => isEn ? 'Guest' : 'Khách';
  String get youTag => isEn ? 'You' : 'Bạn';
  String get manageMemberTooltip => isEn ? 'Manage member' : 'Quản lý thành viên';
  String get transferOwnership => isEn ? 'Transfer ownership' : 'Chuyển quyền chủ nhóm';
  String get revokeOwnership => isEn ? 'Revoke ownership' : 'Thu hồi quyền chủ nhóm';
  String get removeFromGroup => isEn ? 'Remove from group' : 'Xóa khỏi nhóm';
  String get deleteSplitPrompt => isEn ? 'Delete this shared bill?' : 'Xóa lần chia tiền?';
  String deleteSplitDesc(String desc) => isEn ? '“$desc” will be removed from the group.' : '“$desc” sẽ bị xóa khỏi nhóm.';
  String get deleteMemberPrompt => isEn ? 'Remove member?' : 'Xóa thành viên?';
  String deleteMemberDesc(String name) => isEn
      ? '“$name” will no longer be able to add expenses to this group.'
      : '“$name” sẽ không thể thêm khoản chi mới vào nhóm này.';
  String get deleteGroupPrompt => isEn ? 'Delete group?' : 'Xóa nhóm?';
  String get deleteGroupDesc => isEn
      ? 'The group and all shared expenses will be permanently deleted.'
      : 'Nhóm và toàn bộ khoản chia trong nhóm sẽ bị xóa vĩnh viễn.';
  String get leaveGroupPrompt => isEn ? 'Leave group?' : 'Rời nhóm?';
  String get leaveGroupDesc => isEn
      ? 'You will no longer view or add expenses to this group.'
      : 'Bạn sẽ không còn xem hoặc thêm khoản chi vào nhóm này.';
  String payerLabel(String name) => isEn ? 'Payer: $name' : 'Người trả: $name';
  String get sharedFromPersonal => isEn ? 'Shared from personal receipt' : 'Hóa đơn được chia sẻ từ hóa đơn cá nhân';
  String get paidTag => isEn ? 'Paid' : 'Đã trả';
  String get iHavePaid => isEn ? 'I have paid' : 'Tôi đã thanh toán';
  String get settlementSuggestions => isEn ? 'Payment Suggestions' : 'Gợi ý thanh toán';
  String transferText(String from, String amount, String to) => isEn
      ? '$from pays $amount to $to'
      : '$from trả $amount cho $to';
  String get balanced => isEn ? 'Balanced' : 'Đã cân bằng';
  String shouldReceive(String amount) => isEn ? 'to receive $amount' : 'được nhận $amount';
  String shouldPay(String amount) => isEn ? 'to pay $amount' : 'cần trả $amount';
  String get shareInbox => isEn ? 'Share Inbox' : 'Hộp thư chia sẻ';
  String get totalInvoice => isEn ? 'Total Invoice' : 'Tổng hóa đơn';
  String get yourShare => isEn ? 'Your share' : 'Phần của bạn';

  // Categories
  String get addCategory => isEn ? 'Add Category' : 'Thêm danh mục';
  String get editCategory => isEn ? 'Edit Category' : 'Chỉnh sửa danh mục';
  String get deleteCategory => isEn ? 'Delete Category' : 'Xóa danh mục';
  String get expensesKind => isEn ? 'Expenses' : 'Khoản chi';
  String get incomeKind => isEn ? 'Income' : 'Khoản thu';
  String get defaultCategory => isEn ? 'Default category' : 'Danh mục mặc định';
  String get customCategory => isEn ? 'Custom category' : 'Danh mục tùy chỉnh';
  String get categoryNameLabel => isEn ? 'Category name' : 'Tên danh mục';
  String get categoryNameHint => isEn ? 'e.g. Stationery' : 'Ví dụ: Văn phòng phẩm';
  String get categoryIcons => isEn ? 'Icons' : 'Biểu tượng';
  String get categoryColors => isEn ? 'Colors' : 'Màu sắc';
  String categoryLimitLabel(String month) => isEn ? 'Monthly limit $month' : 'Hạn mức tháng $month';
  String get categoryLimitHelper => isEn ? 'Optional; can be adjusted anytime.' : 'Không bắt buộc; có thể chỉnh sửa sau.';
  String get pleaseEnterCategoryName => isEn ? 'Please enter category name.' : 'Hãy nhập tên danh mục.';
  String get categoryNameExists => isEn ? 'Category name already exists.' : 'Tên danh mục đã tồn tại.';
  String get saveCategoryBtn => isEn ? 'Save Category' : 'Lưu danh mục';
  String deleteCategoryPrompt(String name) => isEn ? 'Delete “$name”?' : 'Xóa “$name”?';
  String get deleteCategoryIncomeDesc => isEn
      ? 'Incomes under this category will be moved to “Uncategorized”.'
      : 'Các khoản thu dùng danh mục này sẽ chuyển về “Chưa phân loại”.';
  String get deleteCategoryExpenseDesc => isEn
      ? 'Receipts under this category will be moved to “Other”. Budget and merchant rules will be deleted.'
      : 'Hóa đơn đang dùng danh mục này sẽ chuyển về “Khác”. Ngân sách và quy tắc merchant của danh mục sẽ bị xóa.';

  // Web Phone Frame & Multi-Instance
  String get phoneFrameMode => isEn ? 'Phone Frame' : 'Cỡ điện thoại';
  String get fullScreenMode => isEn ? 'Full Screen' : 'Toàn màn hình';
  String get dualInstanceTip => isEn
      ? 'Open 2 tabs side-by-side (Win + ⬅️ / Win + ➡️) to compare & demo accounts'
      : 'Mở 2 tab đặt cạnh nhau (Win + ⬅️ / Win + ➡️) để so sánh 2 tài khoản!';

  // Categories translation
  String categoryName(String rawName, {String? categoryId}) =>
      localizedCategoryName(rawName, categoryId: categoryId, isEn: isEn);

  // Settings
  String get settingsTitle => isEn ? 'Settings & Sync' : 'Cài đặt và đồng bộ';
  String get secAccountAndSync => isEn ? 'Account & Sync' : 'Tài khoản & đồng bộ';
  String get accountTitle => isEn ? 'Account' : 'Tài khoản';
  String get syncDataTitle => isEn ? 'Data Sync' : 'Đồng bộ dữ liệu';
  String get restoreCloudTitle => isEn ? 'Restore Customizations' : 'Khôi phục tùy chỉnh';
  String get secCustomization => isEn ? 'Customization' : 'Tùy chỉnh';
  String get appearanceTitle => isEn ? 'Appearance' : 'Giao diện';
  String get themeModeTitle => isEn ? 'Theme Mode' : 'Chế độ sáng tối';
  String get budgetAlertsTitle => isEn ? 'Budget Alerts' : 'Cảnh báo ngân sách';
  String get languageTitle => isEn ? 'Language' : 'Ngôn ngữ';
  String get vietnamese => isEn ? 'Vietnamese' : 'Tiếng Việt';
  String get english => isEn ? 'English' : 'Tiếng Anh';
  String get chooseLanguage => isEn ? 'Select Language' : 'Chọn ngôn ngữ';

  // History & Invoices Extra
  String selectedCount(int count) => isEn ? '$count selected' : 'Đã chọn $count';
  String get cancelSelection => isEn ? 'Cancel selection' : 'Hủy chọn';
  String get selectMultipleExpenses => isEn ? 'Select multiple expenses' : 'Chọn nhiều khoản chi';
  String get selectVisibleItems => isEn ? 'Select visible items' : 'Chọn các khoản đang hiển thị';
  String get deselectVisibleItems => isEn ? 'Deselect visible items' : 'Bỏ chọn các khoản đang hiển thị';
  String get noIncomesYet => isEn ? 'No income records yet' : 'Chưa có khoản thu';
  String get allReviewed => isEn ? 'All transactions reviewed' : 'Đã kiểm tra hết giao dịch';
  String get noTransactionsFound => isEn ? 'No transactions found' : 'Không tìm thấy giao dịch';
  String get noDebtsYet => isEn ? 'No debt records yet' : 'Chưa có khoản nợ nào';
  String get resetFilter => isEn ? 'Reset' : 'Đặt lại';
  String get clearFilters => isEn ? 'Clear filters' : 'Xóa bộ lọc';
  String get unclassified => isEn ? 'Uncategorized' : 'Chưa phân loại';
  String get noSeller => isEn ? 'No merchant name' : 'Chưa có tên người bán';
  String get backToOverview => isEn ? 'Back to Overview' : 'Về Tổng quan';
  String get selectionHint => isEn
      ? 'Select confirmed or review-needed expenses.'
      : 'Chọn các khoản chi đã xác nhận hoặc cần kiểm tra.';
  String get cannotLoadIncomes => isEn ? 'Could not load income records' : 'Không tải được khoản thu';
  String get cannotLoadHistory => isEn ? 'Could not load transaction history' : 'Không tải được lịch sử giao dịch';
  String get debtRecordTitle => isEn ? 'Debt' : 'Khoản nợ';
  String get debtNotificationTitle => isEn ? 'Debt Notification' : 'Thông báo nợ';
}

/// Helper to translate standard category names into English dynamically
String localizedCategoryName(
  String rawName, {
  String? categoryId,
  required bool isEn,
}) {
  if (!isEn) return rawName;
  if (categoryId != null) {
    switch (categoryId) {
      case 'food':
        return 'Food & Dining';
      case 'transport':
        return 'Transportation';
      case 'shopping':
        return 'Shopping';
      case 'utilities':
        return 'Bills & Utilities';
      case 'health':
        return 'Healthcare';
      case 'education':
        return 'Education';
      case 'entertainment':
        return 'Entertainment';
      case 'other':
        return 'Other';
      case 'income_salary':
        return 'Salary';
      case 'income_bonus':
        return 'Bonus & Commission';
      case 'income_investment':
        return 'Investment';
      case 'income_business':
        return 'Business & Sales';
      case 'income_allowance':
        return 'Allowance';
      case 'income_gift':
        return 'Gifts & Donations';
      case 'income_interest':
        return 'Interest & Dividends';
      case 'income_other':
        return 'Other Income';
      case 'income_uncategorized':
      case 'uncategorized':
      case 'unclassified':
        return 'Uncategorized';
    }
  }
  final lower = rawName.trim().toLowerCase();
  switch (lower) {
    case 'chưa phân loại':
      return 'Uncategorized';
    case 'ăn uống':
      return 'Food & Dining';
    case 'di chuyển':
      return 'Transportation';
    case 'mua sắm':
      return 'Shopping';
    case 'tiện ích':
      return 'Bills & Utilities';
    case 'y tế':
      return 'Healthcare';
    case 'giáo dục':
      return 'Education';
    case 'giải trí':
      return 'Entertainment';
    case 'khác':
      return 'Other';
    case 'thu nhập khác':
      return 'Other Income';
    case 'tiền lương':
    case 'lương':
      return 'Salary';
    case 'thưởng & hoa hồng':
    case 'thưởng':
      return 'Bonus & Commission';
    case 'đầu tư & sinh lời':
    case 'đầu tư':
      return 'Investment';
    case 'kinh doanh & bán hàng':
    case 'kinh doanh':
      return 'Business & Sales';
    case 'phụ cấp & trợ cấp':
    case 'phụ cấp':
      return 'Allowance';
    case 'tiền lãi & cổ tức':
    case 'tiền lãi':
    case 'lãi & cổ tức':
      return 'Interest & Dividends';
    case 'được tặng & biếu':
    case 'được tặng':
    case 'tặng & biếu':
      return 'Gifts & Donations';
    default:
      return rawName;
  }
}

extension LocalizationExtension on BuildContext {
  AppStrings get tr => AppStrings.of(this);
}
