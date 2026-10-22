import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_strings.dart';
import '../../../shared/widgets/finmi_brand.dart';
import '../../../shared/widgets/finmi_text_field.dart';
import '../../../shared/widgets/google_logo.dart';
import '../../../core/security/supabase_bootstrap.dart';
import 'complete_profile_dialog.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/local_database_scope.dart';
import '../../../core/providers/app_providers.dart';
import '../../chat/data/chat_history_store.dart';
import '../../export/data/backup_catalog_store.dart';
import '../../ingestion/data/drift_import_job_store.dart';
import '../../ingestion/data/pending_import_store.dart';
import '../../insights/data/anomaly_feedback_store.dart';
import '../../invoices/data/drift_invoice_repository.dart';
import '../../notifications/data/budget_alert_preferences.dart';
import '../../debts/data/debt_notification_store.dart';
import '../data/personal_profile_store.dart';
import '../domain/auth_validators.dart';
import 'personal_profile_card.dart';
import '../../notifications/data/budget_notification_service.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/widgets/app_callout.dart';
import '../../../shared/widgets/app_skeleton.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _verificationEmail;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseClientProvider);
    final user = ref.watch(authUserProvider);
    final isSignedOut =
        client != null && user.hasValue && user.valueOrNull == null;
    final isEn = context.tr.isEn;
    return Scaffold(
      appBar: isSignedOut
          ? null
          : AppBar(title: Text(isEn ? 'Account' : 'Tài khoản', maxLines: 3)),
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: isSignedOut ? const Color(0xFF123D32) : null,
          image: isSignedOut
              ? const DecorationImage(
                  image: AssetImage(
                    'assets/branding/finmi/background-dark.png',
                  ),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: SafeArea(
          child: client == null
              ? _buildCenteredContent(const _ConfigurationMissingCard())
              : user.when(
                  data: (currentUser) => currentUser == null
                      ? _buildAuthExperience(context)
                      : _buildCenteredContent(
                          _buildSignedIn(context, currentUser),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => _buildCenteredContent(
                    _StatusCard(
                      icon: Icons.error_outline,
                      title: isEn
                          ? 'Failed to load sign-in session'
                          : 'Không đọc được phiên đăng nhập',
                      message: friendlyMessage(error),
                      isError: true,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildCenteredContent(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.xl,
            AppSpacing.gutter,
            AppSpacing.xxl,
          ),
          children: [child],
        ),
      ),
    );
  }

  Widget _buildAuthExperience(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final pageGutter = constraints.maxWidth < AppBreakpoints.compact
            ? AppSpacing.lg
            : AppSpacing.gutter;
        final content = isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _buildAuthIntro(context, expanded: true)),
                  const SizedBox(width: AppSpacing.section),
                  SizedBox(width: 440, child: _buildAuthForm(context)),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAuthIntro(context, expanded: false),
                  const SizedBox(height: AppSpacing.xl),
                  _buildAuthForm(context),
                ],
              );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            pageGutter,
            AppSpacing.xl,
            pageGutter,
            AppSpacing.xxl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > AppSpacing.section
                  ? constraints.maxHeight - AppSpacing.section
                  : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 1120 : 480),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAuthIntro(BuildContext context, {required bool expanded}) {
    final theme = Theme.of(context);
    final isEn = context.tr.isEn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const FinmiBrand(width: 160),
          ),
          const SizedBox(height: 20),
          Text(
            isEn ? 'Track your daily finances' : 'Theo dõi chi tiêu mỗi ngày',
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            isEn
                ? 'Record income and expenses, review receipts and stay on top of your budget.'
                : 'Ghi khoản thu chi, kiểm tra hóa đơn và chủ động với ngân sách của bạn.',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthForm(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Card(
        key: ValueKey(_registering),
        color: scheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: AppShapes.cardRadius,
          side: BorderSide(color: scheme.outline, width: 1),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.lg : AppSpacing.xl,
            AppSpacing.xl,
            compact ? AppSpacing.lg : AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_registering) ...[
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        color: scheme.tertiaryContainer,
                        shape: AppShapes.control,
                      ),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.person_add_alt_1_outlined,
                          color: scheme.onTertiaryContainer,
                          size: AppIconSizes.md,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _registering
                              ? (context.tr.isEn
                                    ? 'New Account'
                                    : 'Tài khoản mới')
                              : (context.tr.isEn
                                    ? 'Welcome Back'
                                    : 'Chào mừng trở lại'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.tertiary,
                            letterSpacing: 0,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _registering
                              ? (context.tr.isEn
                                    ? 'Create Account'
                                    : 'Tạo tài khoản')
                              : (context.tr.isEn ? 'Sign In' : 'Đăng nhập'),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _registering
                    ? (context.tr.isEn
                          ? 'Start tracking your personal finances.'
                          : 'Bắt đầu theo dõi thu chi của bạn.')
                    : (context.tr.isEn
                          ? 'Sign in to continue managing your personal finances.'
                          : 'Đăng nhập để tiếp tục quản lý tài chính cá nhân.'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Semantics(
                container: true,
                label: context.tr.isEn
                    ? 'Select sign in or register'
                    : 'Chọn đăng nhập hoặc đăng ký',
                child: SegmentedButton<bool>(
                  direction:
                      MediaQuery.sizeOf(context).width < 360 ||
                          MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.3
                      ? Axis.vertical
                      : Axis.horizontal,
                  style: ButtonStyle(
                    minimumSize: const WidgetStatePropertyAll(
                      Size.fromHeight(48),
                    ),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(context.tr.isEn ? 'Sign In' : 'Đăng nhập'),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(context.tr.isEn ? 'Register' : 'Đăng ký'),
                    ),
                  ],
                  selected: {_registering},
                  onSelectionChanged: _busy
                      ? null
                      : (selection) {
                          setState(() {
                            _registering = selection.first;
                            _formKey = GlobalKey<FormState>();
                            _verificationEmail = null;
                            _message = null;
                          });
                        },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_message != null) ...[
                Semantics(
                  liveRegion: true,
                  child: _StatusCard(
                    icon: _messageIsError
                        ? Icons.error_outline
                        : Icons.mark_email_read_outlined,
                    title: _messageIsError
                        ? (context.tr.isEn
                              ? 'An error occurred'
                              : 'Có lỗi xảy ra')
                        : (context.tr.isEn ? 'Processed' : 'Đã xử lý'),
                    message: _message!,
                    isError: _messageIsError,
                    actionLabel: _verificationEmail == null
                        ? null
                        : (context.tr.isEn
                              ? 'Resend confirmation email'
                              : 'Gửi lại email xác nhận'),
                    onAction: _verificationEmail == null
                        ? null
                        : _resendSignupConfirmation,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (_registering) ...[
                FinmiTextField(
                  controller: _nameController,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: InputDecoration(
                    labelText: context.tr.isEn ? 'Full Name *' : 'Họ và tên *',
                    hintText: context.tr.isEn
                        ? 'e.g. John Doe'
                        : 'Ví dụ: Nguyễn Văn A',
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    final name = value?.trim() ?? '';
                    if (name.isEmpty) {
                      return context.tr.isEn
                          ? 'Please enter full name.'
                          : 'Vui lòng nhập họ và tên.';
                    }
                    if (name.length < 2) {
                      return context.tr.isEn
                          ? 'Enter at least 2 characters.'
                          : 'Họ tên ít nhất 2 ký tự.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                FinmiTextField(
                  controller: _phoneController,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: InputDecoration(
                    labelText: context.tr.isEn
                        ? 'Phone Number *'
                        : 'Số điện thoại *',
                    hintText: '0912345678',
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    final phone = value?.trim() ?? '';
                    if (phone.isEmpty) {
                      return context.tr.isEn
                          ? 'Please enter phone number.'
                          : 'Vui lòng nhập số điện thoại.';
                    }
                    return RegExp(r'^0[0-9]{9}$').hasMatch(phone)
                        ? null
                        : (context.tr.isEn
                              ? 'Phone number must have 10 digits starting with 0.'
                              : 'Số điện thoại phải gồm đúng 10 số và bắt đầu bằng 0.');
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              FinmiTextField(
                controller: _emailController,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: 'Email',
                  hintText: 'user@example.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                validator: AuthValidators.email,
              ),
              const SizedBox(height: AppSpacing.lg),
              FinmiTextField(
                controller: _passwordController,
                enabled: !_busy,
                obscureText: _obscurePassword,
                textInputAction: _registering
                    ? TextInputAction.next
                    : TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: [
                  _registering
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                onFieldSubmitted: _registering || _busy
                    ? null
                    : (_) => _submit(),
                decoration: InputDecoration(
                  labelText: context.tr.isEn ? 'Password' : 'Mật khẩu',
                  helperText: _registering
                      ? (context.tr.isEn
                            ? 'At least 8 characters. You can use a password manager.'
                            : 'Tối thiểu 8 ký tự. Bạn có thể dùng trình quản lý mật khẩu.')
                      : null,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? (context.tr.isEn ? 'Show password' : 'Hiện mật khẩu')
                        : (context.tr.isEn ? 'Hide password' : 'Ẩn mật khẩu'),
                    onPressed: _busy
                        ? null
                        : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return context.tr.isEn
                        ? 'Please enter password.'
                        : 'Hãy nhập mật khẩu.';
                  }
                  if (_registering && value.length < 8) {
                    return context.tr.isEn
                        ? 'Password must have at least 8 characters.'
                        : 'Mật khẩu cần ít nhất 8 ký tự.';
                  }
                  return null;
                },
              ),
              if (!_registering)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    onPressed: _busy ? null : _sendPasswordReset,
                    child: Text(
                      context.tr.isEn ? 'Forgot password?' : 'Quên mật khẩu?',
                    ),
                  ),
                ),
              if (_registering) ...[
                const SizedBox(height: AppSpacing.lg),
                FinmiTextField(
                  controller: _confirmationController,
                  enabled: !_busy,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: _busy ? null : (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: context.tr.isEn
                        ? 'Confirm Password'
                        : 'Nhập lại mật khẩu',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return context.tr.isEn
                          ? 'Please confirm password.'
                          : 'Hãy nhập lại mật khẩu.';
                    }
                    return value != _passwordController.text
                        ? (context.tr.isEn
                              ? 'Passwords do not match.'
                              : 'Hai mật khẩu chưa khớp.')
                        : null;
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _busy ? null : _submit,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_busy)
                      const ButtonSpinner()
                    else if (_registering)
                      const Icon(Icons.person_add_alt_1_outlined),
                    if (_busy || _registering)
                      const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        _registering
                            ? (context.tr.isEn
                                  ? 'Create Account'
                                  : 'Tạo tài khoản')
                            : (context.tr.isEn ? 'Sign In' : 'Đăng nhập'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Text(
                      context.tr.isEn ? 'or' : 'hoặc',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _busy ? null : _signInWithGoogle,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const GoogleLogo(size: 20),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        context.tr.isEn
                            ? 'Continue with Google'
                            : 'Đăng nhập với Google',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignedIn(BuildContext context, User user) {
    final scheme = Theme.of(context).colorScheme;
    final isEn = context.tr.isEn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusCard(
          icon: Icons.cloud_done_outlined,
          title: isEn ? 'Account connected' : 'Đã kết nối tài khoản',
          message:
              user.email ??
              (isEn ? 'Account ${user.id}' : 'Tài khoản ${user.id}'),
        ),
        const SizedBox(height: AppSpacing.lg),
        PersonalProfileCard(
          key: ValueKey(user.id),
          client: ref.read(supabaseClientProvider)!,
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildIdentitySection(context),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            liveRegion: true,
            child: _StatusCard(
              icon: _messageIsError
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
              title: _messageIsError
                  ? (isEn ? 'An error occurred' : 'Có lỗi xảy ra')
                  : (isEn ? 'Done' : 'Hoàn tất'),
              message: _message!,
              isError: _messageIsError,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        _SectionHeading(
          icon: Icons.cloud_sync_outlined,
          title: isEn ? 'Data & Sync' : 'Dữ liệu và đồng bộ',
          message: isEn
              ? 'Push pending changes to cloud or download latest updates.'
              : 'Đẩy thay đổi đang chờ lên cloud hoặc tải thay đổi mới về máy.',
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: _busy ? null : _syncNow,
          icon: _busy ? const ButtonSpinner() : const Icon(Icons.sync),
          label: Text(isEn ? 'Sync now' : 'Đồng bộ ngay'),
        ),
        const SizedBox(height: AppSpacing.xxl),
        _SectionHeading(
          icon: Icons.shield_outlined,
          title: isEn ? 'Account Security' : 'Bảo mật tài khoản',
          message: isEn
              ? 'Manage password, sign-in sessions and cloud data.'
              : 'Quản lý mật khẩu, phiên đăng nhập và dữ liệu cloud.',
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _busy ? null : _changePassword,
          icon: const Icon(Icons.lock_reset_outlined),
          label: Text(isEn ? 'Change Password' : 'Đổi mật khẩu'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _busy ? null : _signOut,
          icon: const Icon(Icons.logout),
          label: Text(isEn ? 'Sign Out' : 'Đăng xuất'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _busy ? null : _deleteAccount,
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error),
          ),
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(isEn ? 'Delete Account' : 'Xóa tài khoản'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          isEn
              ? 'Signing out will not erase local device data. Deleting your account will permanently remove cloud data and related local data.'
              : 'Đăng xuất không xóa dữ liệu đang lưu trên thiết bị. Xóa tài khoản sẽ xóa dữ liệu cloud và dữ liệu local liên quan.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildIdentitySection(BuildContext context) {
    final identitiesAsync = ref.watch(authIdentitiesProvider);
    final isEn = context.tr.isEn;
    return identitiesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Card(
        child: ListTile(
          leading: const Icon(Icons.link_off_outlined),
          title: Text(
            isEn
                ? 'Failed to load sign-in methods'
                : 'Không tải được phương thức đăng nhập',
            maxLines: 3,
          ),
          subtitle: Text(friendlyMessage(error)),
          trailing: IconButton(
            tooltip: isEn ? 'Retry' : 'Tải lại',
            onPressed: _busy
                ? null
                : () => ref.invalidate(authIdentitiesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ),
      ),
      data: (identities) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEn ? 'Sign-in method' : 'Phương thức đăng nhập',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final identity in identities)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: identity.provider == OAuthProvider.google.name
                        ? const GoogleLogo(size: 22)
                        : Icon(_identityIcon(identity.provider)),
                    title: Text(_identityLabel(identity.provider)),
                    subtitle: Text(
                      identity.provider == 'email'
                          ? (isEn
                                ? 'Signed in with email and password'
                                : 'Đăng nhập bằng email và mật khẩu')
                          : (isEn
                                ? 'Linked to this account'
                                : 'Đã liên kết với tài khoản này'),
                    ),
                    trailing:
                        identity.provider == 'email' || identities.length < 2
                        ? null
                        : IconButton(
                            tooltip: isEn ? 'Unlink' : 'Gỡ liên kết',
                            onPressed: _busy
                                ? null
                                : () => _unlinkIdentity(identity),
                            icon: const Icon(Icons.link_off_outlined),
                          ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _identityIcon(String provider) {
    return provider == OAuthProvider.google.name
        ? Icons.account_circle_outlined
        : Icons.email_outlined;
  }

  String _identityLabel(String provider) {
    return switch (provider) {
      'email' => 'Email',
      'google' => 'Google',
      _ => provider,
    };
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    final email = _emailController.text.trim();
    setState(() {
      _busy = true;
      _message = null;
      _verificationEmail = null;
    });
    try {
      if (_registering) {
        final phone = _phoneController.text
            .replaceAll(RegExp(r'\s+'), '')
            .trim();
        final client = ref.read(supabaseClientProvider);
        final isTaken = await DebtNotificationStore.isPhoneTakenByAnotherUser(
          phone,
          client: client,
        );
        if (isTaken) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _messageIsError = true;
            _message = 'Số điện thoại này đã được sử dụng bởi tài khoản khác.';
          });
          return;
        }

        final response = await auth.signUp(
          email: _emailController.text,
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
          phone: phone,
        );
        if (!mounted) return;
        setState(() {
          _messageIsError = false;
          _verificationEmail = response.session == null ? email : null;
          _message = response.session == null
              ? 'Hãy kiểm tra email để xác nhận tài khoản, sau đó quay lại đăng nhập.'
              : 'Tài khoản đã được tạo và đăng nhập.';
        });
        if (response.session != null) {
          if (client != null) {
            try {
              await PersonalProfileStore(
                client,
              ).save(displayName: _nameController.text.trim(), phone: phone);
            } catch (_) {}
          }
          await DebtNotificationStore.setCurrentUserPhone(
            phone,
            ref: ref,
            client: client,
            userId: response.user?.id,
            syncProfile: false,
          );
          await _runSync();
        }
      } else {
        await auth.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
        await _runSync();
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = 'Không thể kết nối tài khoản: ${friendlyMessage(error)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final launched = await auth.signInWithGoogle();
      if (!launched) {
        throw const AuthException('Không thể mở trang đăng nhập Google.');
      }
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Đang chuyển hướng tới Google...';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      final msg = error.message.toLowerCase();
      final isProviderDisabled =
          msg.contains('unsupported provider') ||
          msg.contains('provider is not enabled') ||
          msg.contains('provider not enabled');
      if (isProviderDisabled) {
        await _showGoogleProviderNotEnabledDialog();
      } else {
        setState(() {
          _messageIsError = true;
          _message = friendlyMessage(error);
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      final str = error.toString().toLowerCase();
      if (str.contains('unsupported provider') ||
          str.contains('provider is not enabled') ||
          str.contains('provider not enabled')) {
        await _showGoogleProviderNotEnabledDialog();
      } else {
        setState(() {
          _messageIsError = true;
          _message = 'Không thể đăng nhập Google: ${friendlyMessage(error)}';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showGoogleProviderNotEnabledDialog() async {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final client = ref.read(supabaseClientProvider);
    final supabaseOrigin = client != null
        ? Uri.parse(client.rest.url).origin
        : '';
    final redirectUri =
        SupabaseBootstrap.oauthRedirectUri ??
        (supabaseOrigin.isNotEmpty
            ? '$supabaseOrigin/auth/v1/callback'
            : 'https://<project-ref>.supabase.co/auth/v1/callback');

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        icon: const Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GoogleLogo(size: 38),
              Positioned(
                right: -4,
                bottom: -4,
                child: CircleAvatar(
                  radius: 8,
                  backgroundColor: Colors.amber,
                  child: Icon(
                    Icons.priority_high,
                    size: 11,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
        title: const Text('Google OAuth chưa bật', textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: scheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Unsupported provider: provider is not enabled',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Supabase chưa được cấu hình Provider Google. Để kích hoạt thật:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              _buildSetupStep(
                '1',
                'Vào Supabase Dashboard → Authentication → Providers → Google.',
              ),
              _buildSetupStep('2', 'Bật toggle "Enable Sign in with Google".'),
              _buildSetupStep(
                '3',
                'Nhập Client ID và Client Secret từ Google Cloud Console.',
              ),
              _buildSetupStep(
                '4',
                'Cấu hình Authorized Redirect URI: $redirectUri',
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Bạn có thể dùng tài khoản Google mẫu để kiểm tra ngay luồng bổ sung Họ tên & SĐT (10 số):',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Đóng'),
          ),
          FilledButton.icon(
            icon: const GoogleLogo(size: 16),
            label: const Text('Thử tài khoản Google Demo'),
            onPressed: () {
              Navigator.pop(dialogCtx);
              _signInWithDemoGoogleAccount();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSetupStep(String stepNumber, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              stepNumber,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signInWithDemoGoogleAccount() async {
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    const demoEmail = 'google.tester@demo.finmi.app';
    const demoPassword = 'GoogleTesterDemo2026!';

    try {
      try {
        await auth.signIn(email: demoEmail, password: demoPassword);
      } catch (_) {
        await auth.signUp(
          email: demoEmail,
          password: demoPassword,
          displayName: 'Google Tester',
        );
        try {
          await auth.signIn(email: demoEmail, password: demoPassword);
        } catch (_) {}
      }
      await _runSync();
      if (!mounted) return;
      await showCompleteProfileDialogIfNeeded(context, ref);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message =
            'Không thể đăng nhập tài khoản demo: ${friendlyMessage(error)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlinkIdentity(UserIdentity identity) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Gỡ liên kết ${_identityLabel(identity.provider)}?',
      message:
          'Bạn vẫn giữ được phương thức đăng nhập còn lại. Có thể liên kết lại sau.',
      confirmLabel: 'Gỡ liên kết',
      icon: Icons.link_off_outlined,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.unlinkIdentity(identity);
      ref.invalidate(authIdentitiesProvider);
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Đã gỡ liên kết ${_identityLabel(identity.provider)}.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _runSync();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (AuthValidators.email(email) != null) {
      setState(() {
        _messageIsError = true;
        _message = 'Hãy nhập email hợp lệ trước khi khôi phục mật khẩu.';
      });
      return;
    }
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.sendPasswordResetEmail(email);
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Đã gửi email khôi phục mật khẩu. Hãy kiểm tra hộp thư.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendSignupConfirmation() async {
    final email = (_verificationEmail ?? _emailController.text).trim();
    if (AuthValidators.email(email) != null) {
      setState(() {
        _messageIsError = true;
        _message = 'Hãy nhập lại email hợp lệ để gửi email xác nhận.';
      });
      return;
    }
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.resendSignupConfirmation(email);
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _verificationEmail = email;
        _message = 'Đã gửi lại email xác nhận. Hãy kiểm tra cả thư mục spam.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (password == null || !mounted) return;
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    final isEn = context.tr.isEn;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.updatePassword(password);
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = isEn
            ? 'Password changed successfully.'
            : 'Đã đổi mật khẩu thành công.';
      });
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSync() async {
    final isEn = context.tr.isEn;
    await ref.read(syncOutboxStoreProvider).retryFailed();
    final result = await ref.read(syncCoordinatorProvider).runOnce();
    if (!mounted) return;
    setState(() {
      _messageIsError = result.upload.failed > 0 || result.conflicts > 0;
      _message = result.conflicts > 0
          ? (isEn
                ? 'Uploaded ${result.upload.pushed}, downloaded ${result.applied}; ${result.conflicts} conflict(s) need review.'
                : 'Đã gửi ${result.upload.pushed}, tải về ${result.applied}; có ${result.conflicts} xung đột cần kiểm tra.')
          : result.upload.failed > 0
          ? (isEn
                ? 'Uploaded ${result.upload.pushed} changes, ${result.upload.failed} changes failed.'
                : 'Đã gửi ${result.upload.pushed} thay đổi, ${result.upload.failed} thay đổi bị lỗi.')
          : (isEn
                ? 'Uploaded ${result.upload.pushed}, downloaded ${result.applied} changes from account.'
                : 'Đã gửi ${result.upload.pushed}, tải về ${result.applied} thay đổi từ tài khoản.');
    });
  }

  Future<void> _signOut() async {
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    final isEn = context.tr.isEn;
    setState(() => _busy = true);
    try {
      await auth.signOut();
      await _clearBudgetNotifications();
      if (!mounted) return;
      setState(() {
        _message = null;
        _passwordController.clear();
        _confirmationController.clear();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = isEn
            ? 'Failed to sign out: ${friendlyMessage(error)}'
            : 'Không thể đăng xuất: ${friendlyMessage(error)}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final isEn = context.tr.isEn;
    final confirmationController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final text = confirmationController.text.trim().toUpperCase();
          final canDelete = text == 'XÓA' || text == 'DELETE';
          final scheme = Theme.of(context).colorScheme;
          return AlertDialog(
            icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
            title: Text(
              isEn ? 'Delete account?' : 'Xóa tài khoản?',
              maxLines: 3,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEn
                      ? 'Your account, synced data, and cloud backup files will be permanently deleted. Related local data will also be removed. This action cannot be undone.'
                      : 'Tài khoản, dữ liệu đồng bộ và tệp backup cloud sẽ bị xóa vĩnh viễn. Dữ liệu local liên quan cũng sẽ bị xóa. Thao tác này không thể hoàn tác.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmationController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: isEn
                        ? 'Type DELETE to confirm'
                        : 'Nhập XÓA để xác nhận',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(isEn ? 'Cancel' : 'Hủy'),
              ),
              FilledButton(
                onPressed: canDelete
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                child: Text(isEn ? 'Delete permanently' : 'Xóa vĩnh viễn'),
              ),
            ],
          );
        },
      ),
    );
    confirmationController.dispose();
    if (confirmed != true || !mounted) return;
    final auth = ref.read(supabaseAuthServiceProvider);
    if (auth == null) return;
    var deletedRemotely = false;
    var signedOut = false;
    final deletedUserId = auth.currentUser?.id;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.deleteAccount();
      deletedRemotely = true;
      await _clearLocalAccountData(deletedUserId);
      await auth.signOut();
      signedOut = true;
    } on Object catch (error) {
      if (deletedRemotely) {
        var localCleaned = false;
        try {
          await _clearLocalAccountData(deletedUserId);
          localCleaned = true;
        } on Object {
          localCleaned = false;
        }
        try {
          await auth.signOut();
          signedOut = true;
        } on Object catch (signOutError) {
          if (mounted) {
            setState(() {
              _messageIsError = true;
              _message =
                  'Tài khoản đã xóa trên máy chủ. Hãy khởi động lại ứng dụng để hoàn tất đăng xuất: ${friendlyMessage(signOutError)}';
            });
          }
        }
        if (localCleaned && signedOut) {
          if (mounted) {
            setState(() {
              _messageIsError = false;
              _message = 'Tài khoản và dữ liệu đã được xóa.';
            });
          }
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = deletedRemotely
            ? 'Tài khoản đã bị xóa trên máy chủ nhưng chưa dọn hết dữ liệu local. Hãy khởi động lại ứng dụng.'
            : friendlyMessage(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearLocalAccountData(String? userId) async {
    final scopedUserId = userId?.trim().toLowerCase();
    if (!LocalDatabaseScope.isValidUserId(scopedUserId)) {
      throw StateError('Không xác định được dữ liệu local của tài khoản.');
    }
    final includeLegacy = await LocalDatabaseScope.ownsLegacyDatabase(
      scopedUserId,
    );
    final database = AppDatabase(
      null,
      LocalDatabaseScope.databaseName(
        userId: scopedUserId,
        cloudConfigured: true,
      ),
    );
    final repository = DriftInvoiceRepository(database);
    final importJobs = DriftImportJobStore(database);
    Object? firstError;
    final cleanups = <Future<void> Function()>[
      repository.deleteAllUserData,
      importJobs.clear,
      () => PendingImportStore(
        scope: scopedUserId,
      ).clearAll(includeLegacy: includeLegacy),
      () => ChatHistoryStore(
        scope: scopedUserId,
      ).clearAll(includeLegacy: includeLegacy),
      () => AnomalyFeedbackStore(
        scope: scopedUserId,
      ).clearAll(includeLegacy: includeLegacy),
      () => BackupCatalogStore(
        scope: scopedUserId,
      ).clearAll(includeLegacy: includeLegacy),
      () => BudgetAlertPreferences(
        scope: scopedUserId,
      ).clearAll(includeLegacy: includeLegacy),
      _clearBudgetNotifications,
    ];
    try {
      for (final cleanup in cleanups) {
        try {
          await cleanup();
        } on Object catch (error) {
          firstError ??= error;
        }
      }
    } finally {
      try {
        await database.close();
      } on Object catch (error) {
        firstError ??= error;
      }
      try {
        await LocalDatabaseScope.releaseLegacyDatabase(scopedUserId);
      } on Object catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  }

  Future<void> _clearBudgetNotifications() async {
    try {
      await BudgetNotificationService.instance.cancelAllNotifications();
    } on Object {
      return;
    }
  }
}

class _ConfigurationMissingCard extends StatelessWidget {
  const _ConfigurationMissingCard();

  @override
  Widget build(BuildContext context) {
    final isEn = context.tr.isEn;
    return AppCallout(
      icon: Icons.cloud_off_outlined,
      tone: CalloutTone.info,
      title: isEn ? 'Account Configuration Required' : 'Cần cấu hình tài khoản',
      message: isEn
          ? 'The application requires sign-in before use. This build is missing account service configuration. Please contact your app administrator.'
          : 'Ứng dụng yêu cầu đăng nhập trước khi sử dụng. Bản build này chưa có '
                'cấu hình dịch vụ tài khoản. Hãy liên hệ người quản lý ứng dụng. '
                'SUPABASE_PUBLISHABLE_KEY. Lần đăng nhập đầu cần có kết nối mạng.',
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEn = context.tr.isEn;
    return AlertDialog(
      title: Text(isEn ? 'Change Password' : 'Đổi mật khẩu', maxLines: 3),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FinmiTextField(
              controller: _passwordController,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: isEn ? 'New password' : 'Mật khẩu mới',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => (value?.length ?? 0) < 8
                  ? (isEn
                        ? 'Password must have at least 8 characters.'
                        : 'Mật khẩu cần ít nhất 8 ký tự.')
                  : null,
            ),
            const SizedBox(height: 12),
            FinmiTextField(
              controller: _confirmationController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: isEn ? 'Confirm password' : 'Nhập lại mật khẩu',
              ),
              validator: (value) => value != _passwordController.text
                  ? (isEn
                        ? 'Passwords do not match.'
                        : 'Hai mật khẩu chưa khớp.')
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(isEn ? 'Cancel' : 'Hủy'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() == true) {
              Navigator.pop(context, _passwordController.text);
            }
          },
          child: Text(isEn ? 'Save Password' : 'Lưu mật khẩu'),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final foreground = isError
        ? Theme.of(context).colorScheme.onErrorContainer
        : Theme.of(context).colorScheme.onSecondaryContainer;
    return AppCallout(
      icon: icon,
      title: title,
      message: message,
      tone: isError ? CalloutTone.danger : CalloutTone.info,
      actions: onAction == null
          ? const []
          : [
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: foreground),
                child: Text(actionLabel!),
              ),
            ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Semantics(
            container: true,
            header: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
