import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'frontend/crChecker/cr_checker_view.dart';
import 'frontend/documents/document_scan_view.dart';
import 'frontend/documents/saved_documents_portal_view.dart';
import 'frontend/home/app_search_view.dart';
import 'frontend/home/home_view.dart';
import 'frontend/menu/app_menu_drawer.dart';
import 'frontend/notice/notice_view.dart';
import 'frontend/payment/controllers/payment_controller.dart';
import 'frontend/payment/payment_view.dart';
import 'frontend/profile/controllers/profile_controller.dart';
import 'frontend/profile/profile_view.dart';
import 'l10n/app_strings.dart';
import 'l10n/language_controller.dart';
import 'theme/app_colors.dart';
import 'widget/app_bar.dart';
import 'widget/bottom_navigation_bar.dart';
import 'splash_view.dart';

// Override for another project with:
//   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://xfwxiawapksepskcevwe.supabase.co',
);
const _supabaseKey = String.fromEnvironment(
  'SUPABASE_KEY',
  defaultValue: 'sb_publishable_j189-L73p34K9QMvj-2Msg_dTYOWhIh',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read the saved language first, so the app opens in it rather than
  // flashing English and then switching.
  await LanguageController.instance.load();
  await _initSupabase();
  runApp(const SplashGate());
}

/// The document vault and transaction history are scoped to a Supabase user, so
/// every device signs in anonymously and row-level security keeps its rows private.
/// A failure here is not fatal: the app still runs, but scans are not saved.
Future<void> _initSupabase() async {
  try {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseKey);
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser != null) return;
    await auth.signInAnonymously().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('[main] Supabase unavailable; the document vault is disabled: $e');
  }
}

class ProbashiGuardApp extends StatelessWidget {
  const ProbashiGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LanguageController.instance,
      builder: (context, locale, _) => AppStringsScope(
        strings: AppStrings(locale.languageCode),
        child: _buildApp(locale),
      ),
    );
  }

  Widget _buildApp(Locale locale) {
    return MaterialApp(
      title: 'Probashi Guard',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: LanguageController.supportedLocales,
      localizationsDelegates: LanguageController.localizationsDelegates,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.cloudDancer,
        primaryColor: AppColors.royalBlue,
        colorScheme: const ColorScheme.light(
          primary: AppColors.royalBlue,
          surface: AppColors.cloudDancer,
          error: AppColors.crimsonRed,
        ),
        // Normal text is #040303 unless a widget sets its own colour, so new
        // Text() does not fall back to Material's black87.
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: AppColors.ink,
              displayColor: AppColors.ink,
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

  /// Checking a document for fraud *is* the scanner, so Fraud Checker opens it.
  /// From a pushed screen (the profile page) the shell has to come back first.
  void _openFraudChecker() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _onTabSelected(2);
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

  /// The vault of documents already scanned on this device.
  void _openSavedDocuments() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SavedDocumentsPortalView()),
    );
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppSearchView(
          onNavigateTab: _onTabSelected,
          onOpenMenu: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
      ),
    );
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.of(context).comingSoon(feature)),
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
        _openFraudChecker();
      case MenuDestination.complaint:
        // TODO: open the Complaint screen once it is ready to link.
        _comingSoon('Complaint');
      case MenuDestination.savedDocuments:
        _openSavedDocuments();
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
        _openFraudChecker();
      case ProfileAction.logout:
        // TODO(backend): clear the session and go to the login screen.
        _comingSoon('Log out');
      case ProfileAction.editProfile:
        _comingSoon('Edit Profile');
      case ProfileAction.savedDocuments:
        _openSavedDocuments();
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
        onNavigateToFraudChecker: _openFraudChecker,
        onOpenSavedDocuments: _openSavedDocuments,
        onSearchTap: _openSearch,
      ),
      PaymentView(controller: _paymentController),
      const DocumentScanView(),
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
            onSearchTap: _openSearch,
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