import 'package:flutter/material.dart';

import '../../crChecker/cr_checker_view.dart';
import '../../documents/saved_documents_portal_view.dart';
import '../../notice/notice_view.dart';
import '../../payment/controllers/payment_controller.dart';
import '../../payment/flows/send_flow_view.dart';
import '../../profile/controllers/profile_controller.dart';
import '../../profile/profile_view.dart';
import '../models/search_action_item.dart';

/// Centralized registry of all primary searchable app services and features.
class SearchServiceRegistry {
  SearchServiceRegistry._();

  static List<SearchActionItem> getServices({
    void Function(int tabIndex)? onNavigateTab,
    VoidCallback? onOpenMenu,
  }) {
    return [
      SearchActionItem(
        id: 'scan_passport',
        titleEn: 'Scan Passport',
        titleBn: 'পাসপোর্ট স্ক্যান',
        subtitleEn: 'Verify passport MRZ and validity',
        subtitleBn: 'পাসপোর্টের এমআরজেড ও মেয়াদ যাচাই',
        icon: Icons.document_scanner_rounded,
        keywords: [
          'passport',
          'pass',
          'mrz',
          'travel document',
          'পাসপোর্ট',
          'পাসপোড',
          'স্ক্যান',
          'passport scan',
          'scan',
          'passpot',
          'bidesh',
          'travel',
        ],
        action: (context) {
          if (onNavigateTab != null) {
            Navigator.pop(context);
            onNavigateTab(2);
          } else {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
      ),
      SearchActionItem(
        id: 'contract_fraud',
        titleEn: 'Check Contract Fraud',
        titleBn: 'চুক্তি যাচাই',
        subtitleEn: 'AI verification of job offer and visa',
        subtitleBn: 'এআই দিয়ে চাকরির চুক্তি ও ভিসা যাচাই',
        icon: Icons.verified_user_outlined,
        keywords: [
          'contract',
          'fraud',
          'agreement',
          'visa',
          'job',
          'offer letter',
          'চুক্তি',
          'ভিসা',
          'জালিয়াতি',
          'প্রতারণা',
          'যাচাই',
          'chukti',
          'dhanda',
          'dalal',
          'fake visa',
          'bogus',
        ],
        action: (context) {
          if (onNavigateTab != null) {
            Navigator.pop(context);
            onNavigateTab(2);
          } else {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
      ),
      SearchActionItem(
        id: 'send_remittance',
        titleEn: 'Send Remittance',
        titleBn: 'টাকা পাঠান',
        subtitleEn: 'Instant transfer to Bangladesh with 2.5% incentive',
        subtitleBn: '২.৫% প্রণোদনাসহ তাৎক্ষণিক দেশে টাকা পাঠান',
        icon: Icons.send_rounded,
        keywords: [
          'send',
          'money',
          'remittance',
          'transfer',
          'bkash',
          'bank',
          'টাকা',
          'পাঠান',
          'রেমিট্যান্স',
          'প্রণোদনা',
          'taka',
          'pathan',
          'send money',
          'recharge',
          'payment',
          'pay',
        ],
        action: (context) {
          if (onNavigateTab != null) {
            Navigator.pop(context);
            onNavigateTab(1);
          } else {
            SendFlowView.push(
              context,
              controller: PaymentController.instance,
            );
          }
        },
      ),
      SearchActionItem(
        id: 'saved_documents',
        titleEn: 'Saved Documents',
        titleBn: 'সংরক্ষিত কাগজপত্র',
        subtitleEn: 'Access your scanned passes, visas, and contracts',
        subtitleBn: 'আপনার স্ক্যান করা পাসপোর্ট, ভিসা ও চুক্তিপত্র',
        icon: Icons.folder_shared_rounded,
        keywords: [
          'saved',
          'documents',
          'vault',
          'files',
          'papers',
          'records',
          'সংরক্ষিত',
          'কাগজপত্র',
          'ডকুমেন্ট',
          'ফাইল',
          'kagoj',
          'dokument',
          'saved doc',
          'history',
        ],
        action: (context) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SavedDocumentsPortalView(),
            ),
          );
        },
      ),
      SearchActionItem(
        id: 'official_notices',
        titleEn: 'Official Notices',
        titleBn: 'সরকারি নোটিশ',
        subtitleEn: 'Important government alerts and embassy news',
        subtitleBn: 'গুরুত্বপূর্ণ সরকারি বিজ্ঞপ্তি ও দূতাবাস সংবাদ',
        icon: Icons.campaign_rounded,
        keywords: [
          'notice',
          'notices',
          'news',
          'government',
          'embassy',
          'alerts',
          'circular',
          'নোটিশ',
          'খবর',
          'সংবাদ',
          'বিজ্ঞপ্তি',
          'সরকারি',
          'notis',
          'khobor',
          'notish',
          'bulletin',
        ],
        action: (context) {
          if (onNavigateTab != null) {
            Navigator.pop(context);
            onNavigateTab(3);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const Scaffold(
                  body: SafeArea(child: NoticeView()),
                ),
              ),
            );
          }
        },
      ),
      SearchActionItem(
        id: 'departure_checklist',
        titleEn: 'Pre-Departure Checklist',
        titleBn: 'যাত্রা পূর্ব চেকলিস্ট',
        subtitleEn: 'Essential steps before traveling abroad',
        subtitleBn: 'বিদেশ যাওয়ার আগে প্রয়োজনীয় প্রস্তুতি',
        icon: Icons.checklist_rounded,
        keywords: [
          'checklist',
          'departure',
          'flight',
          'travel',
          'preparation',
          'bmet',
          'medical',
          'চেকলিস্ট',
          'প্রস্তুতি',
          'যাত্রা',
          'চেক',
          'cheklist',
          'bidesh jatra',
          'travel checklist',
        ],
        action: (context) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CrCheckerView(),
            ),
          );
        },
      ),
      SearchActionItem(
        id: 'profile_settings',
        titleEn: 'Profile & Settings',
        titleBn: 'প্রোফাইল ও সেটিংস',
        subtitleEn: 'Manage your account, PIN, and preferences',
        subtitleBn: 'অ্যাকাউন্ট, পিন ও পছন্দসমূহ পরিচালনা করুন',
        icon: Icons.settings_rounded,
        keywords: [
          'profile',
          'settings',
          'account',
          'pin',
          'security',
          'preferences',
          'language',
          'প্রোফাইল',
          'সেটিংস',
          'অ্যাকাউন্ট',
          'পিন',
          'profil',
          'setting',
          'security',
        ],
        action: (context) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileView(
                controller: ProfileController.instance,
              ),
            ),
          );
        },
      ),
    ];
  }
}
