import 'package:flutter/material.dart';
import '../frontend/payment/controllers/payment_controller.dart';
import '../theme/app_colors.dart';

class CustomAppBar extends StatefulWidget implements PreferredSizeWidget {
  final VoidCallback? onProfileTap;
  final VoidCallback? onMenuTap;
  final ValueChanged<String>? onSearchChanged;
  final TextEditingController? searchController;
  final String? balanceAmount;
  final VoidCallback? onBalanceTap;
  final bool? isBalanceVisible;
  final ValueChanged<bool>? onVisibilityChanged;

  const CustomAppBar({
    super.key,
    this.onProfileTap,
    this.onMenuTap,
    this.onSearchChanged,
    this.searchController,
    this.balanceAmount,
    this.onBalanceTap,
    this.isBalanceVisible,
    this.onVisibilityChanged,
  });

  // Layout metrics (dp). Kept as statics so preferredSize always matches
  // what the build method actually draws.
  static const double kActionSize = 48.0; // profile / menu (min touch target)
  static const double kSearchHeight = 44.0;
  static const double kBalanceHeight = 36.0;
  static const double kBarGap = 6.0;
  static const double kVerticalPadding = 6.0;
  static const double kHorizontalPadding = 16.0;
  static const double kSideSpacing = 10.0;

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();

  static const double kBorderWidth = 1.0; // bottom divider line

  // 44 + 6 + 36 = 86 content + 12 vertical padding + 1 border = 99.
  // (Scaffold adds the status-bar height on top of this automatically.)
  @override
  Size get preferredSize => const Size.fromHeight(
        kSearchHeight +
            kBarGap +
            kBalanceHeight +
            (kVerticalPadding * 2) +
            kBorderWidth,
      );
}

class _CustomAppBarState extends State<CustomAppBar> {
  final PaymentController _payment = PaymentController.instance;

  // Always follow the shared controller so the top bar and the card can never
  // disagree.
  bool get _isBalanceVisible => _payment.isBalanceVisible;

  void _toggleBalance() {
    _payment.toggleBalanceVisibility();
    widget.onVisibilityChanged?.call(_payment.isBalanceVisible);
    widget.onBalanceTap?.call();
  }

  BoxDecoration _softShadowCircle() => BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.royalBlue.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      );

  Widget _circleButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        decoration: _softShadowCircle(),
        child: Material(
          color: AppColors.cloudDancer,
          shape: CircleBorder(
            side: BorderSide(
              color: AppColors.royalBlue.withValues(alpha: 0.30),
              width: 1.3,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: CustomAppBar.kActionSize,
              height: CustomAppBar.kActionSize,
              child: Icon(icon, color: AppColors.royalBlue, size: 26),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: CustomAppBar.kSearchHeight,
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.royalBlue.withValues(alpha: 0.30),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.royalBlue.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: widget.searchController,
        onChanged: widget.onSearchChanged,
        textInputAction: TextInputAction.search,
        cursorColor: AppColors.royalBlue,
        style: const TextStyle(
          color: AppColors.royalBlue,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Search services, agents...',
          hintStyle: TextStyle(
            color: AppColors.royalBlueMuted,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: AppColors.royalBlue,
            size: 22,
          ),
          prefixIconConstraints: BoxConstraints(minWidth: 42, minHeight: 42),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.only(right: 12),
        ),
      ),
    );
  }

  Widget _buildBalanceBar() {
    return ListenableBuilder(
      listenable: _payment,
      builder: (context, _) {
        final effectiveBalance =
            widget.balanceAmount ?? _payment.unmaskedActiveBalance;
        final visible = _isBalanceVisible;

        return Semantics(
          button: true,
          label: visible
              ? 'Balance $effectiveBalance. Double tap to hide.'
              : 'Balance hidden. Double tap to show.',
          onTap: _toggleBalance,
          excludeSemantics: true,
          child: InkWell(
            onTap: _toggleBalance,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              // Fixed height: the bar never changes size when toggled, so the
              // page below it does not jump.
              height: CustomAppBar.kBalanceHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: visible
                    ? AppColors.emeraldGreen.withValues(alpha: 0.06)
                    : AppColors.cloudDancer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: visible
                      ? AppColors.emeraldGreen
                      : AppColors.royalBlue.withValues(alpha: 0.30),
                  width: 1.2,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: visible
                    ? Row(
                        key: const ValueKey('balance-shown'),
                        children: [
                          const Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 18,
                            color: AppColors.emeraldGreen,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              effectiveBalance,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.emeraldGreen,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                                // Equal-width digits: no wobble.
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.visibility_off_outlined,
                            size: 18,
                            color: AppColors.royalBlue,
                          ),
                        ],
                      )
                    : const Row(
                        key: ValueKey('balance-hidden'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.touch_app_outlined,
                            size: 18,
                            color: AppColors.royalBlue,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Tap to see balance',
                            style: TextStyle(
                              color: AppColors.royalBlue,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
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

  @override
  Widget build(BuildContext context) {
    // Larger system font sizes are respected, but capped so the fixed-height
    // bar can never overflow.
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.15,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cloudDancer,
          border: Border(
            bottom: BorderSide(
              color: AppColors.royalBlue.withValues(alpha: 0.14),
              width: CustomAppBar.kBorderWidth,
            ),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Ambient cloud decoration (theme palette only)
            Positioned(
              top: -24,
              left: -18,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.royalBlue.withValues(alpha: 0.035),
                ),
              ),
            ),
            Positioned(
              top: -12,
              right: 56,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.royalBlue.withValues(alpha: 0.025),
                ),
              ),
            ),
            Positioned(
              bottom: -28,
              right: -16,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.royalBlue.withValues(alpha: 0.03),
                ),
              ),
            ),

            // Main header content
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CustomAppBar.kHorizontalPadding,
                  vertical: CustomAppBar.kVerticalPadding,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _circleButton(
                      icon: Icons.person_rounded,
                      label: 'Profile',
                      onTap: widget.onProfileTap,
                    ),
                    const SizedBox(width: CustomAppBar.kSideSpacing),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSearchField(),
                          const SizedBox(height: CustomAppBar.kBarGap),
                          _buildBalanceBar(),
                        ],
                      ),
                    ),
                    const SizedBox(width: CustomAppBar.kSideSpacing),
                    _circleButton(
                      icon: Icons.menu_rounded,
                      label: 'Open menu',
                      onTap: widget.onMenuTap,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}