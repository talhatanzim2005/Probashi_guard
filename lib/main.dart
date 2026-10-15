import 'package:flutter/material.dart';
import 'frontend/crChecker/cr_checker_view.dart';
import 'frontend/home/home_view.dart';
import 'frontend/notice/notice_view.dart';
import 'frontend/ocr/ocr_view.dart';
import 'frontend/payment/controllers/payment_controller.dart';
import 'frontend/payment/payment_view.dart';
import 'theme/app_colors.dart';
import 'widget/app_bar.dart';
import 'widget/bottom_navigation_bar.dart';

void main() {
  runApp(const ProbashiGuardApp());
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

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeView(
        onNavigateToNotice: () => _onTabSelected(3),
        onNavigateToCrChecker: _openCrChecker,
      ),
      PaymentView(controller: _paymentController),
      const OcrView(),
      const NoticeView(),
    ];

    return ListenableBuilder(
      listenable: _paymentController,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.cloudDancer,
          appBar: CustomAppBar(
            balanceAmount: _paymentController.unmaskedActiveBalance,
            isBalanceVisible: _paymentController.isBalanceVisible,
            onVisibilityChanged: (_) => _paymentController.toggleBalanceVisibility(),
            onProfileTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Profile tapped'),
                  backgroundColor: AppColors.royalBlue,
                  duration: Duration(seconds: 1),
                ),
              );
            },
            onMenuTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Menu tapped'),
                  backgroundColor: AppColors.royalBlue,
                  duration: Duration(seconds: 1),
                ),
              );
            },
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
