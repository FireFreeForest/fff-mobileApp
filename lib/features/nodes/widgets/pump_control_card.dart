import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/command_repository.dart';
import '../../../models/command.dart';
import '../../../shared/widgets/surface_card.dart';

class PumpControlCard extends StatefulWidget {
  const PumpControlCard({
    super.key,
    required this.deviceId,
    required this.pumpOn,
    required this.online,
    required this.canOperate,
    required this.onCommandSettled,
  });

  final String deviceId;
  final bool? pumpOn;
  final bool online;
  final bool canOperate;
  final VoidCallback onCommandSettled;

  @override
  State<PumpControlCard> createState() => _PumpControlCardState();
}

class _PumpControlCardState extends State<PumpControlCard> {
  bool _busy = false;
  Command? _command;
  String? _error;

  Future<void> _send({required bool state}) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _command = null;
    });

    try {
      final command = await context.read<CommandRepository>().issuePump(
        deviceId: widget.deviceId,
        state: state,
      );

      if (!mounted) return;
      setState(() => _command = command);

      if (command.status.isFinal) {
        _finish();
      } else {
        unawaited(_pollCommand(command.commandId));
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Perintah pompa belum dapat dikirim.';
      });
    }
  }

  Future<void> _pollCommand(String commandId) async {
    final repository = context.read<CommandRepository>();

    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      try {
        final command = await repository.getCommand(commandId);
        if (!mounted) return;
        setState(() => _command = command);
        if (command.status.isFinal) {
          _finish();
          return;
        }
      } on ApiException catch (error) {
        if (!mounted) return;
        if (error.isUnauthorized) {
          setState(() => _busy = false);
          return;
        }
      } catch (_) {
        // Keep polling while the command result is not available yet.
      }
    }

    if (mounted) {
      _finish();
    }
  }

  void _finish() {
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onCommandSettled();
  }

  @override
  Widget build(BuildContext context) {
    final pumpOn = widget.pumpOn;
    final pumpLabel = pumpOn == null
        ? 'Belum diketahui'
        : pumpOn
        ? 'Menyala'
        : 'Mati';
    final command = _command;
    final canTurnOn =
        widget.canOperate && widget.online && !_busy && pumpOn != true;
    final canTurnOff =
        widget.canOperate && widget.online && !_busy && pumpOn != false;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pompa air',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontSize: 14),
              ),
              Text(
                pumpLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: pumpOn == true
                      ? AppColors.primary
                      : context.appTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Kontrol manual · pompa menyala 30 detik',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 10, color: context.appTextMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: canTurnOff ? () => _send(state: false) : null,
                  child: const Text('Matikan'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: canTurnOn ? () => _send(state: true) : null,
                  child: const Text('Nyalakan'),
                ),
              ),
            ],
          ),
          if (!widget.canOperate) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Hanya admin dan petugas yang dapat mengontrol pompa.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 10, color: context.appTextMuted),
            ),
          ] else if (!widget.online) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Node offline. Kontrol pompa dinonaktifkan.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 10, color: AppColors.warning),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    command == null
                        ? 'Mengirim perintah...'
                        : 'Perintah ${command.status.label.toLowerCase()}...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: context.appTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (command != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Perintah ${command.status.label}'
              '${command.ackMessage.isEmpty ? '' : ' · ${command.ackMessage}'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: command.status == CommandStatus.success
                    ? AppColors.success
                    : command.status == CommandStatus.failed ||
                          command.status == CommandStatus.timeout
                    ? AppColors.danger
                    : context.appTextSecondary,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 10, color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}
