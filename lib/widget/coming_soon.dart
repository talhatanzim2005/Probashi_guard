import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

/// The one answer for a feature whose screen is not built yet: a short
/// "[feature] is coming soon" message, in the app language, so a tap on it is
/// never silent.
///
/// Every tap that has nowhere to go yet should end here, rather than in an
/// empty callback. [feature] is the name as the person sees it (pass the
/// translated label, not an English constant).
void showComingSoon(BuildContext context, String feature) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    // A second tap replaces the first instead of queueing a row of them.
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context).comingSoon(feature)),
        backgroundColor: AppColors.royalBlue,
        duration: const Duration(seconds: 2),
      ),
    );
}
