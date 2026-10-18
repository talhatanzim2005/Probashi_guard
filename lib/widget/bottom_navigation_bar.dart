import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

class CustomBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  /// Content height of the bar (the system gesture/nav inset is added on top).
  static const double kBarHeight = 72.0;

  static List<_NavItemData> _itemsFor(AppStrings s) => [
        _NavItemData(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: s.navHome,
        ),
        _NavItemData(
          icon: Icons.credit_card_outlined,
          activeIcon: Icons.credit_card_rounded,
          label: s.navPayment,
        ),
        _NavItemData(
          icon: Icons.document_scanner_outlined,
          activeIcon: Icons.document_scanner_rounded,
          label: s.navScan,
        ),
        _NavItemData(
          icon: Icons.notifications_none_rounded,
          activeIcon: Icons.notifications_rounded,
          label: s.navNotice,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final items = _itemsFor(AppStrings.of(context));

    // Respect the system font size, but cap it so labels never overflow.
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.2,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cloudDancer,
          border: Border(
            top: BorderSide(
              color: AppColors.royalBlue.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.royalBlue.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: kBarHeight,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavItem(
                      data: items[i],
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _NavItem extends StatelessWidget {
  final _NavItemData data;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.royalBlue : AppColors.royalBlueMuted;
    // The label is normal text; the icon above keeps the royal-blue pair.
    final labelColor = selected ? AppColors.royalBlue : AppColors.inkMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: data.label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Active "pill" behind the icon (Material 3 style indicator).
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: 64,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.royalBlue.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  selected ? data.activeIcon : data.icon,
                  size: 26,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 12.5,
                  // Same size for both states so the bar never "jumps".
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}