abstract final class PhoneUtils {
  static String? normalizeForComparison(String? value) {
    if (value == null) {
      return null;
    }

    String digitsOnly = value.replaceAll(RegExp(r'\D'), '');
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
    return value.replaceAll(RegExp(r'\D'), '');
  }
}
