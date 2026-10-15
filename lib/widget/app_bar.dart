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

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(74.0);
}

class _CustomAppBarState extends State<CustomAppBar> {
  final PaymentController _payment = PaymentController.instance;

  bool get _isBalanceVisible =>
      widget.isBalanceVisible ?? _payment.isBalanceVisible;

  void _toggleBalance() {
    _payment.toggleBalanceVisibility();
    widget.onVisibilityChanged?.call(_payment.isBalanceVisible);
    widget.onBalanceTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    // Proportional dimensions:
    // Side icon height: 40.0
    // Combined search (26.0) + balance (22.0) = 48.0 -> Exactly 1.2x of side icon height
    const double kActionHeight = 40.0;
    const double kItemRadius = 8.0;
    const double kSideSpacing = 8.0;
    const double kSearchBarHeight = 26.0;
    const double kBalanceBarHeight = 22.0;
    const double kBarGap = 3.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        border: Border(
          bottom: BorderSide(
            color: AppColors.royalBlue.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: Stack(
        children: [
          // Ambient Cloud Atmosphere decorative contours (strictly in theme palette)
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
            right: 48,
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
          Positioned(
            bottom: 6,
            right: 14,
            child: Icon(
              Icons.cloud_queue,
              size: 50,
              color: AppColors.royalBlue.withValues(alpha: 0.04),
            ),
          ),

          // Main Header Content
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 8.0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Profile Icon at most left (with user's adjusted border radius kItemRadius * 2.5)
                  GestureDetector(
                    onTap: widget.onProfileTap,
                    child: Container(
                      width: kActionHeight,
                      height: kActionHeight,
                      decoration: BoxDecoration(
                        color: AppColors.cloudDancer,
                        borderRadius: BorderRadius.circular(kItemRadius * 2.5),
                        border: Border.all(
                          color: AppColors.royalBlue.withValues(alpha: 0.28),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.royalBlue.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        color: AppColors.royalBlue,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: kSideSpacing),

                  // 2. Center Column: Search Bar + Balance Bar
                  // Naturally and perfectly main-axis aligned with each other
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Search Bar (height: 26.0, border radius: kItemRadius)
                        Container(
                          height: kSearchBarHeight,
                          decoration: BoxDecoration(
                            color: AppColors.cloudDancer,
                            borderRadius: BorderRadius.circular(kItemRadius),
                            border: Border.all(
                              color: AppColors.royalBlue.withValues(
                                alpha: 0.28,
                              ),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.royalBlue.withValues(
                                  alpha: 0.04,
                                ),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: widget.searchController,
                            onChanged: widget.onSearchChanged,
                            style: const TextStyle(
                              color: AppColors.royalBlue,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Search services, agents...',
                              hintStyle: TextStyle(
                                color: AppColors.royalBlue.withValues(
                                  alpha: 0.55,
                                ),
                                fontSize: 11,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: AppColors.royalBlue,
                                size: 15,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: kBarGap),

                        // Balance Bar (height: 22.0, expands on tap, border radius: kItemRadius)
                        ListenableBuilder(
                          listenable: _payment,
                          builder: (context, _) {
                            final effectiveBalance =
                                widget.balanceAmount ?? _payment.unmaskedActiveBalance;

                            return InkWell(
                              onTap: _toggleBalance,
                              borderRadius: BorderRadius.circular(kItemRadius),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                height: _isBalanceVisible ? 28.0 : kBalanceBarHeight,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.cloudDancer,
                                  borderRadius: BorderRadius.circular(kItemRadius),
                                  border: Border.all(
                                    color: _isBalanceVisible
                                        ? AppColors.emeraldGreen
                                        : AppColors.royalBlue.withValues(
                                            alpha: 0.28,
                                          ),
                                    width: 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _isBalanceVisible
                                          ? AppColors.emeraldGreen.withValues(
                                              alpha: 0.08,
                                            )
                                          : AppColors.royalBlue.withValues(
                                              alpha: 0.04,
                                            ),
                                      blurRadius: 3,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: _isBalanceVisible
                                    ? Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.account_balance_wallet,
                                                size: 13,
                                                color: AppColors.emeraldGreen,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                effectiveBalance,
                                                style: const TextStyle(
                                                  color: AppColors.emeraldGreen,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Icon(
                                            Icons.visibility_off_outlined,
                                            size: 13,
                                            color: AppColors.royalBlue,
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Icon(
                                            Icons.touch_app_outlined,
                                            size: 12,
                                            color: AppColors.royalBlue,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Tap to see Balance',
                                            style: TextStyle(
                                              color: AppColors.royalBlue,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.1,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: kSideSpacing),

                  // 3. Hamburger Menu Icon at most right (with user's adjusted border radius kItemRadius * 2)
                  Container(
                    width: kActionHeight,
                    height: kActionHeight,
                    decoration: BoxDecoration(
                      color: AppColors.cloudDancer,
                      borderRadius: BorderRadius.circular(kItemRadius * 2.3),
                      border: Border.all(
                        color: AppColors.royalBlue.withValues(alpha: 0.28),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.royalBlue.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: widget.onMenuTap,
                      icon: const Icon(
                        Icons.menu,
                        color: AppColors.royalBlue,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
