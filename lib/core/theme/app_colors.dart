import 'package:flutter/material.dart';
import 'package:shadchan/core/constants/enums.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF7B1FA2);
  static const Color primaryLight = Color(0xFFE1BEE7);
  static const Color primaryDark = Color(0xFF4A148C);
  static const Color secondary = Color(0xFFF48FB1);
  static const Color secondaryLight = Color(0xFFFCE4EC);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFFFF8FA);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1C1B1F);
  static const Color onSurfaceVariant = Color(0xFF6B6B6B);
  static const Color outline = Color(0xFFE0E0E0);
  static const Color error = Color(0xFFD32F2F);
  static const Color divider = Color(0xFFF0F0F0);

  static const Color statusIdea = Color(0xFF42A5F5);
  static const Color statusChecking = Color(0xFFFFB74D);
  static const Color statusUnavailable = Color(0xFFBDBDBD);
  static const Color statusRejected = Color(0xFFEF5350);
  static const Color statusDating = Color(0xFF66BB6A);
  static const Color statusDated = Color(0xFF9575CD);
  static const Color statusMarried = Color(0xFFEC407A);

  static const Color primaryDarkDm = Color(0xFFCE93D8);
  static const Color primaryLightDarkDm = Color(0xFF2C0A3E);
  static const Color secondaryDarkDm = Color(0xFFF48FB1);
  static const Color backgroundDm = Color(0xFF1A1A2E);
  static const Color surfaceDm = Color(0xFF252540);
  static const Color onSurfaceDm = Color(0xFFF5F5F5);
  static const Color onSurfaceVariantDm = Color(0xFFAAAAAA);
  static const Color outlineDm = Color(0xFF3A3A5C);
  static const Color dividerDm = Color(0xFF2A2A45);

  static Color statusColor(String status) {
    switch (status) {
      case 'idea':
        return statusIdea;
      case 'checking':
        return statusChecking;
      case 'unavailable':
        return statusUnavailable;
      case 'rejected':
        return statusRejected;
      case 'dating':
        return statusDating;
      case 'dated':
        return statusDated;
      case 'married':
        return statusMarried;
      default:
        return statusColor(MatchStatus.idea.name);
    }
  }

  static Color statusBackgroundColor(String status) {
    return statusColor(status).withValues(alpha: 0.15);
  }
}
