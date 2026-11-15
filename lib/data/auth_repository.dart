import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/storage/secure_token_store.dart';
import '../core/utils/json_utils.dart';
import '../models/token_pair.dart';
import '../models/user.dart';

class AuthSession {
  const AuthSession({required this.tokens, required this.user});

  final TokenPair tokens;
  final User user;
}

class AuthRepository {
  AuthRepository({required this._apiClient, required this._tokenStore});

  final ApiClient _apiClient;
  final SecureTokenStore _tokenStore;

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.postJson(
      '/api/v1/auth/login',
      body: {'email': email, 'password': password},
      authenticated: false,
    );

    final data = parseMap(response['data']);
    final tokens = TokenPair.fromJson(parseMap(data['tokens']));
    final user = User.fromJson(parseMap(data['user']));

    if (tokens.accessToken.isEmpty || tokens.refreshToken.isEmpty) {
      throw const ApiException(
        'Respons login tidak berisi token yang valid.',
        code: 'invalid_login_response',
      );
    }

    await _tokenStore.saveTokens(tokens);
    await _tokenStore.saveUser(user);

    return AuthSession(tokens: tokens, user: user);
  }

  Future<User> me() async {
    final response = await _apiClient.getJson('/api/v1/auth/me');
    final user = User.fromJson(parseMap(response['data']));
    await _tokenStore.saveUser(user);
    return user;
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    await _apiClient.postJson(
      '/api/v1/auth/logout',
      body: {'refresh_token': refreshToken},
    );
  }

  Future<User?> readStoredUser() {
    return _tokenStore.readUser();
  }
}
