import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../l10n/language_controller.dart';
import '../theme/app_colors.dart';

/// A pill-shaped "বাংলা | ENG" switch, in the style bKash uses.
///
/// One tap flips the language for the whole app — the active segment slides
/// rather than cutting, so it is obvious which side is selected even to someone
/// who cannot read the other label.
///
/// Place it wherever a person might get stuck: the home app bar and the menu
/// drawer both show it.
class LanguageToggleSwitch extends StatelessWidget {
  /// `true` renders light-on-dark, for use on a royal blue surface such as the
  /// drawer header. `false` is the default dark-on-light pill.
  final bool onDarkSurface;

  /// Slightly smaller pill, for sitting inside an app bar.
  final bool compact;

  const LanguageToggleSwitch({
    super.key,
    this.onDarkSurface = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageController.instance,
      builder: (context, locale, _) {
        final isBangla = locale.languageCode == LanguageController.banglaCode;
        final s = AppStrings.of(context);

        final trackColor = onDarkSurface
            ? AppColors.cloudDancer.withValues(alpha: 0.18)
            : AppColors.royalBlue.withValues(alpha: 0.08);
        final borderColor = onDarkSurface
            ? AppColors.cloudDancer.withValues(alpha: 0.45)
            : AppColors.royalBlue.withValues(alpha: 0.25);
        final knobColor =
            onDarkSurface ? AppColors.cloudDancer : AppColors.royalBlue;
        final activeLabel =
            onDarkSurface ? AppColors.royalBlue : AppColors.cloudDancer;
        final idleLabel =
            onDarkSurface ? AppColors.cloudDancer : AppColors.royalBlue;

        final height = compact ? 28.0 : 32.0;
        final width = compact ? 84.0 : 104.0;
        final radius = height / 2;

        return Semantics(
          button: true,
          label: s.language,
          value: isBangla ? 'বাংলা' : 'English',
          excludeSemantics: true,
          child: Tooltip(
            message: s.chooseLanguage,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                LanguageController.instance.toggle();
              },
              child: Container(
                height: height,
                width: width,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: borderColor, width: 1),
                ),
                // Halves rather than fixed widths: the 1px border shrinks the
                // content box, which would overflow two fixed-width segments.
                child: Stack(
                  children: [
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: isBangla
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: FractionallySizedBox(
                        widthFactor: 0.5,
                        heightFactor: 1.0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: knobColor,
                            borderRadius: BorderRadius.circular(radius),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        _segment(
                          label: 'বাংলা',
                          selected: isBangla,
                          activeColor: activeLabel,
                          idleColor: idleLabel,
                          compact: compact,
                        ),
                        _segment(
                          label: 'ENG',
                          selected: !isBangla,
                          activeColor: activeLabel,
                          idleColor: idleLabel,
                          compact: compact,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _segment({
    required String label,
    required bool selected,
    required Color activeColor,
    required Color idleColor,
    required bool compact,
  }) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: selected ? activeColor : idleColor,
            // Same weight both ways so the pill never changes width.
            fontWeight: FontWeight.w800,
            fontSize: compact ? 11 : 12,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}
