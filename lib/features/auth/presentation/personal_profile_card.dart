import '../../../core/localization/app_strings.dart';
import '../../../shared/widgets/finmi_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../debts/data/debt_notification_store.dart';
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
      if (profile.phone.trim().isNotEmpty) {
        await DebtNotificationStore.setCurrentUserPhone(
          profile.phone.trim(),
          client: widget.client,
          userId: widget.client.auth.currentUser?.id,
          syncProfile: false,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      final isEn = context.tr.isEn;
      setState(() => _error = friendlyMessage(error, isEn: isEn));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final isEn = context.tr.isEn;
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });

    final cleanPhone = _phone.text.replaceAll(RegExp(r'\s+'), '').trim();
    final currentUserId = widget.client.auth.currentUser?.id;

    // Kiểm tra xem số điện thoại đã được đăng ký bởi tài khoản khác chưa
    final isTaken = await DebtNotificationStore.isPhoneTakenByAnotherUser(
      cleanPhone,
      currentUserId: currentUserId,
      client: widget.client,
    );
    if (isTaken) {
      if (mounted) {
        setState(() {
          _error = isEn
              ? 'This phone number is already registered by another account.'
              : 'Số điện thoại này đã được sử dụng bởi tài khoản khác.';
          _saving = false;
        });
      }
      return;
    }

    try {
      await PersonalProfileStore(
        widget.client,
      ).save(displayName: _name.text, phone: cleanPhone);

      await DebtNotificationStore.setCurrentUserPhone(
        cleanPhone,
        client: widget.client,
        userId: currentUserId,
        syncProfile: false,
      );

      if (mounted) {
        setState(
          () => _success = isEn
              ? 'Personal profile saved.'
              : 'Đã lưu thông tin cá nhân.',
        );
      }
    } on Object catch (error) {
      final str = error.toString();
      final isDuplicate =
          str.contains('23505') ||
          str.contains('đã được sử dụng') ||
          str.contains('profiles_phone_unique_idx');
      if (mounted) {
        setState(
          () => _error = isDuplicate
              ? (isEn
                    ? 'This phone number is already registered by another account.'
                    : 'Số điện thoại này đã được sử dụng bởi tài khoản khác.')
              : friendlyMessage(error, isEn: isEn),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final isEn = tr.isEn;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEn ? 'Personal Profile' : 'Thông tin cá nhân',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                isEn
                    ? 'Your name and phone number will be displayed to members in groups you join.'
                    : 'Họ tên và số điện thoại sẽ hiển thị với thành viên trong các nhóm bạn tham gia.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_loading) ...[
                const SizedBox(height: AppSpacing.lg),
                const LinearProgressIndicator(),
              ] else ...[
                const SizedBox(height: AppSpacing.lg),
                FinmiTextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: isEn ? 'Full Name' : 'Họ và tên',
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  maxLength: 120,
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? (isEn
                            ? 'Enter at least 2 characters.'
                            : 'Nhập họ tên ít nhất 2 ký tự.')
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                FinmiTextField(
                  controller: _phone,
                  decoration: InputDecoration(
                    labelText: isEn ? 'Phone Number *' : 'Số điện thoại *',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    hintText: '0912345678',
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  autofillHints: const [AutofillHints.telephoneNumber],
                  validator: (value) {
                    final phone = value?.trim() ?? '';
                    if (phone.isEmpty) {
                      return isEn
                          ? 'Please enter phone number.'
                          : 'Vui lòng nhập số điện thoại.';
                    }
                    return RegExp(r'^0[0-9]{9}$').hasMatch(phone)
                        ? null
                        : (isEn
                              ? 'Phone number must have 10 digits starting with 0.'
                              : 'Số điện thoại phải gồm đúng 10 số và bắt đầu bằng 0.');
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
                    label: Text(isEn ? 'Save Profile' : 'Lưu thông tin'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
