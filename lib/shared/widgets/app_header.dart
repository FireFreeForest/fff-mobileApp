import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_controller.dart';

class ThemeQuickToggle extends StatelessWidget {
  const ThemeQuickToggle({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeController? controller;
    try {
      controller = context.watch<ThemeController>();
    } catch (_) {
      controller = null;
    }
    final mode = controller?.mode ?? AppThemeMode.system;
    final icon = switch (mode) {
      AppThemeMode.light => Icons.light_mode_rounded,
      AppThemeMode.dark => Icons.dark_mode_rounded,
      AppThemeMode.system => Icons.brightness_auto_rounded,
    };

    return PopupMenuButton<AppThemeMode>(
      tooltip: 'Ganti tema',
      onSelected: (value) => controller?.setMode(value),
      icon: Icon(icon),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: AppThemeMode.system,
          child: _ThemeMenuItem(
            icon: Icons.brightness_auto_rounded,
            label: 'Ikuti sistem',
            selected: mode == AppThemeMode.system,
          ),
        ),
        PopupMenuItem(
          value: AppThemeMode.light,
          child: _ThemeMenuItem(
            icon: Icons.light_mode_rounded,
            label: 'Mode terang',
            selected: mode == AppThemeMode.light,
          ),
        ),
        PopupMenuItem(
          value: AppThemeMode.dark,
          child: _ThemeMenuItem(
            icon: Icons.dark_mode_rounded,
            label: 'Mode gelap',
            selected: mode == AppThemeMode.dark,
          ),
        ),
      ],
    );
  }
}

class _ThemeMenuItem extends StatelessWidget {
  const _ThemeMenuItem({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label)),
        if (selected)
          Icon(
            Icons.check_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 18,
          ),
      ],
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? const Color(0xFFC2C0B6)
                          : context.appTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const ThemeQuickToggle(),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Row(mainAxisSize: MainAxisSize.min, children: actions),
          ],
        ],
      ),
    );
  }
}
