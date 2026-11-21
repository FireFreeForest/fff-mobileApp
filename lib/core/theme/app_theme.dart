import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        surface: Color(0xFF23231F),
        onSurface: Color(0xFFF3F0E8),
        onSurfaceVariant: Color(0xFFC2C0B6),
        error: AppColors.danger,
        outline: Color(0xFF494842),
      ),
      fontFamily: GoogleFonts.inter().fontFamily,
    );

    final textTheme = base.textTheme
        .apply(
          bodyColor: const Color(0xFFF3F0E8),
          displayColor: const Color(0xFFF3F0E8),
        )
        .copyWith(
          headlineMedium: const TextStyle(
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: Color(0xFFF3F0E8),
          ),
          headlineSmall: const TextStyle(
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: Color(0xFFF3F0E8),
          ),
          titleLarge: const TextStyle(
            fontSize: 20,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF3F0E8),
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF3F0E8),
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            height: 1.45,
            color: Color(0xFFF3F0E8),
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Color(0xFFE3E0D6),
          ),
          bodySmall: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: Color(0xFFC2C0B6),
          ),
          labelLarge: const TextStyle(
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: Color(0xFFF3F0E8),
          ),
          labelSmall: const TextStyle(
            fontSize: 11,
            height: 1.3,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            color: Color(0xFFC2C0B6),
          ),
        );

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF171713),
      textTheme: textTheme,
      cardColor: const Color(0xFF23231F),
      canvasColor: const Color(0xFF23231F),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF23231F),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: Color(0xFFF3F0E8),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(color: Color(0xFFE3E0D6), fontSize: 14),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: Color(0xFF292925),
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: Color(0xFFF3F0E8)),
      ),
      iconTheme: const IconThemeData(color: Color(0xFFE3E0D6)),
      listTileTheme: const ListTileThemeData(
        iconColor: Color(0xFFC2C0B6),
        textColor: Color(0xFFF3F0E8),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF171713),
        foregroundColor: Color(0xFFF3F0E8),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF23231F),
        hintStyle: const TextStyle(color: Color(0xFFC2C0B6), fontSize: 14),
        labelStyle: const TextStyle(color: Color(0xFFE3E0D6), fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: Color(0xFF494842)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: Color(0xFF494842)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFF3F0E8),
          side: const BorderSide(color: Color(0xFF494842)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF23231F),
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFFF3F0E8) : const Color(0xFFC2C0B6),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? AppColors.primary : const Color(0xFFC2C0B6),
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF494842),
        thickness: 1,
      ),
    );
  }

  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          error: AppColors.danger,
          outline: AppColors.border,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: GoogleFonts.inter().fontFamily,
    );

    final textTheme = base.textTheme
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          displaySmall: const TextStyle(
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
            color: AppColors.textPrimary,
          ),
          headlineMedium: const TextStyle(
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: AppColors.textPrimary,
          ),
          headlineSmall: const TextStyle(
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
          ),
          titleLarge: const TextStyle(
            fontSize: 20,
            height: 1.25,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            height: 1.45,
            color: AppColors.textPrimary,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.textPrimary,
          ),
          bodySmall: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
          labelLarge: const TextStyle(
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          labelSmall: const TextStyle(
            fontSize: 11,
            height: 1.3,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            color: AppColors.textMuted,
          ),
        );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.14),
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.textPrimary : AppColors.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? AppColors.primary : AppColors.textMuted,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.dark,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    );
  }
}
