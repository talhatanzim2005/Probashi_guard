import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class NoticeView extends StatelessWidget {
  const NoticeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloudDancer,
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Official Notices',
            style: TextStyle(
              color: AppColors.royalBlue,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: AppColors.cloudDancer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.crimsonRed.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.crimsonRed,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Urgent Airport Clearance Advisory',
                        style: TextStyle(
                          color: AppColors.crimsonRed,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Important Advisory: Verify all job offers and CR numbers before airport departure.',
                        style: TextStyle(
                          color: AppColors.royalBlue.withValues(alpha: 0.8),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
