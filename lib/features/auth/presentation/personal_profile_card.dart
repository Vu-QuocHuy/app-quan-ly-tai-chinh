import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../shared/errors/error_presenter.dart';
import '../data/personal_profile_store.dart';

class PersonalProfileCard extends StatefulWidget {
  const PersonalProfileCard({required this.client, super.key});

  final SupabaseClient client;

  @override
  State<PersonalProfileCard> createState() => _PersonalProfileCardState();
}

class _PersonalProfileCardState extends State<PersonalProfileCard> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await PersonalProfileStore(widget.client).load();
      if (!mounted) return;
      _name.text = profile.displayName;
      _phone.text = profile.phone;
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await PersonalProfileStore(
        widget.client,
      ).save(displayName: _name.text, phone: _phone.text);
      if (mounted) setState(() => _success = 'Đã lưu thông tin cá nhân.');
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Thông tin cá nhân',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Họ tên và số điện thoại sẽ hiển thị với thành viên trong các nhóm bạn tham gia.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_loading) ...[
              const SizedBox(height: AppSpacing.lg),
              const LinearProgressIndicator(),
            ] else ...[
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Họ và tên',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                maxLength: 120,
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? 'Nhập họ tên ít nhất 2 ký tự.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại (không bắt buộc)',
                  prefixIcon: Icon(Icons.phone_outlined),
                  hintText: '0912345678',
                ),
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                validator: (value) {
                  final phone = value?.trim() ?? '';
                  return phone.isEmpty ||
                          RegExp(r'^\+?[0-9]{9,15}$').hasMatch(phone)
                      ? null
                      : 'Nhập 9–15 chữ số, có thể bắt đầu bằng +.';
                },
              ),
              if (_error != null || _success != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error ?? _success!,
                  style: TextStyle(
                    color: _error == null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Lưu thông tin'),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
