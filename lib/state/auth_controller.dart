import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../core/storage/secure_token_store.dart';
import '../data/auth_repository.dart';
import '../models/user.dart';
import '../services/fcm_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthController extends ChangeNotifier {
  AuthController({
    required this._authRepository,
    required this._tokenStore,
    required this._fcmService,
  });

  final AuthRepository _authRepository;
  final SecureTokenStore _tokenStore;
  final FcmService _fcmService;

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  bool _isLoading = false;
  String? _errorMessage;
  bool _bootstrapped = false;

  AuthStatus get status => _status;

  User? get user => _user;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _status == AuthStatus.authenticated;

  bool get canOperate => _user?.role.canOperate ?? false;

  bool get canResolve => _user?.role.canResolve ?? false;

  bool get canManageDevices => _user?.role.canManageDevices ?? false;

  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final tokens = await _tokenStore.readTokens();
    if (tokens == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    final cachedUser = await _authRepository.readStoredUser();

    try {
      final user = await _authRepository.me();
      _user = user;
      _status = AuthStatus.authenticated;
      _errorMessage = null;
    } on ApiException catch (error) {
      if (error.isUnauthorized || error.isForbidden) {
        await _tokenStore.clear();
        _user = null;
        _status = AuthStatus.unauthenticated;
        _errorMessage = error.message;
      } else if (cachedUser != null) {
        _user = cachedUser;
        _status = AuthStatus.authenticated;
        _errorMessage =
            'Tidak dapat memverifikasi sesi. Data mungkin tidak terbaru.';
      } else {
        _user = null;
        _status = AuthStatus.unauthenticated;
        _errorMessage = error.message;
      }
    } catch (_) {
      if (cachedUser != null) {
        _user = cachedUser;
        _status = AuthStatus.authenticated;
        _errorMessage =
            'Tidak dapat memverifikasi sesi. Data mungkin tidak terbaru.';
      } else {
        _user = null;
        _status = AuthStatus.unauthenticated;
        _errorMessage = 'Tidak dapat memulihkan sesi.';
      }
    }

    notifyListeners();
    if (_status == AuthStatus.authenticated) {
      unawaited(_fcmService.syncToken());
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final session = await _authRepository.login(
        email: email,
        password: password,
      );

      _user = session.user;
      _status = AuthStatus.authenticated;
      _errorMessage = null;
      notifyListeners();

      await _fcmService.syncToken();
      return true;
    } on ApiException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _errorMessage = 'Tidak dapat masuk. Periksa koneksi dan coba lagi.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    if (_isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _fcmService.unregisterToken();
    } catch (_) {
      // Token removal is best effort.
    }

    try {
      await _authRepository.logout();
    } catch (_) {
      // The local session must still be cleared.
    } finally {
      await _tokenStore.clear();
      _user = null;
      _status = AuthStatus.unauthenticated;
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resetSessionForServerChange() async {
    try {
      await _fcmService.unregisterToken();
    } catch (_) {
      // Token removal is best effort when switching servers.
    }
    await _tokenStore.clear();
    _user = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  void handleSessionExpired() {
    if (_status == AuthStatus.unauthenticated) return;

    _user = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = 'Sesi berakhir. Silakan masuk kembali.';
    unawaited(_tokenStore.clear());
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }
}
