import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document_analysis.dart';

class DocumentAnalysisException implements Exception {
  final String message;

  /// True when sending the same photo again may work (timeouts, network, busy server).
  final bool retryable;

  const DocumentAnalysisException(this.message, {this.retryable = false});

  @override
  String toString() => message;
}

/// Sends scanned documents to backend_service (which holds the Gemini key)
/// and reads the user's vault from Supabase. The app never calls Gemini directly.
class DocumentAnalysisRepository {
  /// The backend answers within 27 s (or explains why not), so this only fires on a dead connection.
  static const analyzeTimeout = Duration(seconds: 30);

  /// Matches the backend's limit on decoded image size, per page.
  static const maxImageBytes = 8 * 1024 * 1024;

  /// Matches the backend's limit on one scan: several pages add up.
  static const maxTotalBytes = 16 * 1024 * 1024;

  /// Matches the backend's page limit for a single scan.
  static const maxPages = 10;

  /// Set when the backend isn't on this machine, e.g. a physical phone on the same Wi-Fi:
  /// `flutter run --dart-define=BACKEND_URL=http://192.168.0.10:3000`
  static const _configuredBaseUrl = String.fromEnvironment('BACKEND_URL');

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  DocumentAnalysisRepository({
    String? baseUrl,
    http.Client? client,
    this.timeout = analyzeTimeout,
  })  : baseUrl = baseUrl ?? _defaultBaseUrl,
        _client = client ?? http.Client();

  static String get _defaultBaseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    try {
      // 10.0.2.2 is the host PC as seen from the Android emulator only.
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:3000';
      }
    } catch (_) {}
    return 'http://localhost:3000';
  }

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// The vault is scoped to the Supabase user, so make sure there is one.
  /// main() signs in anonymously at launch; this covers a launch that was offline.
  Future<Session?> _ensureSession() async {
    final sb = _supabase;
    if (sb == null) return null;
    if (sb.auth.currentSession != null) return sb.auth.currentSession;
    try {
      final response = await sb.auth.signInAnonymously().timeout(const Duration(seconds: 8));
      return response.session;
    } catch (e) {
      debugPrint('[DocumentAnalysisRepository] Anonymous sign-in failed: $e');
      return null;
    }
  }

  /// Contracts, visas and other papers: the pages go to Gemini via the backend.
  /// [files] is one or more page photos, or a single PDF of the whole document.
  ///
  /// Nothing is stored unless [save] is set: the audit comes back first so the
  /// worker can read it and then choose, with [saveAnalysis], whether to keep it.
  Future<DocumentAnalysisResult> analyze({
    required List<Uint8List> files,
    required DocumentLanguage language,
    bool save = false,
  }) async {
    if (files.isEmpty || files.every((f) => f.isEmpty)) {
      throw const DocumentAnalysisException('The photo is empty. Please take it again.');
    }
    if (files.length > maxPages) {
      throw DocumentAnalysisException(
        'Too many pages (more than $maxPages). Please check the document in smaller parts.',
      );
    }
    if (files.any((f) => f.length > maxImageBytes)) {
      throw const DocumentAnalysisException(
        'One of the files is too large (over 8 MB). Please choose a smaller image or PDF.',
      );
    }
    final totalBytes = files.fold<int>(0, (sum, f) => sum + f.length);
    if (totalBytes > maxTotalBytes) {
      throw const DocumentAnalysisException(
        'These pages are too large together (over 16 MB). Please send fewer pages.',
      );
    }
    return _post('/api/documents/scan', {
      'filesBase64': [for (final file in files) base64Encode(file)],
      'language': language.code,
      'save': save,
    });
  }

  /// Passports: only the fields read on the phone are sent, to be checked.
  /// As with [analyze], the result is kept only if [save] is set.
  Future<DocumentAnalysisResult> saveMrzScan({
    required PassportMrz mrz,
    required DocumentLanguage language,
    bool save = false,
  }) {
    return _post('/api/documents/mrz', {
      'mrz': mrz.toJson(),
      'language': language.code,
      'save': save,
    });
  }

  /// Keeps a scan the worker chose to save, after reading it.
  /// Async so a rejected save arrives as a failed future, like every other call.
  Future<DocumentAnalysisResult> saveAnalysis({
    required DocumentAnalysisResult result,
    required DocumentLanguage language,
  }) async {
    if (result.rawAnalysis.isEmpty) {
      throw const DocumentAnalysisException('There is nothing to save. Please scan the document again.');
    }
    return _post('/api/documents/save', {
      'analysis': result.rawAnalysis,
      'language': language.code,
      if (result.imageSha256 != null) 'image_sha256': result.imageSha256,
      if (result.model != null) 'model': result.model,
    });
  }

  Future<DocumentAnalysisResult> _post(String path, Map<String, dynamic> body) async {
    final token = (await _ensureSession())?.accessToken;
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw DocumentAnalysisException(
        'The scan took more than ${timeout.inSeconds} seconds. Check your internet connection and try again.',
        retryable: true,
      );
    } catch (e) {
      debugPrint('[DocumentAnalysisRepository] Network error: $e');
      throw DocumentAnalysisException(
        'Cannot reach the scanner server at $baseUrl. Make sure the backend is running '
        'and this phone can reach it.',
        retryable: true,
      );
    }

    // Decode as UTF-8 explicitly: Bangla/Chinese text would be garbled if a
    // proxy dropped the charset and package:http fell back to Latin-1.
    final decoded = _tryDecode(response.bodyBytes);
    if (response.statusCode != 200) {
      final status = response.statusCode;
      final serverError = decoded?['error']?.toString();
      throw DocumentAnalysisException(
        serverError ??
            (status == 413
                ? 'The photo is too large. Please retake it or choose a smaller image.'
                : 'Document analysis failed ($status).'),
        retryable: status == 429 || status >= 500,
      );
    }
    if (decoded == null) {
      throw const DocumentAnalysisException('Document analysis returned an invalid response.');
    }
    return DocumentAnalysisResult.fromMap(decoded);
  }

  /// The signed-in (or anonymous) user's saved documents, newest first.
  /// Row-level security limits the rows to the current user.
  Future<List<SavedDocument>> fetchSavedDocuments() async {
    final sb = _supabase;
    if (sb == null || await _ensureSession() == null) {
      throw const DocumentAnalysisException('Unable to open your document vault. Please check your connection.');
    }
    try {
      final rows = await sb
          .from('saved_documents')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10));
      return rows.map(SavedDocument.fromRow).toList();
    } catch (e) {
      debugPrint('[DocumentAnalysisRepository] fetchSavedDocuments failed: $e');
      throw const DocumentAnalysisException('Unable to load your saved documents.');
    }
  }

  Map<String, dynamic>? _tryDecode(List<int> bodyBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
