import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/app_settings_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/server_settings_dialog.dart';
import '../../shared/widgets/surface_card.dart';
import '../../services/realtime_service.dart';
import '../../state/auth_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _editServer(BuildContext context) async {
    final apiClient = context.read<ApiClient>();
    final settingsStore = context.read<AppSettingsStore>();
    final realtimeService = context.read<RealtimeService>();
    final auth = context.read<AuthController>();

    final newUrl = await showDialog<String>(
      context: context,
      builder: (_) => ServerSettingsDialog(currentUrl: apiClient.baseUrl),
    );
    if (newUrl == null) return;

    if (auth.isAuthenticated) {
      await auth.resetSessionForServerChange();
    }
    await settingsStore.saveApiBaseUrl(newUrl);
    apiClient.updateBaseUrl(newUrl);
    await realtimeService.updateApiBaseUrl(newUrl);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server diubah. Silakan masuk kembali.')),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Keluar dari aplikasi?'),
          content: const Text(
            'Anda perlu masuk kembali untuk memantau node dan menerima peringatan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Keluar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;
    await context.read<AuthController>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.user;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        children: [
          SurfaceCard(
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: AppColors.infoSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? 'Pengguna',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '—',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successSoft,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Text(
                    user?.role.label ?? '—',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'SESI PERANGKAT',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.textSecondary,
                  ),
                  title: const Text('Notifikasi peringatan'),
                  subtitle: const Text(
                    'Token FCM didaftarkan otomatis setelah masuk.',
                  ),
                  trailing: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                    size: 20,
                  ),
                ),
                const Divider(),
                if (AppConfig.allowServerSwitch) ...[
                  ListTile(
                    leading: const Icon(
                      Icons.dns_outlined,
                      color: AppColors.textSecondary,
                    ),
                    title: const Text('Server backend'),
                    subtitle: Text(
                      context.read<ApiClient>().baseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    onTap: () => _editServer(context),
                  ),
                  const Divider(),
                ],
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: AppColors.danger,
                  ),
                  title: Text(
                    'Keluar',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Hapus sesi dan token notifikasi dari perangkat ini.',
                  ),
                  onTap: auth.isLoading ? null : () => _confirmLogout(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Fire Free Forest · Sistem Peringatan Dini Kebakaran Hutan',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
