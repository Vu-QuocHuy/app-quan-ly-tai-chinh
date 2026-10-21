import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/errors/error_presenter.dart';
import '../domain/group_models.dart';
import 'group_expense_dialog.dart';

/// Kết quả đọc hóa đơn dùng để điền sẵn biểu mẫu chia tiền.
class ReceiptPrefill {
  const ReceiptPrefill({required this.description, required this.totalMinor});

  final String description;
  final int totalMinor;
}

/// Dialog "Chia tiền": tab "Nhập thủ công" và tab "Quét hóa đơn"; tab nào cũng
/// lưu được một lần chia tiền cho các thành viên.
///
/// [onScan] chụp/chọn ảnh và đọc hóa đơn: trả `null` khi người dùng huỷ chọn
/// ảnh, ném lỗi khi đọc thất bại. Dialog không đọc provider nên test độc lập.
class GroupSplitDialog extends StatefulWidget {
  const GroupSplitDialog({
    required this.members,
    required this.onScan,
    super.key,
  });

  final List<GroupMember> members;
  final Future<ReceiptPrefill?> Function(ImageSource source) onScan;

  @override
  State<GroupSplitDialog> createState() => _GroupSplitDialogState();
}

class _GroupSplitDialogState extends State<GroupSplitDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));
  final _manualKey = GlobalKey<GroupExpenseFormState>();
  final _scanKey = GlobalKey<GroupExpenseFormState>();
  ReceiptPrefill? _prefill;
  bool _scanning = false;
  String? _scanError;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _onScanTab => _tabs.index == 1;

  Future<void> _scan(ImageSource source) async {
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      final prefill = await widget.onScan(source);
      if (!mounted) return;
      if (prefill != null) setState(() => _prefill = prefill);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () =>
              _scanError = 'Không thể xử lý hóa đơn: ${friendlyMessage(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _cancel() async {
    final changed =
        (_manualKey.currentState?.hasChanges ?? false) ||
        (_scanKey.currentState?.hasChanges ?? false) ||
        _prefill != null;
    if (changed) {
      final discard = await showDiscardChangesDialog(context);
      if (!discard || !mounted) return;
    }
    Navigator.pop(context);
  }

  void _submit() {
    final form = _onScanTab ? _scanKey.currentState : _manualKey.currentState;
    final draft = form?.submit();
    if (draft != null) Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    final prefill = _prefill;
    // Toàn màn hình: Scaffold tự co khi bàn phím mở, không tràn như AlertDialog cố định chiều cao.
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Đóng',
            onPressed: _cancel,
            icon: const Icon(Icons.close),
          ),
          title: const Text('Chia tiền'),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Nhập thủ công'),
              Tab(text: 'Quét hóa đơn'),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          // IndexedStack giữ trạng thái cả hai tab khi chuyển qua lại.
          child: IndexedStack(
            index: _tabs.index,
            children: [
              KeyedSubtree(
                key: const ValueKey('tab-thu-cong'),
                child: SingleChildScrollView(
                  child: GroupExpenseForm(
                    key: _manualKey,
                    members: widget.members,
                  ),
                ),
              ),
              KeyedSubtree(
                key: const ValueKey('tab-quet'),
                child: prefill == null
                    ? _buildScanStart(context)
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () =>
                                    setState(() => _prefill = null),
                                icon: const Icon(
                                  Icons.document_scanner_outlined,
                                ),
                                label: const Text('Quét hóa đơn khác'),
                              ),
                            ),
                            GroupExpenseForm(
                              key: _scanKey,
                              members: widget.members,
                              initialDescription: prefill.description,
                              initialTotalMinor: prefill.totalMinor,
                              autofocus: false,
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _cancel, child: const Text('Hủy')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _onScanTab && prefill == null ? null : _submit,
                  child: const Text('Chia tiền'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanStart(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Chụp hoặc chọn ảnh hóa đơn; nội dung và tổng tiền sẽ được điền sẵn.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (_scanning)
          const Center(child: CircularProgressIndicator())
        else ...[
          FilledButton.icon(
            onPressed: () => _scan(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Chụp ảnh hóa đơn'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _scan(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Chọn từ thư viện'),
          ),
        ],
        if (_scanError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _scanError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
