abstract final class PhoneUtils {
  /// Compiled once: [normalizeForComparison] runs for every friend on every
  /// read of the database (see `SelfIdentity.isSelf`).
  static final RegExp _nonDigits = RegExp(r'\D');

  static String? normalizeForComparison(String? value) {
    if (value == null) {
      return null;
    }

    String digitsOnly = value.replaceAll(_nonDigits, '');
    if (digitsOnly.isEmpty) {
      return null;
    }

    if (digitsOnly.startsWith('00')) {
      digitsOnly = digitsOnly.substring(2);
    }

    if (digitsOnly.startsWith('972')) {
      digitsOnly = digitsOnly.substring(3);
      if (!digitsOnly.startsWith('0')) {
        digitsOnly = '0$digitsOnly';
      }
    }

    if (digitsOnly.length > 10 && digitsOnly.startsWith('0')) {
      digitsOnly = digitsOnly.substring(digitsOnly.length - 10);
    }

    return digitsOnly.isEmpty ? null : digitsOnly;
  }

  static String digitsOnly(String value) {
    return value.replaceAll(_nonDigits, '');
  }

  static String? toWhatsAppNumber(String? value) {
    if (value == null) {
      return null;
    }

    String digits = digitsOnly(value);
    if (digits.isEmpty) {
      return null;
    }

    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }

    if (digits.startsWith('972')) {
      return digits.length >= 11 ? digits : null;
    }

    if (digits.startsWith('0') && digits.length >= 9) {
      return '972${digits.substring(1)}';
    }

    return digits.length >= 8 ? digits : null;
  }
}
