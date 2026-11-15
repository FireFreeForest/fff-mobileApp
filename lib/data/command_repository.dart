import 'package:uuid/uuid.dart';

import '../core/network/api_client.dart';
import '../core/utils/json_utils.dart';
import '../models/command.dart';
import '../models/paginated.dart';

class CommandRepository {
  CommandRepository({required this._apiClient});

  final ApiClient _apiClient;
  final _uuid = const Uuid();

  Future<Command> issuePump({
    required String deviceId,
    required bool state,
    int duration = 30,
  }) async {
    final response = await _apiClient.postJson(
      '/api/v1/devices/$deviceId/commands',
      body: {
        'action': 'SET_PUMP',
        'payload': {'state': state, 'duration': state ? duration : 0},
      },
      idempotencyKey: _uuid.v4(),
    );
    return Command.fromJson(parseMap(response['data']));
  }

  Future<Command> getCommand(String commandId) async {
    final response = await _apiClient.getJson('/api/v1/commands/$commandId');
    return Command.fromJson(parseMap(response['data']));
  }

  Future<Paginated<Command>> listCommands({
    required String deviceId,
    int page = 1,
    int perPage = 20,
  }) async {
    final response = await _apiClient.getJson(
      '/api/v1/devices/$deviceId/commands',
      query: {'page': '$page', 'per_page': '$perPage'},
    );
    return Paginated.fromJson(response, Command.fromJson);
  }
}
