import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../invoices/domain/invoice_models.dart';
import '../application/qr_payment_providers.dart';
import '../data/qr_payment_draft_store.dart';
import '../data/vietqr_directory.dart';
import '../data/vietqr_parser.dart';
import '../domain/qr_payment_draft.dart';

class QrPaymentScreen extends ConsumerStatefulWidget {
  const QrPaymentScreen({super.key});

  @override
  ConsumerState<QrPaymentScreen> createState() => _QrPaymentScreenState();
}

class _QrPaymentScreenState extends ConsumerState<QrPaymentScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  late final QrPaymentDraftStore _store;
  final _directory = VietQrDirectory();
  late final TextEditingController _amountController;
  late final TextEditingController _accountController;
  late final TextEditingController _recipientController;
  late final TextEditingController _memoController;

  QrPaymentDraft? _draft;
  List<VietQrBank> _banks = const [];
  String? _lastBankAppId;
  String? _selectedCategoryId;
  String? _scanError;
  bool _loadingDraft = true;
  bool _scanLocked = false;
  bool _awaitingBankReturn = false;
  bool _leftForBank = false;
  bool _returnedFromBank = false;
  bool _returnPromptShown = false;
  bool _isSaving = false;
  bool _isLaunchingBank = false;
  Future<bool>? _scanEventFuture;

  @override
  void initState() {
    super.initState();
    _store = ref.read(qrPaymentDraftStoreProvider);
    WidgetsBinding.instance.addObserver(this);
    _amountController = TextEditingController();
    _accountController = TextEditingController();
    _recipientController = TextEditingController();
    _memoController = TextEditingController();
    unawaited(_restoreDraft());
    unawaited(_restoreLastBankApp());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountController.dispose();
    _accountController.dispose();
    _recipientController.dispose();
    _memoController.dispose();
    unawaited(_scannerController.dispose());
    _directory.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused) &&
        _awaitingBankReturn) {
      _leftForBank = true;
      return;
    }
    if (state == AppLifecycleState.resumed &&
        _leftForBank &&
        _awaitingBankReturn &&
        _draft != null) {
      _leftForBank = false;
      _awaitingBankReturn = false;
      _showPaymentReturnPrompt();
    }
  }

  Future<void> _restoreDraft() async {
    final draft = await _store.readDraft();
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _loadingDraft = false;
      if (draft != null) {
        _applyDraftToFields(draft);
        _selectedCategoryId = draft.categoryId;
        _returnedFromBank = draft.bankAppId != null;
      }
    });
    if (draft != null) {
      unawaited(_loadBanks());
      if (draft.bankAppId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showPaymentReturnPrompt();
        });
      }
    }
  }

  Future<void> _restoreLastBankApp() async {
    var appId = await _store.readLastBankAppId();
    final preferencesStore = ref.read(profilePreferencesStoreProvider);
    if (preferencesStore?.canSync == true) {
      try {
        final preferences = await preferencesStore!.load();
        final cloudAppId = preferences.preferredBankAppId;
        if (cloudAppId != null && cloudAppId.isNotEmpty) {
          appId = cloudAppId;
          await _store.writeLastBankAppId(cloudAppId);
        }
      } on Object {
        // Keep the last locally selected bank app available offline.
      }
    }
    if (mounted) setState(() => _lastBankAppId = appId);
  }

  Future<void> _syncPreferredBankApp(String appId) async {
    final store = ref.read(profilePreferencesStoreProvider);
    if (store == null || !store.canSync) return;
    try {
      await store.savePreferredBankApp(appId);
    } on Object {
      if (mounted) {
        _showMessage(
          'App ngân hàng đã nhớ trên thiết bị nhưng chưa đồng bộ lên tài khoản.',
        );
      }
    }
  }

  Future<bool> _recordCloudEvent(
    QrPaymentDraft draft,
    String eventType, {
    String? invoiceId,
  }) async {
    final store = ref.read(qrPaymentHistoryStoreProvider);
    if (store == null || !store.canSync) return true;
    try {
      await store.record(draft, eventType, invoiceId: invoiceId);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _loadBanks() async {
    final banks = await _directory.loadBanks();
    if (mounted) setState(() => _banks = banks);
  }

  void _applyDraftToFields(QrPaymentDraft draft) {
    _amountController.text = draft.amountVnd?.toString() ?? '';
    _accountController.text = draft.accountNumber;
    _recipientController.text = draft.recipientName;
    _memoController.text = draft.memo;
  }

  Future<void> _onQrDetected(BarcodeCapture capture) async {
    if (_scanLocked || _draft != null) return;
    final rawPayload = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (rawPayload == null) return;
    _scanLocked = true;

    VietQrPayload payload;
    try {
      payload = VietQrParser.parse(rawPayload);
    } on FormatException catch (error) {
      _showScanError(error.message);
      return;
    } on Object {
      _showScanError('Không thể đọc mã QR này. Hãy thử lại.');
      return;
    }

    try {
      await _scannerController.stop();
    } on Object {
      // The camera may already be stopping as the scanner leaves the view.
    }
    if (!mounted) return;
    final draft = QrPaymentDraft(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      bankBin: payload.bankBin,
      accountNumber: payload.accountNumber,
      recipientName: payload.recipientName,
      memo: payload.memo,
      amountVnd: payload.amountVnd,
    );
    setState(() {
      _draft = draft;
      _selectedCategoryId = null;
      _applyDraftToFields(draft);
      _scanError = null;
    });
    _scanEventFuture = _recordCloudEvent(draft, 'scanned');
    unawaited(_loadBanks());
  }

  void _showScanError(String message) {
    if (!mounted) return;
    setState(() => _scanError = message);
    Future<void>.delayed(const Duration(seconds: 2), () async {
      if (!mounted || _draft != null) return;
      setState(() {
        _scanError = null;
        _scanLocked = false;
      });
      try {
        await _scannerController.start();
      } on Object {
        // Scanner errors are presented by MobileScanner itself.
      }
    });
  }

  QrPaymentDraft _draftFromFields({String? bankAppId}) {
    final current = _draft!;
    return current.copyWith(
      accountNumber: _accountController.text.trim(),
      recipientName: _recipientController.text.trim(),
      memo: _memoController.text.trim(),
      amountVnd: int.tryParse(_amountController.text.trim()),
      categoryId: _selectedCategoryId,
      bankAppId: bankAppId ?? current.bankAppId,
    );
  }

  Future<void> _openLastBankApp() async {
    await _openBankApp(chooseAnother: false);
  }

  Future<void> _chooseBankApp() async {
    await _openBankApp(chooseAnother: true);
  }

  Future<void> _openBankApp({required bool chooseAnother}) async {
    if (!_validateForm()) return;
    final apps = await _directory.loadBankApps();
    if (!mounted) return;
    VietQrBankApp? selected;
    if (!chooseAnother && _lastBankAppId != null) {
      for (final app in apps) {
        if (app.id == _lastBankAppId) {
          selected = app;
          break;
        }
      }
    }
    selected ??= await _showBankAppPicker(apps);
    if (selected == null || !mounted) return;
    await _launchBankApp(selected);
  }

  Future<VietQrBankApp?> _showBankAppPicker(List<VietQrBankApp> apps) {
    return showModalBottomSheet<VietQrBankApp>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final height = MediaQuery.sizeOf(sheetContext).height * 0.72;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chọn app ngân hàng',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Một số ngân hàng có thể tự điền thông tin. Hãy luôn kiểm tra người nhận và số tiền trong app ngân hàng trước khi xác nhận.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: apps.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return ListTile(
                        minTileHeight: 64,
                        leading: const CircleAvatar(
                          child: Icon(Icons.account_balance_outlined),
                        ),
                        title: Text(app.name),
                        subtitle: Text(app.bankName),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(sheetContext, app),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _launchBankApp(VietQrBankApp app) async {
    if (!_validateForm() || _isLaunchingBank) return;
    setState(() => _isLaunchingBank = true);
    final draft = _draftFromFields(bankAppId: app.id);
    try {
      final banks = await _directory.loadBanks();
      if (!mounted) return;
      final receivingBank = banks
          .where((bank) => bank.bin == draft.bankBin)
          .firstOrNull;
      setState(() => _banks = banks);
      final launchUri = app.launchUri(
        bankCode: receivingBank?.code,
        accountNumber: draft.accountNumber,
        amountVnd: draft.amountVnd,
        transferDescription: draft.memo,
        recipientName: draft.recipientName,
      );
      await _store.writeDraft(draft);
      if (!mounted) return;
      ref.invalidate(pendingQrPaymentDraftProvider);
      await _store.writeLastBankAppId(app.id);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _lastBankAppId = app.id;
        _awaitingBankReturn = true;
        _leftForBank = false;
      });
      final opened = await launchUrl(
        launchUri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (opened) {
        _showMessage(
          receivingBank == null
              ? 'Đã mở ${app.name}. Chưa tra được mã ngân hàng; hãy nhập và kiểm tra thông tin chuyển khoản thủ công.'
              : 'Đã mở ${app.name}. Hãy kiểm tra người nhận và số tiền trước khi xác nhận.',
        );
        unawaited(_syncPreferredBankApp(app.id));
        final scanRecorded = await (_scanEventFuture ?? Future.value(true));
        if (scanRecorded) {
          unawaited(_recordCloudEvent(draft, 'bank_opened'));
        }
      }
      if (!opened) {
        final retryableDraft = draft.copyWith(clearBankAppId: true);
        await _store.writeDraft(retryableDraft);
        setState(() {
          _draft = retryableDraft;
          _awaitingBankReturn = false;
          _leftForBank = false;
        });
        _showMessage(
          'Không mở được ${app.name}. Kiểm tra app đã cài đặt hoặc chọn app khác.',
        );
      }
    } on Object {
      if (!mounted) return;
      final retryableDraft = _draft?.copyWith(clearBankAppId: true);
      if (retryableDraft != null) {
        await _store.writeDraft(retryableDraft);
      }
      setState(() {
        _draft = retryableDraft ?? _draft;
        _awaitingBankReturn = false;
        _leftForBank = false;
      });
      _showMessage(
        'Không thể mở app ngân hàng lúc này. Bản nháp vẫn được giữ.',
      );
    } finally {
      if (mounted) setState(() => _isLaunchingBank = false);
    }
  }

  bool _validateForm() {
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    final validCategory = categories.any(
      (category) => category.id == _selectedCategoryId,
    );
    final valid = _formKey.currentState?.validate() == true && validCategory;
    if (!validCategory) {
      _showMessage(
        categories.isEmpty
            ? 'Chưa tải được danh mục. Hãy thử lại sau.'
            : 'Hãy chọn danh mục cho khoản chi.',
      );
    }
    return valid;
  }

  void _showPaymentReturnPrompt() {
    if (!mounted || _draft == null || _returnPromptShown) return;
    _returnPromptShown = true;
    setState(() => _returnedFromBank = true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final action = await showModalBottomSheet<_PaymentReturnAction>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        showDragHandle: true,
        builder: (sheetContext) => _PaymentReturnSheet(
          onPaid: () => Navigator.pop(sheetContext, _PaymentReturnAction.paid),
          onNotPaid: () =>
              Navigator.pop(sheetContext, _PaymentReturnAction.notPaid),
          onEdit: () => Navigator.pop(sheetContext, _PaymentReturnAction.edit),
        ),
      );
      if (!mounted) return;
      switch (action) {
        case _PaymentReturnAction.paid:
          await _confirmPaid();
        case _PaymentReturnAction.notPaid:
          await _cancelDraft();
        case _PaymentReturnAction.edit:
          _showMessage('Sửa các trường phía trên, rồi xác nhận kết quả.');
        case null:
          break;
      }
    });
  }

  Future<void> _confirmPaid() async {
    if (_isSaving || !_validateForm()) return;
    final draft = _draftFromFields();
    final amount = draft.amountVnd!;
    final now = DateTime.now();
    final invoice = InvoiceEntity(
      id: draft.id,
      sellerName: draft.recipientName.isEmpty
          ? 'Chuyển khoản QR'
          : draft.recipientName,
      currencyCode: AppConstants.defaultCurrency,
      subtotalMinor: amount,
      taxMinor: 0,
      totalMinor: amount,
      sourceType: InvoiceSourceType.manual,
      sourceHash: 'qr-payment:${draft.id}',
      status: InvoiceStatus.confirmed,
      categoryId: draft.categoryId,
      notes: draft.memo.isEmpty ? 'Thanh toán VietQR' : draft.memo,
      tags: const ['qr-payment'],
      createdAt: draft.createdAt,
      updatedAt: now,
      confirmedAt: now,
      syncState: InvoiceSyncState.pending,
    );

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(invoiceRepositoryProvider);
      final existing = await repository.findBySourceHash(invoice.sourceHash!);
      if (existing == null) await repository.saveInvoice(invoice);
      final scanRecorded = await (_scanEventFuture ?? Future.value(true));
      final historySaved =
          scanRecorded &&
          await _recordCloudEvent(
            draft,
            'user_confirmed',
            invoiceId: invoice.id,
          );
      await _store.clearDraft();
      if (!mounted) return;
      ref.invalidate(pendingQrPaymentDraftProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            historySaved
                ? 'Đã ghi nhận khoản chi và đưa vào đồng bộ.'
                : 'Khoản chi đã lưu; nhật ký thanh toán QR chưa đồng bộ được.',
          ),
        ),
      );
      context.pop();
    } on Object {
      if (mounted) {
        _showMessage(
          'Chưa lưu được khoản chi. Bản nháp vẫn được giữ để thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _cancelDraft() async {
    final scanRecorded = await (_scanEventFuture ?? Future.value(true));
    if (scanRecorded) {
      await _recordCloudEvent(_draftFromFields(), 'user_cancelled');
    }
    await _store.clearDraft();
    if (!mounted) return;
    ref.invalidate(pendingQrPaymentDraftProvider);
    context.pop();
  }

  Future<void> _copyAccountNumber() async {
    await _copyToClipboard(_accountController.text, 'số tài khoản');
  }

  Future<void> _copyToClipboard(String value, String label) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value.trim()));
    if (mounted) _showMessage('Đã sao chép $label.');
  }

  String _bankLabel(QrPaymentDraft draft) {
    for (final bank in _banks) {
      if (bank.bin == draft.bankBin) return '${bank.shortName} · ${bank.bin}';
    }
    return 'Ngân hàng · ${draft.bankBin}';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          draft == null ? 'Quét QR thanh toán' : 'Kiểm tra khoản chi',
        ),
      ),
      body: _loadingDraft
          ? const Center(child: CircularProgressIndicator())
          : draft == null
          ? _buildScanner(context)
          : _buildDetails(context, draft),
      bottomNavigationBar: draft == null ? null : _buildActions(context),
    );
  }

  Widget _buildScanner(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: _onQrDetected,
              ),
              Center(
                child: Semantics(
                  label: 'Khung quét mã VietQR',
                  child: Container(
                    width: 264,
                    height: 264,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 24,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _scanError ?? 'Đưa mã VietQR vào trong khung quét',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Nếu đăng nhập, thông tin người nhận và trạng thái QR được lưu riêng tư trên cloud. Chỉ khoản chi đã xác nhận mới được ghi vào thu chi.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Bật hoặc tắt đèn pin',
                              onPressed: _scannerController.toggleTorch,
                              icon: const Icon(Icons.flashlight_on_outlined),
                            ),
                            const SizedBox(width: 12),
                            IconButton.filledTonal(
                              tooltip: 'Đổi camera',
                              onPressed: _scannerController.switchCamera,
                              icon: const Icon(Icons.cameraswitch_outlined),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context, QrPaymentDraft draft) {
    final theme = Theme.of(context);
    final categoriesState = ref.watch(categoriesProvider);
    final categories = categoriesState.valueOrNull ?? const [];
    final categoryId =
        categories.any((category) => category.id == _selectedCategoryId)
        ? _selectedCategoryId
        : null;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Kiểm tra người nhận và số tiền trong app ngân hàng trước khi xác nhận chuyển khoản.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Thông tin từ mã QR', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _DetailRow(label: 'Ngân hàng nhận', value: _bankLabel(draft)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _accountController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 34,
            decoration: InputDecoration(
              labelText: 'Số tài khoản / thẻ người nhận',
              suffixIcon: IconButton(
                tooltip: 'Sao chép số tài khoản',
                onPressed: _copyAccountNumber,
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
            validator: (value) {
              final account = value?.trim() ?? '';
              return RegExp(r'^[A-Za-z0-9]{1,34}$').hasMatch(account)
                  ? null
                  : 'Số tài khoản không hợp lệ';
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _recipientController,
            maxLength: 140,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Tên người nhận / cửa hàng',
              hintText: 'Được điền từ mã QR nếu có',
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(12),
            ],
            decoration: InputDecoration(
              labelText: 'Số tiền (VND)',
              hintText: 'Nhập số tiền cần thanh toán',
              prefixText: '₫ ',
              suffixIcon: IconButton(
                tooltip: 'Sao chép số tiền',
                onPressed: () =>
                    _copyToClipboard(_amountController.text, 'số tiền'),
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
            validator: (value) {
              final amount = int.tryParse(value?.trim() ?? '');
              return amount != null && amount > 0
                  ? null
                  : 'Nhập số tiền lớn hơn 0';
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: categoryId,
            decoration: const InputDecoration(labelText: 'Danh mục chi'),
            hint: const Text('Chọn danh mục'),
            items: [
              for (final category in categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name),
                ),
            ],
            onChanged: categories.isEmpty
                ? null
                : (value) => setState(() => _selectedCategoryId = value),
          ),
          if (categoriesState.hasError) ...[
            const SizedBox(height: 8),
            Text(
              'Không tải được danh mục. Kiểm tra dữ liệu cục bộ rồi thử lại.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextFormField(
            controller: _memoController,
            maxLength: 140,
            decoration: InputDecoration(
              labelText: 'Nội dung chuyển khoản',
              hintText: 'Có thể chỉnh sửa nội dung đọc từ QR',
              suffixIcon: IconButton(
                tooltip: 'Sao chép nội dung chuyển khoản',
                onPressed: () => _copyToClipboard(
                  _memoController.text,
                  'nội dung chuyển khoản',
                ),
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Số tài khoản và mã ngân hàng chỉ lưu tạm trên thiết bị rồi được xóa. Tên người nhận, số tiền, danh mục và nội dung sẽ lưu cùng khoản chi để đồng bộ.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: _returnedFromBank
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _confirmPaid,
                      icon: _isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: const Text('Đã thanh toán'),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isSaving ? null : _cancelDraft,
                    icon: const Icon(Icons.close),
                    label: const Text('Chưa thanh toán · Bỏ bản nháp'),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isLaunchingBank ? null : _openLastBankApp,
                      icon: _isLaunchingBank
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.account_balance_outlined),
                      label: Text(
                        _lastBankAppId == null
                            ? 'Chọn app ngân hàng'
                            : 'Mở app ngân hàng gần nhất',
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isLaunchingBank ? null : _chooseBankApp,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Chọn app khác'),
                  ),
                  Text(
                    'VietQR.io hiện chỉ điều hướng sang app ngân hàng; ngân hàng có thể yêu cầu quét QR hoặc nhập lại thông tin.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

enum _PaymentReturnAction { paid, notPaid, edit }

class _PaymentReturnSheet extends StatelessWidget {
  const _PaymentReturnSheet({
    required this.onPaid,
    required this.onNotPaid,
    required this.onEdit,
  });

  final VoidCallback onPaid;
  final VoidCallback onNotPaid;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Bạn đã thanh toán chưa?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Ứng dụng không nhận được xác nhận từ ngân hàng. Chỉ ghi khoản chi khi bạn xác nhận đã chuyển tiền.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onPaid,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Đã thanh toán'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onNotPaid,
              icon: const Icon(Icons.close),
              label: const Text('Chưa thanh toán · Bỏ bản nháp'),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Sửa thông tin'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.titleSmall,
          ),
        ),
      ],
    );
  }
}
