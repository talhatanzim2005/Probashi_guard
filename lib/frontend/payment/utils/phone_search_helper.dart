import '../models/beneficiary_model.dart';

class PhoneSearchHelper {
  /// Extracts only numeric digits [0-9] from any string
  static String extractDigits(String input) {
    return input.replaceAll(RegExp(r'\D'), '');
  }

  /// Determines if a beneficiary matches the search query using
  /// standard mobile contact search patterns (WhatsApp / Google Contacts style)
  static bool matches(BeneficiaryModel contact, String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return true;

    final lowerQuery = query.toLowerCase();

    // 1. Name match (case-insensitive substring)
    if (contact.name.toLowerCase().contains(lowerQuery)) {
      return true;
    }

    // 2. Country name, flag, or country code match
    if (contact.countryName.toLowerCase().contains(lowerQuery) ||
        contact.countryCode.toLowerCase().contains(lowerQuery) ||
        contact.countryFlag.contains(query)) {
      return true;
    }

    // 3. Provider match (e.g. bKash, STC Pay, Nagad)
    if (contact.providerType.toLowerCase().contains(lowerQuery)) {
      return true;
    }

    // 4. Raw phone/account string match (handles hyphens/spaces if typed literally)
    if (contact.phoneOrAccount.toLowerCase().contains(lowerQuery)) {
      return true;
    }

    // 5. Intelligent Normalized Digits Search
    final queryDigits = extractDigits(query);
    if (queryDigits.isNotEmpty) {
      final contactDigits = extractDigits(contact.phoneOrAccount);

      // 5a. Direct digits substring (e.g. '345678' inside '8801712345678')
      if (contactDigits.contains(queryDigits)) {
        return true;
      }

      // 5b. Local dialing format with leading zero:
      // Contact is '+880 1712...' (digits: 8801712...)
      // User types '01712...' (digits: 01712...)
      // Strip leading zero from query -> '1712...'
      final strippedQueryLeadingZero = queryDigits.startsWith('0')
          ? queryDigits.replaceFirst(RegExp(r'^0+'), '')
          : queryDigits;

      if (strippedQueryLeadingZero.isNotEmpty &&
          contactDigits.contains(strippedQueryLeadingZero)) {
        return true;
      }

      // 5c. National number without country code:
      // Contact has dial code (e.g. 880 or 966) at the beginning
      // Check if contact without dial code matches query
      final dialCodeDigits = extractDigits(contact.countryDialCode);
      if (dialCodeDigits.isNotEmpty && contactDigits.startsWith(dialCodeDigits)) {
        final localContactDigits = contactDigits.substring(dialCodeDigits.length);
        if (localContactDigits.contains(queryDigits) ||
            localContactDigits.contains(strippedQueryLeadingZero)) {
          return true;
        }
      }

      // 5d. End-of-number / suffix match (e.g. typing the last 4-8 digits)
      if (queryDigits.length >= 3 && contactDigits.endsWith(queryDigits)) {
        return true;
      }
    }

    return false;
  }
}
