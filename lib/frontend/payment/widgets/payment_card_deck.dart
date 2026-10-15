import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../controllers/payment_controller.dart';

class PaymentCardDeck extends StatefulWidget {
  final PaymentController controller;

  const PaymentCardDeck({
    super.key,
    required this.controller,
  });

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

    return GestureDetector(
      onTap: () {
        controller.cycleCardToFront();
      },
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 100) {
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thirdCard.providerName.split(' ').first.toUpperCase(),
                      style: TextStyle(
                        color: AppColors.cloudDancer.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      thirdCard.title,
                      style: const TextStyle(
                        color: AppColors.cloudDancer,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Layer 2: Middle Card (peeking below back card with white/cloud surface)
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nextCard.cardNumberMasked,
                      style: TextStyle(
                        color: AppColors.royalBlue.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      nextCard.title,
                      style: const TextStyle(
                        color: AppColors.royalBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Layer 3: Front Card (Dark Obsidian primary container with curved silhouette)
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
                child: Stack(
                  children: [
                    // Top glass highlight decorative accent
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
                          // Top Row: Card Title & Tap Indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: activeCard.accentColor.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: activeCard.accentColor.withValues(alpha: 0.35),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      activeCard.title.toUpperCase(),
                                      style: TextStyle(
                                        color: activeCard.accentColor,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    activeCard.cardNumberMasked,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.45),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Text(
                                    'TAP TO SWITCH',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.35),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.layers_outlined,
                                    size: 13,
                                    color: Colors.white.withValues(alpha: 0.35),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // Middle: Total Balance & Eye Toggle
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Available Balance',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.65),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    transitionBuilder: (child, animation) => FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                    child: Text(
                                      controller.formattedActiveBalance,
                                      key: ValueKey(
                                        '${controller.formattedActiveBalance}_${controller.isBalanceVisible}',
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 27,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                        fontFamily: 'sans-serif',
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // Toggle Eye Button
                              GestureDetector(
                                onTap: controller.toggleBalanceVisibility,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                  child: Icon(
                                    controller.isBalanceVisible
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: Colors.white.withValues(alpha: 0.8),
                                    size: 19,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Bottom Row: Expiry & Provider Branding
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'EXP ${activeCard.expiryDate}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Text(
                                activeCard.providerName,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
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
          ],
        ),
      ),
    );
  }
}
