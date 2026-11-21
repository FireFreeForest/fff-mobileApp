import '../core/network/api_client.dart';
import '../core/utils/json_utils.dart';
import '../models/paginated.dart';
import '../models/user.dart';

class UserRepository {
  UserRepository({required this._apiClient});

  final ApiClient _apiClient;

  Future<Paginated<User>> listUsers({
    int page = 1,
    int perPage = 100,
    String? query,
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/users',
      query: {
        'page': '$page',
        'per_page': '$perPage',
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    return Paginated.fromJson(response, User.fromJson);
  }

  Future<User> createUser({
    required String email,
    required String password,
    required String name,
    required UserRole role,
  }) async {
    final response = await _apiClient.postJson(
      '/api/v1/users',
      body: {
        'email': email.trim(),
        'password': password,
        'name': name.trim(),
        'role': role.apiValue,
      },
    );
    return User.fromJson(parseMap(response['data']));
  }

  Future<User> updateUser({
    required String userId,
    String? name,
    UserRole? role,
    bool? isActive,
    String? password,
  }) async {
    final response = await _apiClient.patchJson(
      '/api/v1/users/${Uri.encodeComponent(userId)}',
      body: {
        if (name != null) 'name': name.trim(),
        if (role != null) 'role': role.apiValue,
        if (isActive != null) 'is_active': isActive,
        if (password != null && password.isNotEmpty) 'password': password,
      },
    );
    return User.fromJson(parseMap(response['data']));
  }
}
