import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../menu/app_menu_drawer.dart' show confirmLogout;
import 'controllers/profile_controller.dart';

/// Everything the profile screen can trigger. The parent decides what each
/// one does (push a route, open a sheet, call the API...).
enum ProfileAction {
  editProfile,
  savedDocuments,
  passportVisa,
  bmetCard,
  fraudChecker,
  changePin,
  linkedDevices,
  notifications,
  updatePhone,
  helpSupport,
  about,
  logout,
}

class ProfileView extends StatefulWidget {
  final ProfileController controller;

  /// Tells the parent what the user tapped (push a route, open a sheet...).
  final ValueChanged<ProfileAction>? onAction;

  const ProfileView({
    super.key,
    required this.controller,
    this.onAction,
  });

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  ProfileController get _c => widget.controller;

  bool get _bn => _c.isBangla;
  String _t(String en, String bn) => _bn ? bn : en;

  void _do(ProfileAction action) => widget.onAction?.call(action);

  Future<void> _logout() async {
    final ok = await confirmLogout(context);
    if (ok) _do(ProfileAction.logout);
  }

  void _showLanguageSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cloudDancer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        Widget option(String code, String label) {
          final selected = _c.languageCode == code;
          return ListTile(
            title: Text(
              label,
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            trailing: selected
                ? const Icon(Icons.check_circle_rounded,
                    color: AppColors.emeraldGreen)
                : const Icon(Icons.circle_outlined,
                    color: AppColors.royalBlueMuted),
            onTap: () {
              Navigator.pop(ctx);
              _c.setLanguage(code);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.royalBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _t('Choose language', 'ভাষা নির্বাচন করুন'),
                    style: const TextStyle(
                      color: AppColors.royalBlue,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              option('en', 'English'),
              option('bn', 'বাংলা'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloudDancer,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildProtectionCard(),
                const SizedBox(height: 20),

                _SectionLabel(_t('My Documents', 'আমার ডকুমেন্ট')),
                _GroupCard(children: [
                  _ProfileTile(
                    icon: Icons.folder_shared_outlined,
                    title: _t('Saved Documents', 'সংরক্ষিত ডকুমেন্ট'),
                    onTap: () => _do(ProfileAction.savedDocuments),
                  ),
                  _ProfileTile(
                    icon: Icons.badge_outlined,
                    title: _t('Passport & Visa', 'পাসপোর্ট ও ভিসা'),
                    onTap: () => _do(ProfileAction.passportVisa),
                  ),
                  _ProfileTile(
                    icon: Icons.qr_code_scanner_rounded,
                    title: _t('BMET Smart Card', 'বিএমইটি স্মার্ট কার্ড'),
                    onTap: () => _do(ProfileAction.bmetCard),
                  ),
                ]),
                const SizedBox(height: 20),

                _SectionLabel(_t('Security', 'নিরাপত্তা')),
                _GroupCard(children: [
                  _ProfileTile(
                    icon: Icons.fingerprint_rounded,
                    title: _t('Touch / Face ID', 'টাচ/ফেস আইডি'),
                    subtitle: _t('Lock the app with your biometrics',
                        'বায়োমেট্রিক দিয়ে অ্যাপ লক করুন'),
                    trailing: Switch.adaptive(
                      value: _c.biometricEnabled,
                      activeTrackColor: AppColors.royalBlue,
                      onChanged: _c.setBiometric,
                    ),
                    onTap: () => _c.setBiometric(!_c.biometricEnabled),
                  ),
                  _ProfileTile(
                    icon: Icons.lock_outline_rounded,
                    title: _t('Change PIN', 'পিন পরিবর্তন'),
                    onTap: () => _do(ProfileAction.changePin),
                  ),
                  _ProfileTile(
                    icon: Icons.devices_outlined,
                    title: _t('Linked Devices', 'লিংকড ডিভাইস'),
                    onTap: () => _do(ProfileAction.linkedDevices),
                  ),
                ]),
                const SizedBox(height: 20),

                _SectionLabel(_t('Preferences', 'আপনার পছন্দ')),
                _GroupCard(children: [
                  _ProfileTile(
                    icon: Icons.translate_rounded,
                    title: _t('Language', 'ভাষা'),
                    value: _bn ? 'বাংলা' : 'English',
                    onTap: _showLanguageSheet,
                  ),
                  _ProfileTile(
                    icon: Icons.notifications_none_rounded,
                    title: _t('Notification Management',
                        'নোটিফিকেশন ম্যানেজমেন্ট'),
                    onTap: () => _do(ProfileAction.notifications),
                  ),
                ]),
                const SizedBox(height: 20),

                _SectionLabel(_t('Manage Account', 'একাউন্ট ম্যানেজ করুন')),
                _GroupCard(children: [
                  _ProfileTile(
                    icon: Icons.phone_android_rounded,
                    title: _t('Update Phone Number', 'ফোন নম্বর আপডেট'),
                    onTap: () => _do(ProfileAction.updatePhone),
                  ),
                  _ProfileTile(
                    icon: Icons.support_agent_outlined,
                    title: _t('Help & Support', 'সহায়তা ও সাপোর্ট'),
                    onTap: () => _do(ProfileAction.helpSupport),
                  ),
                  _ProfileTile(
                    icon: Icons.info_outline_rounded,
                    title: _t('About the App', 'অ্যাপ সম্পর্কে'),
                    onTap: () => _do(ProfileAction.about),
                  ),
                ]),
                const SizedBox(height: 24),

                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: Text(
                    _t('Log Out', 'লগ আউট'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.crimsonRed,
                    side: BorderSide(
                        color: AppColors.crimsonRed.withValues(alpha: 0.5)),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    _t('Version: ${_c.appVersion}',
                        'ভার্সন: ${_c.appVersion}'),
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Header: back, title, avatar, name, phone, edit ---
  Widget _buildHeader(BuildContext context) {
    final name = _c.userName.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          8, MediaQuery.of(context).padding.top + 4, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.royalBlue,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.cloudDancer),
                tooltip: _t('Back', 'পিছনে'),
              ),
              Expanded(
                child: Text(
                  _t('My Profile', 'আমার প্রোফাইল'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.cloudDancer,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 48), // balances the back button
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.cloudDancer,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: AppColors.royalBlue,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? _t('Your name', 'আপনার নাম') : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.cloudDancer,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _c.phoneNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.cloudDancer.withValues(alpha: 0.85),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _do(ProfileAction.editProfile),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.cloudDancer,
                    side: const BorderSide(color: AppColors.cloudDancer, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    _t('Edit', 'এডিট'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Protection progress, tied to the home checklist ---
  Widget _buildProtectionCard() {
    final total = _c.checklistTotal;
    final done = _c.checklistCompleted.clamp(0, total);
    final percent = total == 0 ? 0.0 : done / total;

    final Color color;
    final String label;
    if (total > 0 && done == total) {
      color = AppColors.emeraldGreen;
      label = _t('Fully Protected', 'সম্পূর্ণ সুরক্ষিত');
    } else if (percent >= 0.5) {
      color = AppColors.royalBlue;
      label = _t('Partially Protected', 'আংশিক সুরক্ষিত');
    } else {
      color = AppColors.crimsonRed;
      label = _t('Action Needed', 'পদক্ষেপ প্রয়োজন');
    }

    return InkWell(
      onTap: () => _do(ProfileAction.fraudChecker),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cloudDancer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '$done/$total',
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percent,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _t(
                '$done of $total pre-departure checks completed',
                '$total টির মধ্যে $done টি যাচাই সম্পন্ন',
              ),
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.inkMuted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(
          height: 1,
          indent: 64,
          color: AppColors.royalBlue.withValues(alpha: 0.08),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cloudDancer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.royalBlue.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Small text shown before the chevron (e.g. current language).
  final String? value;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.royalBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.royalBlue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  value!,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            trailing ??
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.royalBlueMuted),
          ],
        ),
      ),
    );
  }
}
