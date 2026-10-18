import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:probashi_guard/frontend/home/home_view.dart';
import 'package:probashi_guard/frontend/notice/controllers/notice_controller.dart';
import 'package:probashi_guard/frontend/notice/models/notice_model.dart';
import 'package:probashi_guard/frontend/notice/notice_view.dart';
import 'package:probashi_guard/frontend/notice/repository/notice_repository.dart';

class _FakeNoticeRepository extends NoticeRepository {
  final List<NoticeModel> fakeNotices;
  const _FakeNoticeRepository(this.fakeNotices);

  @override
  Future<List<NoticeModel>> getNotices({int? limit}) async {
    if (limit != null) {
      return fakeNotices.take(limit).toList();
    }
    return fakeNotices;
  }
}

void main() {
  final testNotices = [
    NoticeModel(
      id: '1',
      title: 'Hotline launched for migrant workers',
      description: 'Wage Earners Welfare Board launched a toll-free hotline.',
      imageUrl: 'https://example.com/image1.jpg',
      sourceUrl: 'https://www.tbsnews.net/bangladesh/migration/hotline-490534',
      createdAt: DateTime(2026, 10, 18, 12, 0),
    ),
    NoticeModel(
      id: '2',
      title: 'Saudi Arabia extends work permit renewal',
      description: 'Expatriate workers will be allowed to complete renewal.',
      imageUrl: null, // Test null image handling
      sourceUrl: 'https://www.tbsnews.net/bangladesh/migration/saudi-deadline',
      createdAt: DateTime(2026, 10, 18, 11, 0),
    ),
    NoticeModel(
      id: '3',
      title: 'Laos suspends new work permits',
      description: null, // Test null description handling
      imageUrl: 'https://example.com/image3.jpg',
      sourceUrl: 'https://en.prothomalo.com/bangladesh/laos-work-permits',
      createdAt: DateTime(2026, 10, 18, 10, 0),
    ),
    NoticeModel(
      id: '4',
      title: 'Fourth older notice',
      description: 'This is the fourth item.',
      imageUrl: null,
      sourceUrl: 'https://thefinancialexpress.com.bd/home/notice-4',
      createdAt: DateTime(2026, 10, 18, 9, 0),
    ),
  ];

  group('NoticeModel tests', () {
    test('NoticeModel parses from map correctly and extracts sourceName', () {
      final model = NoticeModel.fromMap({
        'id': 'abc-123',
        'title': 'Test Headline',
        'description': 'Test Description',
        'image_url': 'https://example.com/photo.jpg',
        'source_url': 'https://www.tbsnews.net/article/123',
        'created_at': '2026-10-18T10:00:00.000Z',
      });

      expect(model.id, 'abc-123');
      expect(model.title, 'Test Headline');
      expect(model.description, 'Test Description');
      expect(model.imageUrl, 'https://example.com/photo.jpg');
      expect(model.sourceUrl, 'https://www.tbsnews.net/article/123');
      expect(model.sourceName, 'tbsnews.net');
      expect(model.hasImage, isTrue);
    });

    test('NoticeModel handles missing image, description, and www prefix gracefully', () {
      final model = NoticeModel.fromMap({
        'id': 'abc-456',
        'title': 'No Image Headline',
        'source_url': 'https://en.prothomalo.com/article/456',
      });

      expect(model.title, 'No Image Headline');
      expect(model.description, isNull);
      expect(model.imageUrl, isNull);
      expect(model.hasImage, isFalse);
      expect(model.sourceName, 'en.prothomalo.com');
    });
  });

  group('NoticeController tests', () {
    test('Controller loads notices and populates latest 3 items', () async {
      final controller = NoticeController.withRepository(
        _FakeNoticeRepository(testNotices),
      );

      await controller.refresh();

      expect(controller.notices.length, 4);
      expect(controller.latest.length, 3);
      expect(controller.latest.first.title, 'Hotline launched for migrant workers');
      expect(controller.latest[2].title, 'Laos suspends new work permits');
    });
  });

  group('NoticeView & HomeView widget tests', () {
    testWidgets('HomeView slider renders dynamic notice headlines and tapping triggers onNavigateToNotice', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var noticeNavTriggered = false;

      final testRepo = _FakeNoticeRepository(testNotices);
      final testCtrl = NoticeController.withRepository(testRepo);
      await testCtrl.refresh();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeView(
              noticeController: testCtrl,
              onNavigateToNotice: () {
                noticeNavTriggered = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Notice Board section is present
      expect(find.text('Notice Board'), findsOneWidget);
      expect(find.text('All Notices'), findsOneWidget);

      // Verify dynamic headline from testNotices is present in the slider
      expect(find.text('Hotline launched for migrant workers'), findsOneWidget);

      // Tap on dynamic notice slide and verify it triggers navigation to Notice tab
      await tester.tap(find.text('Hotline launched for migrant workers'));
      await tester.pumpAndSettle();
      expect(noticeNavTriggered, isTrue);

      // Reset and verify tapping "All Notices" also triggers navigation
      noticeNavTriggered = false;
      await tester.tap(find.text('All Notices'));
      await tester.pumpAndSettle();
      expect(noticeNavTriggered, isTrue);
    });

    testWidgets('NoticeView renders rich cards with titles and descriptions', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testRepo = _FakeNoticeRepository(testNotices);
      final testCtrl = NoticeController.withRepository(testRepo);
      await testCtrl.refresh();

      await tester.pumpWidget(
        MaterialApp(
          home: NoticeView(controller: testCtrl),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header
      expect(find.text('Official Notices'), findsOneWidget);
      expect(find.text('Latest News'), findsOneWidget);

      // Verify headlines exist
      expect(find.text('Hotline launched for migrant workers'), findsOneWidget);
      expect(find.text('Saudi Arabia extends work permit renewal'), findsOneWidget);
      expect(find.text('Laos suspends new work permits'), findsOneWidget);

      // Verify description
      expect(
        find.text('Wage Earners Welfare Board launched a toll-free hotline.'),
        findsOneWidget,
      );

      // Verify source labels
      expect(find.text('tbsnews.net'), findsAtLeastNWidgets(1));
      expect(find.text('en.prothomalo.com'), findsOneWidget);
    });

    testWidgets('NoticeView view toggle alternates between Compact and Expanded mode', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testRepo = _FakeNoticeRepository(testNotices);
      final testCtrl = NoticeController.withRepository(testRepo);
      await testCtrl.refresh();

      await tester.pumpWidget(
        MaterialApp(
          home: NoticeView(controller: testCtrl),
        ),
      );
      await tester.pumpAndSettle();

      // View toggle buttons are present
      expect(find.text('Compact'), findsOneWidget);
      expect(find.text('Expanded'), findsOneWidget);

      // Tap "Expanded" to switch to expanded banner cards
      await tester.tap(find.text('Expanded'));
      await tester.pumpAndSettle();

      // Verify articles are still rendered properly in expanded view
      expect(find.text('Hotline launched for migrant workers'), findsOneWidget);
      expect(find.text('Official Notices'), findsOneWidget);

      // Tap "Compact" to switch back to compact half-height cards
      await tester.tap(find.text('Compact'));
      await tester.pumpAndSettle();

      expect(find.text('Hotline launched for migrant workers'), findsOneWidget);
    });

    testWidgets('Notice cards do not display any date strings', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testRepo = _FakeNoticeRepository(testNotices);
      final testCtrl = NoticeController.withRepository(testRepo);
      await testCtrl.refresh();

      await tester.pumpWidget(
        MaterialApp(
          home: NoticeView(controller: testCtrl),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no date format like '18 Oct 2026' or 'Oct 2026' is displayed
      expect(find.textContaining('18 Oct 2026'), findsNothing);
      expect(find.textContaining('Oct 2026'), findsNothing);

      // Also check Expanded mode
      await tester.tap(find.text('Expanded'));
      await tester.pumpAndSettle();
      expect(find.textContaining('18 Oct 2026'), findsNothing);
      expect(find.textContaining('Oct 2026'), findsNothing);
    });
  });
}
