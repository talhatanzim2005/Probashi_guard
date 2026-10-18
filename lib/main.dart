import 'package:flutter/material.dart';
import 'frontend/crChecker/cr_checker_view.dart';
import 'frontend/home/home_view.dart';
import 'frontend/menu/app_menu_drawer.dart';
import 'frontend/notice/notice_view.dart';
import 'frontend/ocr/ocr_view.dart';
import 'frontend/payment/controllers/payment_controller.dart';
import 'frontend/payment/payment_view.dart';
import 'frontend/profile/controllers/profile_controller.dart';
import 'frontend/profile/profile_view.dart';
import 'theme/app_colors.dart';
import 'widget/app_bar.dart';
import 'widget/bottom_navigation_bar.dart';
import 'splash_view.dart';

void main() {
  runApp(const SplashGate());
}

class ProbashiGuardApp extends StatelessWidget {
  const ProbashiGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Probashi Guard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.cloudDancer,
        primaryColor: AppColors.royalBlue,
        colorScheme: const ColorScheme.light(
          primary: AppColors.royalBlue,
          surface: AppColors.cloudDancer,
          error: AppColors.crimsonRed,
        ),
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  final PaymentController _paymentController = PaymentController.instance;
  final ProfileController _profileController = ProfileController.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _openCrChecker() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CrCheckerView()),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileView(
          controller: _profileController,
          onAction: _onProfileAction,
        ),
      ),
    );
  }

  void _comingSoon(String feature) {
    final bn = _profileController.isBangla;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(bn ? '$feature শীঘ্রই আসছে' : '$feature is coming soon'),
        backgroundColor: AppColors.royalBlue,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Which menu item is highlighted for the current bottom-bar tab.
  MenuDestination get _selectedDestination {
    switch (_currentIndex) {
      case 1:
        return MenuDestination.payment;
      case 2:
        return MenuDestination.ocrScanner;
      case 3:
        return MenuDestination.notices;
      default:
        return MenuDestination.home;
    }
  }

  void _onMenuSelected(MenuDestination destination) {
    switch (destination) {
      case MenuDestination.home:
        _onTabSelected(0);
      case MenuDestination.payment:
        _onTabSelected(1);
      case MenuDestination.ocrScanner:
        _onTabSelected(2);
      case MenuDestination.notices:
        _onTabSelected(3);
      case MenuDestination.profile:
        _openProfile();
      case MenuDestination.fraudChecker:
        _openCrChecker();
      case MenuDestination.complaint:
        // TODO: open the Complaint screen once it is ready to link.
        _comingSoon('Complaint');
      case MenuDestination.savedDocuments:
        _comingSoon('Saved Documents');
      case MenuDestination.embassyContacts:
        _comingSoon('Embassy & Helplines');
      case MenuDestination.helpSupport:
        _comingSoon('Help & Support');
      case MenuDestination.about:
        _comingSoon('About');
      case MenuDestination.shareApp:
        _comingSoon('Share App');
      case MenuDestination.logout:
        // TODO(backend): clear the session and go to the login screen.
        _comingSoon('Log out');
    }
  }

  void _onProfileAction(ProfileAction action) {
    switch (action) {
      case ProfileAction.fraudChecker:
        _openCrChecker();
      case ProfileAction.logout:
        // TODO(backend): clear the session and go to the login screen.
        _comingSoon('Log out');
      case ProfileAction.editProfile:
        _comingSoon('Edit Profile');
      case ProfileAction.savedDocuments:
        _comingSoon('Saved Documents');
      case ProfileAction.passportVisa:
        _comingSoon('Passport & Visa');
      case ProfileAction.bmetCard:
        _comingSoon('BMET Smart Card');
      case ProfileAction.changePin:
        _comingSoon('Change PIN');
      case ProfileAction.linkedDevices:
        _comingSoon('Linked Devices');
      case ProfileAction.notifications:
        _comingSoon('Notification Management');
      case ProfileAction.updatePhone:
        _comingSoon('Update Phone Number');
      case ProfileAction.helpSupport:
        _comingSoon('Help & Support');
      case ProfileAction.about:
        _comingSoon('About');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeView(
        userName: _profileController.userName,
        onNavigateToNotice: () => _onTabSelected(3),
        onNavigateToCrChecker: _openCrChecker,
      ),
      PaymentView(controller: _paymentController),
      const OcrView(),
      const NoticeView(),
    ];

    return ListenableBuilder(
      listenable: Listenable.merge([_paymentController, _profileController]),
      builder: (context, _) {
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.cloudDancer,
          endDrawer: AppMenuDrawer(
            userName: _profileController.userName,
            phoneNumber: _profileController.phoneNumber,
            appVersion: _profileController.appVersion,
            languageCode: _profileController.languageCode,
            selected: _selectedDestination,
            onLanguageChanged: _profileController.setLanguage,
            onSelected: _onMenuSelected,
          ),
          appBar: CustomAppBar(
            balanceAmount: _paymentController.unmaskedActiveBalance,
            isBalanceVisible: _paymentController.isBalanceVisible,
            // The app bar already toggles the shared balance state itself.
            // Toggling again here flipped it back (show, then hide), which
            // made the tap look like it did nothing.
            onProfileTap: _openProfile,
            onMenuTap: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          body: screens[_currentIndex],
          bottomNavigationBar: CustomBottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabSelected,
          ),
        );
      },
    );
  }
}