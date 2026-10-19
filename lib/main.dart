import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'frontend/auth/auth_session.dart';
import 'frontend/auth/phone_setup_view.dart';
import 'frontend/crChecker/controllers/checklist_controller.dart';
import 'frontend/crChecker/cr_checker_view.dart';
import 'frontend/documents/document_scan_view.dart';
import 'frontend/documents/saved_documents_portal_view.dart';
import 'frontend/home/app_search_view.dart';
import 'frontend/home/home_view.dart';
import 'frontend/menu/app_menu_drawer.dart';
import 'frontend/notice/notice_view.dart';
import 'frontend/payment/controllers/payment_controller.dart';
import 'frontend/payment/repository/payment_local_store.dart';
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
  // Everything the person has saved on this device comes back before the first
  // frame, so no screen flashes its defaults and then jumps.
  await Future.wait([
    ChecklistController.instance.load(),
    ProfileController.instance.load(),
    PaymentLocalStore.load(),
  ]);
  await _initSupabase();
  await _initFirebase();
  runApp(const ProbashiGuardApp());
}

/// Restores a saved login, if any. Nobody is signed in anonymously any more:
/// the login screen comes first, so the vault and history always belong to a
/// real account. (Phones still holding an older anonymous session have its
/// data moved over at login — see `lib/frontend/auth/auth_session.dart`.)
/// A failure here is not fatal: the app still opens, but cannot log in.
Future<void> _initSupabase() async {
  try {
    // ignore: deprecated_member_use
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseKey);
  } catch (e) {
    debugPrint('[main] Supabase unavailable; login and the vault are disabled: $e');
  }
}

/// Firebase is used for ONE thing: proving a phone number over SMS. It is not
/// an identity system here — Supabase is.
///
/// It is absent until `google-services.json` / `GoogleService-Info.plist` are
/// in place, and initialising without them throws. That is not fatal: the
/// phone screen notices Firebase is missing, says verification is not set up
/// and lets the person carry on unverified, which only costs them the ability
/// to move money.
///
/// Web and Android get their config differently. A browser has no
/// google-services.json, and `initializeApp()` with no options there means
/// "use the app the HTML page already created" — none exists, which is the
/// `[core/no-app]` error — so web needs the generated options. Android reads
/// google-services.json through the Gradle plugin and takes no options;
/// `DefaultFirebaseOptions.currentPlatform` deliberately throws for it, since
/// only the web app was generated (regenerating Android through flutterfire
/// would rewrite the conditional Gradle setup).
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp(
      options: kIsWeb ? DefaultFirebaseOptions.currentPlatform : null,
    );
  } catch (e) {
    debugPrint('[main] Firebase not configured; phone verification is off: $e');
  }
}

class ProbashiGuardApp extends StatelessWidget {
  final Widget? home;
  const ProbashiGuardApp({super.key, this.home});

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
      home: home ?? const SplashView(),
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

  /// Brings the person to the checklist card on Home, from anywhere (the
  /// profile banner is on a pushed screen, so the shell has to come back first).
  void _openChecklist() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _onTabSelected(0);
    // The Home tab may only just have been built; wait a frame so it is
    // listening before the scroll is requested.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ChecklistController.instance.requestFocus(),
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

  /// Profile > Update Phone Number: the same verify screen as after login,
  /// pushed on top of the profile so a verified number comes back to it.
  void _openPhoneSetup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PhoneSetupView(openedFromProfile: true),
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
        // The drawer has already asked "Log out?".
        signOut(context);
    }
  }

  void _onProfileAction(ProfileAction action) {
    switch (action) {
      case ProfileAction.fraudChecker:
        _openFraudChecker();
      case ProfileAction.checklist:
        _openChecklist();
      case ProfileAction.logout:
        // The profile screen has already asked "Log out?".
        signOut(context);
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
        _openPhoneSetup();
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