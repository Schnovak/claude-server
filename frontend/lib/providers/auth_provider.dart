import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user.dart';
import '../services/api_client.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = true;

  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  User? get user => _user;
  String? get token => _token;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isLoading => _isLoading;

  AuthProvider() {
    _loadStoredToken();
  }

  Future<void> _loadStoredToken() async {
    try {
      final storedToken = await _storage.read(key: _tokenKey);
      if (storedToken != null) {
        _token = storedToken;
        apiClient.setToken(_token);
        _user = await apiClient.getCurrentUser();
      }
    } catch (e) {
      await _storage.delete(key: _tokenKey);
      _token = null;
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    final authToken = await apiClient.login(email, password);
    _token = authToken.accessToken;
    _user = authToken.user;
    apiClient.setToken(_token);
    await _storage.write(key: _tokenKey, value: _token);
    notifyListeners();
  }

  Future<void> register(String email, String password, String displayName) async {
    final authToken = await apiClient.register(email, password, displayName);
    _token = authToken.accessToken;
    _user = authToken.user;
    apiClient.setToken(_token);
    await _storage.write(key: _tokenKey, value: _token);
    notifyListeners();
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    _token = null;
    _user = null;
    apiClient.setToken(null);
    notifyListeners();
  }
}
