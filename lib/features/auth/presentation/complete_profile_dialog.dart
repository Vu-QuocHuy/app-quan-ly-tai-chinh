import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../debts/data/debt_notification_store.dart';
import '../data/personal_profile_store.dart';

/// App shell and account screen can both request this sheet right after a
/// sign-in; only one may be checking or showing it at a time, otherwise a
/// second identical sheet stays behind the one the user completes.
bool _profileSheetActive = false;

Future<void> showCompleteProfileDialogIfNeeded(
  BuildContext context,
  WidgetRef ref,
) async {
  if (_profileSheetActive) return;
  final client = ref.read(supabaseClientProvider);
  final user = client?.auth.currentUser;
  if (client == null || user == null) return;

  _profileSheetActive = true;
  try {
    final profile = await PersonalProfileStore(client).load();
    if (profile.phone.trim().isNotEmpty &&
        profile.displayName.trim().isNotEmpty) {
      return;
    }

    if (!context.mounted) return;
    final isEn = context.tr.isEn;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: profile.displayName.isNotEmpty
          ? profile.displayName
          : (user.userMetadata?['full_name'] as String? ?? ''),
    );
    final phoneController = TextEditingController(text: profile.phone);
    bool saving = false;
    // Errors are shown inside the sheet: a SnackBar would render on the page
    // Scaffold underneath this modal and stay hidden behind it.
    String? phoneError;
    String? submitError;
    final phoneTakenMessage = isEn
        ? 'This phone number is already registered by another account.'
        : 'Số điện thoại này đã được sử dụng bởi tài khoản khác.';

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetCtx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.person_pin_rounded,
                        color: Theme.of(ctx).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEn
                                ? 'Complete Profile'
                                : 'Hoàn tất thông tin cá nhân',
                            style: Theme.of(ctx).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            isEn
                                ? 'Required for debts and group funds'
                                : 'Cần thiết để quản lý nợ và quỹ nhóm',
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: nameController,
                  enabled: !saving,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: isEn ? 'Full Name *' : 'Họ và tên *',
                    hintText: isEn ? 'e.g. John Doe' : 'Ví dụ: Nguyễn Văn A',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (text.isEmpty) {
                      return isEn
                          ? 'Please enter full name.'
                          : 'Vui lòng nhập họ và tên.';
                    }
                    if (text.length < 2) {
                      return isEn
                          ? 'Enter at least 2 characters.'
                          : 'Họ tên ít nhất 2 ký tự.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  enabled: !saving,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onChanged: (_) {
                    if (phoneError != null) {
                      setState(() => phoneError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: isEn ? 'Phone Number *' : 'Số điện thoại *',
                    hintText: '0912345678',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: const OutlineInputBorder(),
                    errorText: phoneError,
                    errorMaxLines: 2,
                  ),
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (text.isEmpty) {
                      return isEn
                          ? 'Please enter phone number.'
                          : 'Vui lòng nhập số điện thoại.';
                    }
                    if (!RegExp(r'^0[0-9]{9}$').hasMatch(text)) {
                      return isEn
                          ? 'Phone number must have 10 digits starting with 0.'
                          : 'Số điện thoại phải gồm đúng 10 số và bắt đầu bằng 0.';
                    }
                    return null;
                  },
                ),
                if (submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    submitError!,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() {
                            phoneError = null;
                            submitError = null;
                          });
                          if (formKey.currentState?.validate() != true) return;
                          setState(() => saving = true);
                          try {
                            final name = nameController.text.trim();
                            final phone = phoneController.text
                                .replaceAll(RegExp(r'\s+'), '')
                                .trim();

                            final isTaken =
                                await DebtNotificationStore.isPhoneTakenByAnotherUser(
                                  phone,
                                  client: client,
                                  currentUserId: user.id,
                                );
                            if (isTaken) {
                              if (ctx.mounted) {
                                setState(() {
                                  saving = false;
                                  phoneError = phoneTakenMessage;
                                });
                              }
                              return;
                            }

                            await PersonalProfileStore(
                              client,
                            ).save(displayName: name, phone: phone);
                            await DebtNotificationStore.setCurrentUserPhone(
                              phone,
                              ref: ref,
                              client: client,
                              userId: user.id,
                              syncProfile: false,
                            );
                            if (bottomSheetCtx.mounted) {
                              Navigator.pop(bottomSheetCtx);
                            }
                            if (context.mounted) {
                              final messenger = ScaffoldMessenger.of(context);
                              messenger.clearSnackBars();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isEn
                                        ? 'Personal profile updated.'
                                        : 'Đã cập nhật thông tin cá nhân.',
                                  ),
                                  duration: const Duration(seconds: 3),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              final str = e.toString();
                              final taken =
                                  str.contains('23505') ||
                                  str.contains('đã được sử dụng');
                              setState(() {
                                saving = false;
                                if (taken) {
                                  phoneError = phoneTakenMessage;
                                } else {
                                  submitError = isEn
                                      ? 'Could not save profile: $e'
                                      : 'Không lưu được thông tin: $e';
                                }
                              });
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          isEn ? 'Complete' : 'Hoàn tất',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } catch (_) {
  } finally {
    _profileSheetActive = false;
  }
}
