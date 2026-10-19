import 'package:flutter/material.dart';
import 'frontend/splash/splash_view.dart';

export 'frontend/splash/splash_view.dart';

/// Legacy splash gate alias forwarding to the high-performance [SplashView].
class SplashGate extends StatelessWidget {
  const SplashGate({super.key});

  @override
  Widget build(BuildContext context) => const SplashView();
}
