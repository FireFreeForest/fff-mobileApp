import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../models/device_status.dart';
import 'app_colors.dart';

extension RiskLevelStyle on RiskLevel {
  Color get color {
    switch (this) {
      case RiskLevel.normal:
        return AppColors.success;
      case RiskLevel.waspada:
        return AppColors.warning;
      case RiskLevel.bahaya:
        return AppColors.danger;
      case RiskLevel.darurat:
        return AppColors.emergency;
      case RiskLevel.unknown:
        return AppColors.textMuted;
    }
  }

  Color get softColor {
    switch (this) {
      case RiskLevel.normal:
        return AppColors.successSoft;
      case RiskLevel.waspada:
        return AppColors.warningSoft;
      case RiskLevel.bahaya:
      case RiskLevel.darurat:
        return AppColors.dangerSoft;
      case RiskLevel.unknown:
        return AppColors.surface;
    }
  }

  Color get darkSoftColor {
    switch (this) {
      case RiskLevel.normal:
        return const Color(0xFF303C33);
      case RiskLevel.waspada:
        return const Color(0xFF433A27);
      case RiskLevel.bahaya:
      case RiskLevel.darurat:
        return const Color(0xFF4A302B);
      case RiskLevel.unknown:
        return const Color(0xFF292925);
    }
  }

  IconData get icon {
    switch (this) {
      case RiskLevel.normal:
        return Icons.check_circle_outline_rounded;
      case RiskLevel.waspada:
        return Icons.warning_amber_rounded;
      case RiskLevel.bahaya:
        return Icons.local_fire_department_outlined;
      case RiskLevel.darurat:
        return Icons.crisis_alert_rounded;
      case RiskLevel.unknown:
        return Icons.help_outline_rounded;
    }
  }
}

extension DeviceConnectionStyle on DeviceConnection {
  Color get color =>
      this == DeviceConnection.online ? AppColors.success : AppColors.textMuted;
}
