import 'dart:async';
import 'package:flutter/material.dart';
import '../auth/auth_session.dart';
import '../auth/login_view.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  static const Color _backgroundColor = Color(0xFFF6F5F0);
  static const Color _ink = Color(0xFF040303);
  static const Color _royalBlue = Color(0xFF1A4B9C);
  static const String _logoAsset = 'assets/images/1000021944.png';

  static const Duration _animationDuration = Duration(milliseconds: 2000);
  static const Duration _routeDelay = Duration(milliseconds: 2500);

  late final AnimationController _controller;

  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _nameOpacity;
  late final Animation<Offset> _nameOffset;
  late final Animation<double> _sloganOpacity;
  late final Animation<Offset> _sloganOffset;

  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: _animationDuration);

    // Staggered waterfall: each element starts as the one before it is still
    // finishing, so the sequence reads as one motion rather than three.
    CurvedAnimation stage(double begin, double end, Curve curve) =>
        CurvedAnimation(
          parent: _controller,
          curve: Interval(begin, end, curve: curve),
        );

    final logo = stage(0.0, 0.4, Curves.easeOutCubic);
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(logo);
    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(logo);

    final name = stage(0.3, 0.7, Curves.easeOutCubic);
    _nameOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(name);
    _nameOffset = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(name);

    final slogan = stage(0.6, 1.0, Curves.easeOutCubic);
    _sloganOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(slogan);
    _sloganOffset = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(slogan);

    _controller.forward();

    _navigationTimer = Timer(_routeDelay, _goNext);
  }

  /// Someone already logged in on this phone goes straight to the app.
  void _goNext() {
    if (!mounted) return;
    if (hasSignedInAccount()) {
      goToApp(context, fade: true);
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, _, _) => const LoginView(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _logoOpacity,
              child: ScaleTransition(
                scale: _logoScale,
                child: Image.asset(_logoAsset, height: 120, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 16),
            FadeTransition(
              opacity: _nameOpacity,
              child: SlideTransition(
                position: _nameOffset,
                child: const Text(
                  'PROBASHI GUARD',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _royalBlue,
                    fontFamily: 'serif',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _sloganOpacity,
              child: SlideTransition(
                position: _sloganOffset,
                child: Text(
                  'VERIFY • PROTECT • SEND',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ink.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
