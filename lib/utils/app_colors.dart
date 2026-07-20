import 'package:flutter/material.dart';
import 'package:shadchan/utils/enums.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF7F9EAA);
  static const Color primaryLight = Color(0xFFD7E4EA);
  static const Color primaryDark = Color(0xFF5F7F8C);
  static const Color secondary = Color(0xFFC1845B);
  static const Color secondaryLight = Color(0xFFEFE4D4);

  static const Color surface = Color(0xFFFFFDF8);
  static const Color background = Color(0xFFF7F0E4);
  static const Color onPrimary = Color(0xFFFFFDF8);
  static const Color onSecondary = Color(0xFF211D17);
  static const Color onSurface = Color(0xFF211D17);
  static const Color onSurfaceVariant = Color(0xFF7C7468);
  static const Color outline = Color(0xFFE2D7C8);
  static const Color error = Color(0xFFD32F2F);
  static const Color divider = Color(0xFFE2D7C8);

  static const Color statusIdea = primary;
  static const Color statusChecking = Color(0xFFB99A55);
  static const Color statusUnavailable = Color(0xFF948577);
  static const Color statusRejected = Color(0xFFA96B49);
  static const Color statusDating = Color(0xFF6F7A55);
  static const Color statusDated = Color(0xFF948577);
  static const Color statusMarried = Color(0xFF6F7A55);

  static const Color softBlue = Color(0xFFD7E4EA);
  static const Color softPink = Color(0xFFE6D4C0);
  static const Color softGreen = Color(0xFFDDE3CF);
  static const Color softPurple = Color(0xFFDDD7E7);
  static const Color softSand = Color(0xFFE6D4C0);
  static const Color softYellow = Color(0xFFEFE0B8);

  static const Color primaryDarkDm = Color(0xFFAFC7D0);
  static const Color primaryLightDarkDm = Color(0xFF28444F);
  static const Color secondaryDarkDm = Color(0xFFD6A17A);
  static const Color secondaryLightDarkDm = Color(0xFF3A3128);
  static const Color backgroundDm = Color(0xFF211D17);
  static const Color surfaceDm = Color(0xFF2A251F);
  static const Color onSurfaceDm = Color(0xFFF7F0E4);
  static const Color onSurfaceVariantDm = Color(0xFFC9BDAE);
  static const Color outlineDm = Color(0xFF5C5045);
  static const Color dividerDm = Color(0xFF3A3128);

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
