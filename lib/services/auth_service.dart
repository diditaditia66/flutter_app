// lib/services/auth_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart'; // apiBaseUrl

/// AuthService sederhana dengan:
/// - login/logout
/// - simpan access/refresh token di memori
/// - helper header Authorization
/// - wrapper HTTP GET/POST yang otomatis menyertakan Bearer token
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  String? _accessToken;
  String? _refreshToken;
  String? _username;

  Uri _uri(String pathOrUrl) {
    // Terima absolute URL atau path relatif yang akan di-join ke apiBaseUrl
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return Uri.parse(pathOrUrl);
    }
    final base = apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
    final path = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    return Uri.parse('$base$path');
  }

  // ------------------------------
  // State & token utilities
  // ------------------------------
  Future<bool> isLoggedIn() async {
    return _accessToken != null && _accessToken!.isNotEmpty;
  }

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get username => _username;

  Future<void> setTokens({
    required String accessToken,
    String? refreshToken,
    String? username,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _username = username;
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _username = null;
  }

  /// Header Authorization standar untuk endpoint yang butuh JWT
  Future<Map<String, String>> authHeaders() async {
    final at = _accessToken;
    if (at == null || at.isEmpty) return {};
    return {'Authorization': 'Bearer $at'};
  }

  // ------------------------------
  // Auth flows
  // ------------------------------

  /// Login ke backend /auth/login
  /// Body: {"username": "...", "password": "..."}
  /// Harap backend mengembalikan: access_token, refresh_token, username
  Future<void> login(String username, String password) async {
    final uri = _uri('/auth/login');
    final resp = await http
        .post(uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}))
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      // coba ambil pesan error
      try {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        final msg = m['error']?.toString() ?? m['message']?.toString() ?? resp.body;
        throw Exception('Login gagal: [${resp.statusCode}] $msg');
      } catch (_) {
        throw Exception('Login gagal: HTTP ${resp.statusCode}');
      }
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final access = (data['access_token'] ?? data['accessToken'])?.toString();
    if (access == null || access.isEmpty) {
      throw Exception('Login gagal: access_token tidak ditemukan');
    }
    final refresh = data['refresh_token']?.toString();
    final name = data['username']?.toString();

    await setTokens(accessToken: access, refreshToken: refresh, username: name);
  }

  /// Logout lokal (hapus token di memori).
  /// Jika ingin juga logout server-side (blocklist refresh token), bisa tambahkan
  /// pemanggilan endpoint /auth/logout di sini bila diperlukan.
  Future<void> logout() async {
    // OPTIONAL (server-side):
    // if (_refreshToken != null && _refreshToken!.isNotEmpty) {
    //   try {
    //     await http.post(
    //       _uri('/auth/logout'),
    //       headers: await authHeaders(),
    //       body: jsonEncode({'refresh_token': _refreshToken}),
    //     );
    //   } catch (_) {}
    // }
    await clear();
  }

  // ------------------------------
  // HTTP helpers with auth
  // ------------------------------

  /// GET dengan Authorization (jika ada token)
  Future<http.Response> get(String pathOrUrl, {Map<String, String>? headers}) async {
    final uri = _uri(pathOrUrl);
    final auth = await authHeaders();
    final hdrs = <String, String>{...auth, if (headers != null) ...headers};
    return http.get(uri, headers: hdrs).timeout(const Duration(seconds: 30));
    // NOTE: tambahkan retry jika perlu
  }

  /// POST dengan Authorization (jika ada token)
  /// - Jika [body] Map/String JSON → otomatis kasih Content-Type: application/json
  /// - Jika mau kirim multipart/form-data, gunakan package Dio di screen langsung
  Future<http.Response> post(String pathOrUrl, {Object? body, Map<String, String>? headers}) async {
    final uri = _uri(pathOrUrl);
    final auth = await authHeaders();
    final hdrs = <String, String>{...auth, if (headers != null) ...headers};

    // Jika body berupa Map → JSON-encode. Jika sudah String, pakai apa adanya.
    Object? payload = body;
    if (body is Map<String, dynamic>) {
      payload = jsonEncode(body);
    }

    // Pastikan Content-Type JSON jika payload adalah String JSON
    if (payload is String) {
      hdrs.putIfAbsent('Content-Type', () => 'application/json');
    }

    return http.post(uri, headers: hdrs, body: payload).timeout(const Duration(seconds: 30));
  }
}
