import '../core/utils/json_utils.dart';

enum CommandStatus {
  pending,
  sent,
  success,
  failed,
  timeout;

  static CommandStatus fromApi(dynamic value) {
    switch (value?.toString().toLowerCase()) {
      case 'pending':
        return CommandStatus.pending;
      case 'sent':
        return CommandStatus.sent;
      case 'success':
        return CommandStatus.success;
      case 'failed':
        return CommandStatus.failed;
      case 'timeout':
        return CommandStatus.timeout;
      default:
        return CommandStatus.pending;
    }
  }

  String get label {
    switch (this) {
      case CommandStatus.pending:
        return 'Menunggu';
      case CommandStatus.sent:
        return 'Dikirim';
      case CommandStatus.success:
        return 'Berhasil';
      case CommandStatus.failed:
        return 'Gagal';
      case CommandStatus.timeout:
        return 'Timeout';
    }
  }

  bool get isFinal =>
      this == CommandStatus.success ||
      this == CommandStatus.failed ||
      this == CommandStatus.timeout;
}

class Command {
  const Command({
    required this.id,
    required this.commandId,
    required this.deviceId,
    required this.action,
    required this.payload,
    required this.status,
    required this.origin,
    this.issuedBy,
    this.issuedAt,
    this.sentAt,
    this.ackedAt,
    this.ackMessage = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String commandId;
  final String deviceId;
  final String action;
  final Map<String, dynamic> payload;
  final CommandStatus status;
  final String origin;
  final String? issuedBy;
  final DateTime? issuedAt;
  final DateTime? sentAt;
  final DateTime? ackedAt;
  final String ackMessage;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool? get pumpState {
    final state = payload['state'];
    return state is bool ? state : null;
  }

  int? get duration {
    return parseInt(payload['duration']);
  }

  factory Command.fromJson(Map<String, dynamic> json) {
    return Command(
      id: json['id']?.toString() ?? '',
      commandId: json['command_id']?.toString() ?? '',
      deviceId: json['device_id']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      payload: parseMap(json['payload']),
      status: CommandStatus.fromApi(json['status']),
      origin: json['origin']?.toString() ?? '',
      issuedBy: json['issued_by']?.toString(),
      issuedAt: parseDateTime(json['issued_at']),
      sentAt: parseDateTime(json['sent_at']),
      ackedAt: parseDateTime(json['acked_at']),
      ackMessage: json['ack_message']?.toString() ?? '',
      createdAt: parseDateTime(json['created_at']),
      updatedAt: parseDateTime(json['updated_at']),
    );
  }
}
