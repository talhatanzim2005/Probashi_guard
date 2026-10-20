import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../l10n/app_strings.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';

class PaymentCardDeck extends StatefulWidget {
  final PaymentController controller;

  const PaymentCardDeck({super.key, required this.controller});

  @override
  State<PaymentCardDeck> createState() => _PaymentCardDeckState();
}

class _PaymentCardDeckState extends State<PaymentCardDeck> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final cards = controller.cards;
    if (cards.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.royalBlue),
        ),
      );
    }

    final activeIndex = controller.activeCardIndex % cards.length;
    final activeCard = cards[activeIndex];

    // Other two cards for the layered stack
    final nextCard = cards[(activeIndex + 1) % cards.length];
    final thirdCard = cards[(activeIndex + 2) % cards.length];

    // The card has a fixed height, so the system font size is capped here to
    // keep the text from overflowing it.
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.15,
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity!.abs() > 100) {
            controller.cycleCardToFront();
          }
        },
        child: Container(
          height: 215,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.royalBlue.withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Layer 1: Back Card (peeking at top)
              Positioned(
                top: 0,
                left: 14,
                right: 14,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  height: 180,
                  decoration: BoxDecoration(
                    color: AppColors.royalBlue,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: _CardInk(
                    borderRadius: BorderRadius.circular(24),
                    splashColor: Colors.white.withValues(alpha: 0.2),
                    onTap: () => controller.setActiveCardIndex(activeIndex + 2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              thirdCard.providerName
                                  .split(' ')
                                  .first
                                  .toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.cloudDancer.withValues(
                                  alpha: 0.8,
                                ),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              thirdCard.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: AppColors.cloudDancer,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Layer 2: Middle Card (peeking below back card)
              Positioned(
                top: 24,
                left: 8,
                right: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  height: 175,
                  decoration: BoxDecoration(
                    color: AppColors.cloudDancer,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.royalBlue.withValues(alpha: 0.12),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _CardInk(
                    borderRadius: BorderRadius.circular(23),
                    splashColor: AppColors.royalBlue.withValues(alpha: 0.14),
                    onTap: () => controller.setActiveCardIndex(activeIndex + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              nextCard.cardNumberMasked,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.royalBlue.withValues(
                                  alpha: 0.6,
                                ),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              nextCard.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: AppColors.royalBlue,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Layer 3: Front Card
              Positioned(
                top: 48,
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: activeCard.primaryColor,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  // Tapping the front card gives a soft ripple and a light tap
                  // of haptics. (Switching cards is done on the cards peeking
                  // out behind it; the balance and eye controls inside keep
                  // their own taps.)
                  child: _CardInk(
                    borderRadius: BorderRadius.circular(25),
                    splashColor: Colors.white.withValues(alpha: 0.14),
                    onTap: HapticFeedback.selectionClick,
                    child: Stack(
                      children: [
                        // Top glass highlight
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 24,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.05),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Front Card Content
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Top Row: card title badge, masked number,
                              // and the "switch card" hint icon.
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: activeCard.accentColor
                                                  .withValues(alpha: 0.18),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: activeCard.accentColor
                                                    .withValues(alpha: 0.35),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Text(
                                              activeCard.title.toUpperCase(),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: activeCard.accentColor,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          activeCard.cardNumberMasked,
                                          maxLines: 1,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.55,
                                            ),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Semantics(
                                    label: AppStrings.of(
                                      context,
                                    ).tapCardToSwitch,
                                    child: Icon(
                                      Icons.layers_outlined,
                                      size: 16,
                                      color: Colors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // Middle: Balance & eye toggle
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppStrings.of(
                                            context,
                                          ).availableBalance,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.7,
                                            ),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        // Hidden by default. While hidden, tapping
                                        // this area reveals the balance. While
                                        // shown, taps fall through to the card
                                        // (switch card) as before.
                                        Semantics(
                                          button: !controller.isBalanceVisible,
                                          label: controller.isBalanceVisible
                                              ? AppStrings.of(
                                                  context,
                                                ).balanceShownA11y(
                                                  controller
                                                      .formattedActiveBalance,
                                                )
                                              : AppStrings.of(
                                                  context,
                                                ).balanceHiddenA11y,
                                          onTap: controller.isBalanceVisible
                                              ? null
                                              : controller
                                                    .toggleBalanceVisibility,
                                          excludeSemantics: true,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: controller.isBalanceVisible
                                                ? null
                                                : controller
                                                      .toggleBalanceVisibility,
                                            // Fixed height so the card never jumps
                                            // between hidden and shown states.
                                            child: SizedBox(
                                              height: 34,
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                  milliseconds: 220,
                                                ),
                                                transitionBuilder:
                                                    (child, animation) =>
                                                        FadeTransition(
                                                          opacity: animation,
                                                          child: child,
                                                        ),
                                                layoutBuilder:
                                                    (current, previous) =>
                                                        Stack(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          children: [
                                                            ...previous,
                                                            ?current,
                                                          ],
                                                        ),
                                                child:
                                                    controller.isBalanceVisible
                                                    // FittedBox: a long balance
                                                    // shrinks to fit, never overflows.
                                                    ? FittedBox(
                                                        key: ValueKey(
                                                          'balance-shown-${controller.formattedActiveBalance}',
                                                        ),
                                                        fit: BoxFit.scaleDown,
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Text(
                                                          controller
                                                              .formattedActiveBalance,
                                                          maxLines: 1,
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 27,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            letterSpacing: -0.5,
                                                            fontFamily:
                                                                'sans-serif',
                                                            // Equal-width digits.
                                                            fontFeatures: [
                                                              FontFeature.tabularFigures(),
                                                            ],
                                                          ),
                                                        ),
                                                      )
                                                    : Row(
                                                        key: const ValueKey(
                                                          'balance-hidden',
                                                        ),
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .touch_app_outlined,
                                                            size: 18,
                                                            color: Colors.white
                                                                .withValues(
                                                                  alpha: 0.85,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Flexible(
                                                            child: Text(
                                                              AppStrings.of(
                                                                context,
                                                              ).tapToSeeBalance,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                letterSpacing:
                                                                    0.1,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Toggle Eye Button
                                  Semantics(
                                    button: true,
                                    label: controller.isBalanceVisible
                                        ? AppStrings.of(context).hideBalance
                                        : AppStrings.of(context).showBalance,
                                    onTap: controller.toggleBalanceVisibility,
                                    excludeSemantics: true,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: controller.toggleBalanceVisibility,
                                      // Extra padding = bigger touch target (~44px)
                                      // without changing how the button looks.
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          8,
                                          6,
                                          0,
                                          6,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                          ),
                                          child: Icon(
                                            controller.isBalanceVisible
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                            color: Colors.white.withValues(
                                              alpha: 0.8,
                                            ),
                                            size: 19,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // Bottom Row: Expiry & Provider Branding
                              Row(
                                children: [
                                  Text(
                                    'EXP ${activeCard.expiryDate}',
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.55,
                                      ),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      activeCard.providerName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.65,
                                        ),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable layer of the card deck.
///
/// A ripple is painted on the nearest [Material] above the tapped widget, so
/// the card's own colour (a [Container] decoration) would cover it if the
/// [InkWell] sat above that colour. This transparent Material sits inside the
/// coloured container instead, and clips the ripple to the card's corners.
class _CardInk extends StatelessWidget {
  final BorderRadius borderRadius;
  final Color splashColor;
  final VoidCallback onTap;
  final Widget child;

  const _CardInk({
    required this.borderRadius,
    required this.splashColor,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        // InkRipple is the quiet one; the sparkle used on Android is too loud
        // for a card.
        splashFactory: InkRipple.splashFactory,
        splashColor: splashColor,
        highlightColor: splashColor.withValues(alpha: splashColor.a / 2),
        child: child,
      ),
    );
  }
}
