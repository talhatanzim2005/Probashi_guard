import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:probashi_guard/frontend/documents/document_detail_view.dart';
import 'package:probashi_guard/frontend/documents/models/document_analysis.dart';
import 'package:probashi_guard/frontend/documents/repository/document_analysis_repository.dart';
import 'package:probashi_guard/frontend/documents/widgets/tip_shoi_warning_banner.dart';

Map<String, dynamic> _sampleResponse({required bool tipShoi}) => {
      'analysis': {
        'document_type': 'Employment contract',
        'is_legible': true,
        'salary': {
          'amount': 800,
          'currency': 'SAR',
          'period': 'monthly',
          'monthly_amount': 800,
          'monthly_sar_equivalent': 800,
          'risk': 'high',
          'explanation': 'Below SAR 1,000',
        },
        'fees': {'items': [], 'risk': 'low', 'explanation': ''},
        'duration': {'text': '2 years', 'months': 24},
        'cancellation': {'text': '', 'risk': 'unknown', 'explanation': ''},
        'tip_shoi_detected': tipShoi,
        'tip_shoi_findings': tipShoi
            ? [
                {
                  'type': 'blank_space_before_signature',
                  'location': 'Page bottom',
                  'explanation': 'Blank lines above the thumbprint box',
                }
              ]
            : [],
        'verdict': tipShoi ? 'DO_NOT_SIGN' : 'PROCEED_WITH_CAUTION',
        'summary_3_lines': ['Line one', 'Line two', 'Line three'],
        'translation_segments': [
          {'original': 'Monthly salary: SAR 800', 'translated': 'মাসিক বেতন: ৮০০ রিয়াল'},
          {'original': '[BLANK]', 'translated': 'খালি জায়গা'},
        ],
        'full_translation': 'মাসিক বেতন: ৮০০ রিয়াল',
      },
      'document_id': 'doc-123',
      'saved': true,
    };

void main() {
  group('DocumentAnalysisRepository', () {
    test('posts base64 image and language to the backend and parses the result', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        // Bytes without a charset: the repository must still decode Bangla as UTF-8.
        return http.Response.bytes(utf8.encode(jsonEncode(_sampleResponse(tipShoi: true))), 200);
      });
      final repo = DocumentAnalysisRepository(baseUrl: 'http://backend.test', client: client);

      final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]);
      final result = await repo.analyze(imageBytes: bytes, language: DocumentLanguage.bangla);

      expect(captured.url.toString(), 'http://backend.test/api/documents/scan');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['language'], 'bn');
      expect(body['imageBase64'], base64Encode(bytes));

      expect(result.saved, isTrue);
      expect(result.documentId, 'doc-123');
      expect(result.analysis.tipShoiDetected, isTrue);
      expect(result.analysis.verdict, SigningVerdict.doNotSign);
      expect(result.analysis.salary.risk, RiskLevel.high);
      expect(result.analysis.summary3Lines, hasLength(3));
      expect(result.analysis.tipShoiFindings.single.location, 'Page bottom');
      expect(result.analysis.translationSegments, hasLength(2));
      expect(result.analysis.translationSegments[1].isBlank, isTrue);
    });

    test('sends on-device passport fields, not an image, to /api/documents/mrz', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'analysis': {
              'document_category': 'PASSPORT',
              'source_engine': 'On-device MRZ',
              'identity': {'document_kind': 'passport', 'document_number': 'A01234567'},
              'verdict': 'SAFE_TO_SIGN',
            },
            'document_id': 'doc-9',
            'saved': true,
          })),
          200,
        );
      });
      final repo = DocumentAnalysisRepository(baseUrl: 'http://backend.test', client: client);

      final result = await repo.saveMrzScan(
        mrz: PassportMrz(
          documentNumber: 'A01234567',
          givenNames: 'MOHAMMAD RAHIM',
          surnames: 'UDDIN',
          nationalityCountryCode: 'BGD',
          issuingCountryCode: 'BGD',
          expiryDate: DateTime(2031, 5, 1),
        ),
        language: DocumentLanguage.english,
      );

      expect(captured.url.toString(), 'http://backend.test/api/documents/mrz');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('imageBase64'), isFalse);
      expect(body['language'], 'en');
      expect(body['mrz'], {
        'document_number': 'A01234567',
        'given_names': 'MOHAMMAD RAHIM',
        'surnames': 'UDDIN',
        'nationality_country_code': 'BGD',
        'issuing_country_code': 'BGD',
        'expiry_date': '2031-05-01',
      });
      expect(result.analysis.category, DocumentCategory.passport);
      expect(result.analysis.sourceEngine, onDeviceMrzEngine);
    });

    test('surfaces the server error message', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'error': 'Document scanner is not configured on the server.'}), 503),
      );
      final repo = DocumentAnalysisRepository(baseUrl: 'http://backend.test', client: client);

      expect(
        () => repo.analyze(imageBytes: Uint8List(4), language: DocumentLanguage.english),
        throwsA(isA<DocumentAnalysisException>()
            .having((e) => e.message, 'message', 'Document scanner is not configured on the server.')
            .having((e) => e.retryable, 'retryable', isTrue)),
      );
    });

    test('a request that outlives the timeout fails with a retryable message', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return http.Response('{}', 200);
      });
      final repo = DocumentAnalysisRepository(
        baseUrl: 'http://backend.test',
        client: client,
        timeout: const Duration(milliseconds: 20),
      );

      expect(
        () => repo.analyze(imageBytes: Uint8List(4), language: DocumentLanguage.english),
        throwsA(isA<DocumentAnalysisException>()
            .having((e) => e.message, 'message', contains('took more than'))
            .having((e) => e.retryable, 'retryable', isTrue)),
      );
    });

    test('an unreachable backend names the URL it tried', () async {
      final client = MockClient((_) async => throw http.ClientException('Connection refused'));
      final repo = DocumentAnalysisRepository(baseUrl: 'http://10.0.2.2:3000', client: client);

      expect(
        () => repo.analyze(imageBytes: Uint8List(4), language: DocumentLanguage.bangla),
        throwsA(isA<DocumentAnalysisException>()
            .having((e) => e.message, 'message', contains('http://10.0.2.2:3000'))
            .having((e) => e.retryable, 'retryable', isTrue)),
      );
    });

    test('a proxy 413 without a JSON body still explains the problem', () async {
      final client = MockClient((_) async => http.Response('<html>Request Entity Too Large</html>', 413));
      final repo = DocumentAnalysisRepository(baseUrl: 'http://backend.test', client: client);

      expect(
        () => repo.analyze(imageBytes: Uint8List(4), language: DocumentLanguage.english),
        throwsA(isA<DocumentAnalysisException>()
            .having((e) => e.message, 'message', contains('too large'))
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
    });

    test('rejects a photo over 8 MB without uploading it', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      final repo = DocumentAnalysisRepository(baseUrl: 'http://backend.test', client: client);

      await expectLater(
        repo.analyze(
          imageBytes: Uint8List(DocumentAnalysisRepository.maxImageBytes + 1),
          language: DocumentLanguage.english,
        ),
        throwsA(isA<DocumentAnalysisException>()),
      );
      expect(requests, 0);
    });
  });

  test('parses passport identity fields and the source engine', () {
    final analysis = DocumentAnalysis.fromMap({
      'document_category': 'PASSPORT',
      'document_type': 'Bangladesh passport',
      'source_engine': 'On-device MRZ',
      'identity': {
        'document_kind': 'passport',
        'full_name': 'MOHAMMAD RAHIM UDDIN',
        'document_number': 'A01234567',
        'date_of_expiry': '2031-05-01',
        'visa_type': null,
      },
      'authenticity': {'signature_present': true, 'stamp_present': null, 'notes': ''},
      'verdict': 'SAFE_TO_SIGN',
    });
    expect(analysis.category, DocumentCategory.passport);
    expect(analysis.sourceEngine, onDeviceMrzEngine);
    expect(analysis.identity.presentFields.map((f) => f.$1), ['Name', 'Document no.', 'Expires']);
    expect(analysis.authenticity.signaturePresent, isTrue);
    expect(analysis.authenticity.stampPresent, isNull);
  });

  test('rows saved before the rename still parse SIGN_WITH_CAUTION as caution', () {
    final analysis = DocumentAnalysis.fromMap({'verdict': 'SIGN_WITH_CAUTION'});
    expect(analysis.verdict, SigningVerdict.proceedWithCaution);
    expect(analysis.category, DocumentCategory.contract);
  });

  test('SavedDocument parses a saved_documents row', () {
    final row = {
      ...(_sampleResponse(tipShoi: true)['analysis'] as Map<String, dynamic>),
      'id': 'row-1',
      'created_at': '2026-10-17T10:00:00+00:00',
      'language': 'zh',
    };
    final doc = SavedDocument.fromRow(row);
    expect(doc.id, 'row-1');
    expect(doc.language, DocumentLanguage.chinese);
    expect(doc.createdAt.toUtc(), DateTime.utc(2026, 10, 17, 10));
    expect(doc.analysis.verdict, SigningVerdict.doNotSign);
    expect(doc.analysis.verdict.label(doc.language), '请勿签署');
  });

  testWidgets('Detail view shows banner, summary, terms and side-by-side translation', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final analysis = DocumentAnalysis.fromMap(
      _sampleResponse(tipShoi: true)['analysis'] as Map<String, dynamic>,
    );
    await tester.pumpWidget(MaterialApp(
      home: DocumentDetailView(analysis: analysis, language: DocumentLanguage.bangla),
    ));

    expect(find.text(TipShoiWarningBanner.warning), findsOneWidget);
    expect(find.text('সই করবেন না'), findsOneWidget);
    expect(find.text('1. Line one'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('High risk'), findsOneWidget);
    // High-risk terms open expanded with their explanation; others show a one-line preview.
    expect(find.text('Below SAR 1,000'), findsOneWidget);
    expect(find.text('2 years'), findsOneWidget);
    expect(find.text('Identity details'), findsNothing);

    await tester.tap(find.text('Duration'));
    await tester.pumpAndSettle();
    expect(find.text('2 years'), findsOneWidget);

    await tester.tap(find.text('Translation'));
    await tester.pumpAndSettle();
    expect(find.text('Monthly salary: SAR 800'), findsOneWidget);
    expect(find.text('মাসিক বেতন: ৮০০ রিয়াল'), findsOneWidget);
    expect(find.text('খালি জায়গা'), findsOneWidget);
  });

  testWidgets('Detail view shows identity details for a passport', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final analysis = DocumentAnalysis.fromMap({
      'document_category': 'PASSPORT',
      'document_type': 'Passport',
      'source_engine': 'On-device MRZ',
      'identity': {'document_kind': 'passport', 'full_name': 'MOHAMMAD RAHIM UDDIN', 'document_number': 'A01234567'},
      'authenticity': {'notes': 'The machine-readable zone (MRZ) was read and check-digit verified on the phone.'},
      'verdict': 'SAFE_TO_SIGN',
      'summary_3_lines': ['Passport', 'Valid', 'Keep it safe'],
    });
    await tester.pumpWidget(MaterialApp(
      home: DocumentDetailView(analysis: analysis, language: DocumentLanguage.english),
    ));

    expect(find.text('Identity details'), findsOneWidget);
    expect(find.text('A01234567'), findsOneWidget);
    expect(find.text('Check digits verified on this phone'), findsOneWidget);
    expect(find.text('Signature'), findsNothing); // an MRZ read says nothing about signatures
    expect(find.text('Read by On-device MRZ'), findsOneWidget);
    expect(find.text('Salary'), findsNothing); // no contract terms on a passport
  });

  testWidgets('Detail view shows the stamp Gemini found on a visa', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final analysis = DocumentAnalysis.fromMap({
      'document_category': 'VISA',
      'document_type': 'Work visa',
      'source_engine': 'Gemini',
      'identity': {'document_kind': 'work_visa', 'full_name': 'MOHAMMAD RAHIM UDDIN', 'visa_type': 'Work'},
      'authenticity': {
        'signature_present': false,
        'stamp_present': true,
        'stamp_kind': 'consular_stamp',
        'stamp_text': 'سفارة المملكة العربية السعودية - دكا',
        'notes': '',
      },
      'verdict': 'SAFE_TO_SIGN',
    });
    await tester.pumpWidget(MaterialApp(
      home: DocumentDetailView(analysis: analysis, language: DocumentLanguage.english),
    ));

    expect(find.text('Visa details'), findsOneWidget);
    expect(find.text('Embassy / consulate stamp'), findsOneWidget);
    expect(find.text('سفارة المملكة العربية السعودية - دكا'), findsOneWidget);
    expect(find.text('Not found'), findsOneWidget); // no signature
  });

  testWidgets('Tip Shoi banner always shows the Bangla warning, translated for other languages', (tester) async {
    Future<void> pumpBanner(DocumentLanguage language) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TipShoiWarningBanner(
              language: language,
              findings: const [
                TipShoiFinding(
                  type: 'blank_promissory_note',
                  location: 'Page 2',
                  explanation: 'Blank Sanad Li Amr',
                ),
              ],
            ),
          ),
        ));

    await pumpBanner(DocumentLanguage.bangla);
    expect(
      find.text('সতর্কতা: খালি কাগজে বা অর্থ দাবির দলিলে কোনো অবস্থাতেই টিপ সই বা স্বাক্ষর দিবেন না!'),
      findsOneWidget,
    );
    expect(find.text('Page 2: Blank Sanad Li Amr'), findsOneWidget);
    expect(find.textContaining('Never give your thumbprint'), findsNothing);

    await pumpBanner(DocumentLanguage.english);
    expect(find.text(TipShoiWarningBanner.warning), findsOneWidget);
    expect(find.textContaining('Never give your thumbprint'), findsOneWidget);
  });
}
