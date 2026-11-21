import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/config/server_config.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/app_settings_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/app_header.dart';
import '../../shared/widgets/server_settings_dialog.dart';
import '../../shared/widgets/surface_card.dart';
import '../../services/realtime_service.dart';
import '../../state/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _editServer() async {
    final apiClient = context.read<ApiClient>();
    final settingsStore = context.read<AppSettingsStore>();
    final realtimeService = context.read<RealtimeService>();

    final newUrl = await showDialog<String>(
      context: context,
      builder: (_) => ServerSettingsDialog(currentUrl: apiClient.baseUrl),
    );
    if (newUrl == null || !mounted) return;

    await settingsStore.saveApiBaseUrl(newUrl);
    apiClient.updateBaseUrl(newUrl);
    await realtimeService.updateApiBaseUrl(newUrl);
    if (!mounted) return;

    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Alamat server disimpan.')));
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthController>();
    final success = await auth.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted || success) return;

    final message = auth.errorMessage ?? 'Login gagal. Coba lagi.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final apiClient = context.read<ApiClient>();
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [AppLogo(), ThemeQuickToggle()],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Fire Free Forest',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 2.2,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Masuk ke pusat pemantauan',
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Pantau kondisi hutan, status node, dan peringatan kebakaran dari satu tempat.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: context.appTextSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SurfaceCard(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Akun operator',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Gunakan email dan kata sandi yang terdaftar.',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'nama@instansi.go.id',
                                prefixIcon: Icon(Icons.mail_outline_rounded),
                              ),
                              validator: (value) {
                                final text = value?.trim() ?? '';
                                if (text.isEmpty) {
                                  return 'Email wajib diisi.';
                                }
                                if (!text.contains('@')) {
                                  return 'Format email belum valid.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: 'Kata sandi',
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  tooltip: _obscurePassword
                                      ? 'Tampilkan kata sandi'
                                      : 'Sembunyikan kata sandi',
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Kata sandi wajib diisi.';
                                }
                                if (value.length < 8) {
                                  return 'Kata sandi minimal 8 karakter.';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) {
                                if (!auth.isLoading) {
                                  _submit();
                                }
                              },
                            ),
                            if (auth.errorMessage != null &&
                                !auth.isLoading) ...[
                              const SizedBox(height: AppSpacing.md),
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: AppColors.infoSoft,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSm,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      size: 18,
                                      color: AppColors.primaryDark,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        auth.errorMessage!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: AppColors.primaryDark,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            FilledButton(
                              onPressed: auth.isLoading ? null : _submit,
                              child: auth.isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Masuk'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (AppConfig.allowServerSwitch)
                        TextButton.icon(
                          onPressed: _editServer,
                          icon: const Icon(Icons.dns_outlined, size: 18),
                          label: const Text('Server'),
                        ),
                      Text(
                        ServerConfig.displayLabel(apiClient.baseUrl),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.appTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
