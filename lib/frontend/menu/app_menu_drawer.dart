import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Every place the side menu can send the user.
/// The parent decides what each one does (Navigator, tab switch, etc.).
enum MenuDestination {
  home,
  profile,
  payment,
  fraudChecker,
  notices,
  complaint,
  ocrScanner,
  savedDocuments,
  embassyContacts,
  helpSupport,
  about,
  shareApp,
  logout,
}

/// Shared by the menu and the profile screen so logout always asks first.
Future<bool> confirmLogout(BuildContext context, {bool bangla = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(bangla ? 'লগ আউট করবেন?' : 'Log out?'),
      content: Text(
        bangla
            ? 'অ্যাপ ব্যবহার করতে আপনাকে আবার লগইন করতে হবে।'
            : 'You will need to sign in again to use the app.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(bangla ? 'বাতিল' : 'Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.crimsonRed,
            foregroundColor: AppColors.cloudDancer,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(bangla ? 'লগ আউট' : 'Log Out'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _MenuEntry {
  final MenuDestination destination;
  final IconData icon;
  final String en;
  final String bn;
  final bool isNew;

  const _MenuEntry(this.destination, this.icon, this.en, this.bn,
      {this.isNew = false});
}

class AppMenuDrawer extends StatelessWidget {
  final String userName;
  final String phoneNumber;
  final String appVersion;

  /// 'en' or 'bn'.
  final String languageCode;

  /// Highlights the screen the user is currently on.
  final MenuDestination selected;

  final ValueChanged<String>? onLanguageChanged;
  final ValueChanged<MenuDestination> onSelected;

  const AppMenuDrawer({
    super.key,
    required this.userName,
    required this.phoneNumber,
    required this.onSelected,
    this.appVersion = '1.0.0',
    this.languageCode = 'en',
    this.selected = MenuDestination.home,
    this.onLanguageChanged,
  });

  bool get _bn => languageCode == 'bn';

  static const _mainItems = <_MenuEntry>[
    _MenuEntry(MenuDestination.home, Icons.home_outlined, 'Home', 'হোম'),
    _MenuEntry(MenuDestination.payment, Icons.account_balance_wallet_outlined,
        'Payments', 'পেমেন্ট'),
    _MenuEntry(MenuDestination.fraudChecker, Icons.verified_user_outlined,
        'Fraud Checker', 'জালিয়াতি যাচাই'),
    _MenuEntry(MenuDestination.notices, Icons.campaign_outlined, 'Notices',
        'নোটিশ'),
    _MenuEntry(MenuDestination.complaint, Icons.report_gmailerrorred_outlined,
        'File a Complaint', 'অভিযোগ করুন'),
    _MenuEntry(MenuDestination.ocrScanner, Icons.document_scanner_outlined,
        'Document Scanner', 'ডকুমেন্ট স্ক্যানার',
        isNew: true),
    _MenuEntry(MenuDestination.savedDocuments, Icons.folder_shared_outlined,
        'Saved Documents', 'সংরক্ষিত ডকুমেন্ট'),
  ];

  static const _supportItems = <_MenuEntry>[
    _MenuEntry(MenuDestination.embassyContacts, Icons.phone_in_talk_outlined,
        'Embassy & Helplines', 'দূতাবাস ও হেল্পলাইন'),
    _MenuEntry(MenuDestination.helpSupport, Icons.support_agent_outlined,
        'Help & Support', 'সহায়তা ও সাপোর্ট'),
    _MenuEntry(MenuDestination.about, Icons.info_outline_rounded,
        'About the App', 'অ্যাপ সম্পর্কে'),
    _MenuEntry(MenuDestination.shareApp, Icons.ios_share_rounded, 'Share App',
        'অ্যাপ শেয়ার করুন'),
  ];

  Future<void> _select(BuildContext context, MenuDestination d) async {
    final nav = Navigator.of(context);
    if (d == MenuDestination.logout) {
      final ok = await confirmLogout(context, bangla: _bn);
      if (!ok) return;
    }
    nav.pop(); // close the drawer
    onSelected(d);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.cloudDancer,
      width: MediaQuery.of(context).size.width * 0.84 > 340
          ? 340
          : MediaQuery.of(context).size.width * 0.84,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              children: [
                ..._mainItems.map((e) => _buildItem(context, e)),
                const _SoftDivider(),
                ..._supportItems.map((e) => _buildItem(context, e)),
                const _SoftDivider(),
                _buildItem(
                  context,
                  const _MenuEntry(MenuDestination.logout,
                      Icons.logout_rounded, 'Log Out', 'লগ আউট'),
                  danger: true,
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: Text(
                _bn ? 'ভার্সন: $appVersion' : 'Version: $appVersion',
                style: const TextStyle(
                  color: AppColors.royalBlueMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final initial =
        userName.trim().isEmpty ? '?' : userName.trim()[0].toUpperCase();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 16, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.royalBlue,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _bn ? 'মেনু' : 'Menu',
                  style: const TextStyle(
                    color: AppColors.cloudDancer,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              _LanguageToggle(
                languageCode: languageCode,
                onChanged: onLanguageChanged,
              ),
            ],
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: () => _select(context, MenuDestination.profile),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cloudDancer.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cloudDancer.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.cloudDancer,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: AppColors.royalBlue,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.cloudDancer,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          phoneNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.cloudDancer.withValues(alpha: 0.8),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.cloudDancer.withValues(alpha: 0.9)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, _MenuEntry e,
      {bool danger = false}) {
    final isSelected = e.destination == selected;
    final color = danger ? AppColors.crimsonRed : AppColors.royalBlue;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected
            ? AppColors.royalBlue.withValues(alpha: 0.09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _select(context, e.destination),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              children: [
                Icon(e.icon, color: color, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _bn ? e.bn : e.en,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (e.isNew)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _bn ? 'নতুন!' : 'New',
                      style: const TextStyle(
                        color: AppColors.emeraldGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
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

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Divider(
        height: 1,
        color: AppColors.royalBlue.withValues(alpha: 0.12),
      ),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  final String languageCode;
  final ValueChanged<String>? onChanged;

  const _LanguageToggle({required this.languageCode, this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget segment(String code, String label) {
      final active = languageCode == code;
      return GestureDetector(
        onTap: () => onChanged?.call(code),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.cloudDancer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.royalBlue : AppColors.cloudDancer,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.cloudDancer.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment('en', 'Eng'),
          segment('bn', 'বাং'),
        ],
      ),
    );
  }
}