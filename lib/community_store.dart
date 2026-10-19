import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CommunityException implements Exception {
  const CommunityException(this.message);
  final String message;
}

class CommunityStore extends ChangeNotifier {
  CommunityStore(this.prefs, {http.Client? client, String? apiUrl})
    : client = client ?? http.Client(),
      apiUrl = apiUrl ?? defaultApiUrl();
  final SharedPreferences prefs;
  final http.Client client;
  final String? apiUrl;
  Map<String, dynamic> state = {};
  bool busy = false;
  bool connected = false;
  String? error;
  String? get token => prefs.getString('community_token');
  bool get signedIn => token != null;
  Map<String, dynamic> get profile =>
      Map<String, dynamic>.from(state['profile'] as Map? ?? {});
  int get postPoints => !signedIn
      ? 0
      : profile['post_points'] as int? ?? prefs.getInt('community_points') ?? 0;
  List<Map<String, dynamic>> list(String key) => (state[key] as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();

  static String? defaultApiUrl() {
    const configured = String.fromEnvironment('CIRCLES_API_URL');
    if (configured.isNotEmpty) return configured.replaceAll(RegExp(r'/$'), '');
    if (kIsWeb && ['localhost', '127.0.0.1', '::1'].contains(Uri.base.host)) {
      return Uri(
        scheme: 'http',
        host: Uri.base.host,
        port: 8090,
      ).toString().replaceAll(RegExp(r'/$'), '');
    }
    return null;
  }

  Future<Map<String, dynamic>> request(
    String method,
    String route, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (apiUrl == null) {
      throw const CommunityException(
        'The community service is not configured.',
      );
    }
    try {
      final req = http.Request(method, Uri.parse('$apiUrl$route'));
      req.headers['Content-Type'] = 'application/json';
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      if (method != 'GET') req.body = jsonEncode(data);
      final response = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 12)),
      ).timeout(const Duration(seconds: 12));
      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        if (response.statusCode == 401 && !route.startsWith('/auth/')) {
          await clearSession();
        }
        throw CommunityException(
          body['error'] as String? ??
              'The community service could not complete this action. Try again.',
        );
      }
      connected = true;
      return body;
    } on CommunityException {
      rethrow;
    } catch (_) {
      throw const CommunityException(
        'The community service is unavailable. Try again.',
      );
    }
  }

  Future<void> load() async {
    if (signedIn) {
      state = await request('GET', '/state');
      await prefs.setInt(
        'community_points',
        profile['post_points'] as int? ?? 0,
      );
    } else {
      await request('GET', '/health');
    }
  }

  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await load();
    } on CommunityException catch (e) {
      error = e.message;
      connected = false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> authenticate({
    required bool register,
    required String handle,
    required String password,
    required String name,
    required String path,
  }) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final response = await request(
        'POST',
        register ? '/auth/register' : '/auth/login',
        {'handle': handle, 'password': password, 'name': name, 'path': path},
      );
      await prefs.remove('community_points');
      state = {};
      await prefs.setString('community_token', response['token'] as String);
      await load();
    } on CommunityException catch (e) {
      error = e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> clearSession() async {
    await prefs.remove('community_token');
    await prefs.remove('community_points');
    state = {};
  }

  Future<void> logout() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await request('POST', '/auth/logout');
    } catch (_) {
      /* Clear this device even when offline. */
    }
    await clearSession();
    busy = false;
    error = null;
    notifyListeners();
  }

  Future<void> act(
    String method,
    String route, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (busy) {
      throw const CommunityException(
        'Please wait for the current action to finish.',
      );
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      await request(method, route, data);
      try {
        await load();
      } on CommunityException {
        error = 'Saved, but refresh failed. Tap Refresh.';
        connected = false;
      }
    } on CommunityException catch (e) {
      error = e.message;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}
