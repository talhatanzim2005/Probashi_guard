import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class CustomBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        boxShadow: [
          BoxShadow(
            color: AppColors.royalBlue.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onTap,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.cloudDancer,
          selectedItemColor: AppColors.royalBlue,
          unselectedItemColor: AppColors.royalBlue.withValues(alpha: 0.65),
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          // Same size as the selected label so the bar doesn't "jump" on tap.
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
          elevation: 0,
          items: const [
            // 1. Home
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            // 2. Payment
            BottomNavigationBarItem(
              icon: Icon(Icons.credit_card),
              label: 'Payment',
            ),
            // 3. Scan
            BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner),
              label: 'Scan QR',
            ),
            // 4. Notice
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications),
              label: 'Notice',
            ),
          ],
        ),
      ),
    );
  }
}