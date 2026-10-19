import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/auth/login_view.dart';
import 'package:probashi_guard/frontend/splash/splash_view.dart';

double _opacityOf(WidgetTester tester, Finder child) {
  final fade = tester.widget<FadeTransition>(
    find.ancestor(of: child, matching: find.byType(FadeTransition)).first,
  );
  return fade.opacity.value;
}

void main() {
  Future<void> pumpSplash(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: SplashView()));

  testWidgets('shows the PG logo, name and slogan on a #F6F5F0 background',
      (tester) async {
    await pumpSplash(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFFF6F5F0));

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName,
        'assets/images/1000021944.png');
    expect(image.height, 120);

    expect(find.text('PROBASHI GUARD'), findsOneWidget);
    expect(find.text('VERIFY • PROTECT • SEND'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();
  });

  testWidgets('the logo, name and slogan appear in a staggered order',
      (tester) async {
    await pumpSplash(tester);

    final logo = find.byType(Image);
    final name = find.text('PROBASHI GUARD');
    final slogan = find.text('VERIFY • PROTECT • SEND');

    // Start: nothing is visible yet.
    expect(_opacityOf(tester, logo), 0.0);
    expect(_opacityOf(tester, name), 0.0);
    expect(_opacityOf(tester, slogan), 0.0);

    // 0.4 of 2s: the logo is in, the name has begun, the slogan has not.
    await tester.pump(const Duration(milliseconds: 800));
    expect(_opacityOf(tester, logo), 1.0);
    expect(_opacityOf(tester, name), greaterThan(0.0));
    expect(_opacityOf(tester, name), lessThan(1.0));
    expect(_opacityOf(tester, slogan), 0.0);

    // 0.7 of 2s: the name is in, the slogan is mid-reveal.
    await tester.pump(const Duration(milliseconds: 600));
    expect(_opacityOf(tester, name), 1.0);
    expect(_opacityOf(tester, slogan), greaterThan(0.0));

    // The full 2s: everything is visible.
    await tester.pump(const Duration(milliseconds: 600));
    expect(_opacityOf(tester, slogan), 1.0);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets('cross-fades into LoginView after 2.5 seconds', (tester) async {
    await pumpSplash(tester);

    await tester.pump(const Duration(milliseconds: 2400));
    expect(find.byType(LoginView), findsNothing);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.byType(LoginView), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('leaving the splash early does not navigate or leak a timer',
      (tester) async {
    await pumpSplash(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    // A leaked timer or controller would throw once it fired.
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(LoginView), findsNothing);
  });
}
