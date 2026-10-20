import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../widget/language_toggle_switch.dart';
import '../../widget/ink_surface.dart';
import '../prohori/prohori_chat_view.dart' show ProhoriAvatar;

/// Every place the side menu can send the user.
/// The parent decides what each one does (Navigator, tab switch, etc.).
enum MenuDestination {
  home,
  prohori,
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
Future<bool> confirmLogout(BuildContext context) async {
  final s = AppStrings.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      // Scrolls on a phone held sideways with large system text.
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(s.logOutQuestion),
      content: Text(s.logOutBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.crimsonRed,
            foregroundColor: AppColors.cloudDancer,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s.logOut),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _MenuEntry {
  final MenuDestination destination;
  final IconData icon;
  final String label;
  final bool isNew;

  const _MenuEntry(
    this.destination,
    this.icon,
    this.label, {
    this.isNew = false,
  });
}

class AppMenuDrawer extends StatelessWidget {
  final String appVersion;

  /// 'en' or 'bn'.
  final String languageCode;

  /// Highlights the screen the user is currently on.
  final MenuDestination selected;

  final ValueChanged<String>? onLanguageChanged;
  final ValueChanged<MenuDestination> onSelected;

  const AppMenuDrawer({
    super.key,
    required this.onSelected,
    this.appVersion = '1.0.0',
    this.languageCode = 'en',
    this.selected = MenuDestination.home,
    this.onLanguageChanged,
  });

  static List<_MenuEntry> _mainItemsFor(AppStrings s) => [
    _MenuEntry(MenuDestination.home, Icons.home_outlined, s.menuHome),
    _MenuEntry(
      MenuDestination.payment,
      Icons.account_balance_wallet_outlined,
      s.menuPayments,
    ),
    _MenuEntry(
      MenuDestination.fraudChecker,
      Icons.verified_user_outlined,
      s.menuFraudChecker,
    ),
    _MenuEntry(MenuDestination.notices, Icons.campaign_outlined, s.menuNotices),
    _MenuEntry(
      MenuDestination.complaint,
      Icons.report_gmailerrorred_outlined,
      s.menuComplaint,
    ),
    _MenuEntry(
      MenuDestination.ocrScanner,
      Icons.document_scanner_outlined,
      s.menuDocumentScanner,
      isNew: true,
    ),
    _MenuEntry(
      MenuDestination.savedDocuments,
      Icons.folder_shared_outlined,
      s.menuSavedDocuments,
    ),
  ];

  static List<_MenuEntry> _supportItemsFor(AppStrings s) => [
    _MenuEntry(
      MenuDestination.embassyContacts,
      Icons.phone_in_talk_outlined,
      s.menuEmbassy,
    ),
    _MenuEntry(
      MenuDestination.helpSupport,
      Icons.support_agent_outlined,
      s.menuHelpSupport,
    ),
    _MenuEntry(MenuDestination.about, Icons.info_outline_rounded, s.menuAbout),
    _MenuEntry(
      MenuDestination.shareApp,
      Icons.ios_share_rounded,
      s.menuShareApp,
    ),
  ];

  Future<void> _select(BuildContext context, MenuDestination d) async {
    final nav = Navigator.of(context);
    if (d == MenuDestination.logout) {
      final ok = await confirmLogout(context);
      if (!ok) return;
    }
    nav.pop(); // close the drawer
    onSelected(d);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

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
                ..._mainItemsFor(s).map((e) => _buildItem(context, e)),
                const _SoftDivider(),
                ..._supportItemsFor(s).map((e) => _buildItem(context, e)),
                const _SoftDivider(),
                _buildItem(
                  context,
                  _MenuEntry(
                    MenuDestination.logout,
                    Icons.logout_rounded,
                    s.logOut,
                  ),
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
                s.version(appVersion),
                style: const TextStyle(
                  color: AppColors.inkMuted,
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
    final s = AppStrings.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 16,
        16,
        20,
      ),
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
                  AppStrings.of(context).menu,
                  style: const TextStyle(
                    color: AppColors.cloudDancer,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const LanguageToggleSwitch(onDarkSurface: true),
            ],
          ),
          const SizedBox(height: 18),
          // Prohori, the AI assistant, sits where the profile card used to be.
          // The profile is one tap away from the avatar in the top bar.
          InkSurface(
            onTap: () => _select(context, MenuDestination.prohori),
            borderRadius: BorderRadius.circular(14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cloudDancer.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.cloudDancer.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const ProhoriAvatar(radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.prohori,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.cloudDancer,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.prohoriSubtitle,
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
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.cloudDancer.withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, _MenuEntry e, {bool danger = false}) {
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
                    e.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
                if (e.isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      AppStrings.of(context).badgeNew,
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
