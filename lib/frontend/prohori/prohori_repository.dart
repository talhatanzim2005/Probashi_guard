import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/backend_config.dart';

/// Why Prohori could not answer. The screen shows the matching message in the
/// app language; [serverMessage] is the backend's own words, when it sent any.
enum ProhoriProblem { unavailable, unreachable, timeout, busy, signIn, failed }

class ProhoriException implements Exception {
  final ProhoriProblem problem;
  final String? serverMessage;

  const ProhoriException(this.problem, {this.serverMessage});

  @override
  String toString() => serverMessage ?? problem.name;
}

/// Asks backend_service's POST /api/chat, which finds the matching FAQ answers
/// and has the language model phrase the reply. The app never talks to the
/// model itself, so no key lives on the phone.
class ProhoriRepository {
  /// The model can be slow on a free tier, so this is generous; it only has to
  /// beat a dead connection.
  static const askTimeout = Duration(seconds: 60);

  /// A question longer than this is cut by the screen before it is sent.
  static const maxQuestionLength = 1000;

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  ProhoriRepository({
    String? baseUrl,
    http.Client? client,
    this.timeout = askTimeout,
  }) : baseUrl = baseUrl ?? BackendConfig.baseUrl,
       _client = client ?? http.Client();

  String? get _accessToken {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// [language] is 'en' or 'bn'; the reply comes back in it.
  Future<String> ask(String message, {required String language}) async {
    final token = _accessToken;
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'message': message, 'language': language}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ProhoriException(ProhoriProblem.timeout);
    } catch (e) {
      debugPrint('[ProhoriRepository] Network error: $e');
      throw const ProhoriException(ProhoriProblem.unreachable);
    }

    // UTF-8 explicitly: Bangla would be garbled if a proxy dropped the charset.
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (response.statusCode == 200) {
      final reply = (body?['reply'] ?? body?['response'])?.toString().trim();
      if (reply != null && reply.isNotEmpty) return reply;
      throw const ProhoriException(ProhoriProblem.failed);
    }
    switch (response.statusCode) {
      case 401:
        throw const ProhoriException(ProhoriProblem.signIn);
      // The endpoint is not deployed yet, or its model is switched off.
      case 404:
      case 501:
      case 503:
        throw const ProhoriException(ProhoriProblem.unavailable);
      case 504:
        throw const ProhoriException(ProhoriProblem.timeout);
      // The free models answer 429 whenever they are busy.
      case 429:
        throw const ProhoriException(ProhoriProblem.busy);
      default:
        throw ProhoriException(
          ProhoriProblem.failed,
          serverMessage: body?['error']?.toString(),
        );
    }
  }
}
