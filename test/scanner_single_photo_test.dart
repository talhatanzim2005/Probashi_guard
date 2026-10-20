// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:probashi_guard/frontend/documents/document_scan_view.dart';
import 'package:probashi_guard/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A 1x1 PNG: a real image, so the thumbnail decodes without an error.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Records how the gallery was opened, and hands back one image per pick.
class _FakePicker extends ImagePickerPlatform {
  int singleCalls = 0;
  int multiCalls = 0;
  ImageSource? lastSource;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    singleCalls++;
    lastSource = source;
    return XFile.fromData(_png, name: 'photo$singleCalls.png', mimeType: 'image/png');
  }

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    multiCalls++;
    return [XFile.fromData(_png, name: 'a.png'), XFile.fromData(_png, name: 'b.png')];
  }
}

/// A camera the person has not allowed (yet): every start-up is refused, and
/// each attempt is counted, so a test can see when the app asked.
class _DeniedCamera extends CameraPlatform {
  int asks = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    asks++;
    throw CameraException('CameraAccessDenied', 'denied');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openScanner(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProbashiGuardApp(home: DocumentScanView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('one photo at a time', () {
    late _FakePicker picker;
    late ImagePickerPlatform original;

    setUp(() {
      original = ImagePickerPlatform.instance;
      picker = _FakePicker();
      ImagePickerPlatform.instance = picker;
    });
    tearDown(() => ImagePickerPlatform.instance = original);

    testWidgets('the helper text asks for a single photo', (tester) async {
      await openScanner(tester);

      expect(
        find.text('Photograph the document or pick a photo, then tap Check.'),
        findsOneWidget,
      );
      expect(find.textContaining('PDF'), findsNothing);
    });

    testWidgets('Photos opens a single-image picker, never a multi-select', (tester) async {
      await openScanner(tester);

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(picker.singleCalls, 1);
      expect(picker.lastSource, ImageSource.gallery);
      expect(picker.multiCalls, 0);
      expect(find.text('Check document'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('picking again replaces the photo instead of adding a second', (tester) async {
      await openScanner(tester);

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(picker.singleCalls, 2);
      expect(find.byType(Image), findsOneWidget, reason: 'still one photo');
      expect(find.text('Check document'), findsOneWidget);
    });

    testWidgets('removing the photo brings the helper text back', (tester) async {
      await openScanner(tester);
      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Check document'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(find.text('Check document'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(
        find.text('Photograph the document or pick a photo, then tap Check.'),
        findsOneWidget,
      );
    });

    testWidgets('a waiting photo fits a small phone with large text', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const ProbashiGuardApp(home: DocumentScanView()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // An overflow would have been thrown as a test failure by now.
      expect(find.text('Check document'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dock has no PDF or Vault button, and Photos and Scan are spread evenly',
        (tester) async {
      await openScanner(tester);

      expect(find.text('PDF'), findsNothing);
      expect(find.text('Vault'), findsNothing);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
      expect(find.byIcon(Icons.folder_shared_outlined), findsNothing);

      // spaceEvenly: the gap before Photos, between the two buttons and after
      // Scan are all the same. The dock pads 16dp on each side of an 800dp
      // screen. Each button is measured as a whole (circle and label), which
      // also keeps the check true for any font.
      Rect slot(Finder label) => tester.getRect(
            find.ancestor(of: label, matching: find.byType(Column)).first,
          );
      final photos = slot(find.text('Photos'));
      final scan = slot(find.text('Scan'));
      final before = photos.left - 16;
      final between = scan.left - photos.right;
      final after = (800 - 16) - scan.right;
      expect(between, closeTo(before, 1));
      expect(after, closeTo(before, 1));
      expect(before, greaterThan(100), reason: 'spread across the width, not clumped');
    });
  });

  group('camera permission', () {
    late CameraPlatform original;

    setUp(() => original = CameraPlatform.instance);
    tearDown(() => CameraPlatform.instance = original);

    testWidgets('is asked for as soon as the scanner opens, and again on a tap',
        (tester) async {
      final camera = _DeniedCamera();
      CameraPlatform.instance = camera;
      await openScanner(tester);

      expect(camera.asks, 1, reason: 'asked on load, without any tap');
      expect(find.text('Try again'), findsOneWidget);

      // The shutter is not dead while the camera is off: it asks again.
      await tester.tap(find.byIcon(Icons.document_scanner_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(camera.asks, 2);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(camera.asks, 3);
    });
  });
}
