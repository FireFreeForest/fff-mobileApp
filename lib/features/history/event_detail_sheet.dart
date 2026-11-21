import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_format_utils.dart';
import '../../data/event_repository.dart';
import '../../models/device.dart';
import '../../models/event.dart';
import '../../state/auth_controller.dart';

Future<void> showEventDetailSheet(
  BuildContext context, {
  required Event event,
  required Device? device,
  required ValueChanged<Event> onUpdated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return EventDetailSheet(
        event: event,
        device: device,
        onUpdated: onUpdated,
      );
    },
  );
}

class EventDetailSheet extends StatefulWidget {
  const EventDetailSheet({
    super.key,
    required this.event,
    required this.device,
    required this.onUpdated,
  });

  final Event event;
  final Device? device;
  final ValueChanged<Event> onUpdated;

  @override
  State<EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<EventDetailSheet> {
  late Event _event = widget.event;
  bool _busy = false;
  String? _error;
  List<EventTimeline> _timeline = const [];
  bool _timelineLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTimeline();
  }

  Future<void> _loadTimeline() async {
    try {
      final repository = context.read<EventRepository>();
      final detail = await repository.getEvent(widget.event.id);
      final timeline = await repository.listTimeline(
        widget.event.id,
        perPage: 50,
      );
      if (!mounted) return;
      setState(() {
        _event = detail;
        _timeline = timeline.items;
        _timelineLoading = false;
      });
      widget.onUpdated(detail);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _timeline = _event.timelinePreview;
        _timelineLoading = false;
      });
    }
  }

  Future<void> _run(
    Future<Event> Function(EventRepository repository) action,
  ) async {
    if (_busy) return;

    final repository = context.read<EventRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final updated = await action(repository);
      if (!mounted) return;
      setState(() {
        _event = updated;
        _busy = false;
      });
      widget.onUpdated(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status kejadian diperbarui.')),
      );
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
        _error = 'Kejadian belum dapat diperbarui.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final event = _event;
    final severityColor = _severityColor(event.severity);
    final device = event.device ?? widget.device;
    final deviceLabel = device == null
        ? event.deviceCode
        : '${device.deviceId} · ${device.locationLabel}';
    final canAcknowledge =
        auth.canOperate && event.status == EventStatus.active;
    final canResolve = auth.canResolve && event.status != EventStatus.resolved;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        decoration: BoxDecoration(
          color: context.appBackground,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.appBorder,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Detail Kejadian',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  _StatusChip(status: event.status),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: severityColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                          ),
                          child: Icon(
                            _severityIcon(event.severity),
                            size: 18,
                            color: severityColor,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.typeLabel,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${event.severity.label} · ${event.source}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 10,
                                      color: severityColor,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (event.message.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        event.message,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(
                  children: [
                    _InfoRow(label: 'Node', value: deviceLabel),
                    _InfoRow(
                      label: 'Waktu',
                      value: formatWibDateTime(
                        event.triggeredAt ?? event.createdAt,
                      ),
                    ),
                    _InfoRow(
                      label: 'Dikonfirmasi',
                      value: formatWibDateTime(event.acknowledgedAt),
                    ),
                    _InfoRow(
                      label: 'Ditutup',
                      value: formatWibDateTime(event.resolvedAt),
                      showDivider: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Linimasa', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              if (_timelineLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_timeline.isEmpty)
                const Text('Belum ada catatan linimasa.')
              else
                ..._timeline.map(
                  (item) => Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.appSurface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (item.occurredAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            formatWibDateTime(item.occurredAt),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: context.appTextMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.danger),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (canAcknowledge || canResolve) ...[
                if (canAcknowledge)
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            (repository) => repository.acknowledge(event.id),
                          ),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.task_alt_rounded, size: 18),
                    label: const Text('Tandai Ditangani'),
                  ),
                if (canAcknowledge && canResolve)
                  const SizedBox(height: AppSpacing.sm),
                if (canResolve)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            (repository) => repository.resolve(event.id),
                          ),
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: const Text('Tutup Kejadian'),
                  ),
              ] else
                Text(
                  event.status == EventStatus.resolved
                      ? 'Kejadian ini sudah ditutup.'
                      : 'Hanya petugas yang dapat menindaklanjuti kejadian.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _severityColor(EventSeverity severity) {
    switch (severity) {
      case EventSeverity.critical:
        return AppColors.emergency;
      case EventSeverity.error:
        return AppColors.danger;
      case EventSeverity.warning:
        return AppColors.warning;
    }
  }

  IconData _severityIcon(EventSeverity severity) {
    switch (severity) {
      case EventSeverity.critical:
        return Icons.crisis_alert_rounded;
      case EventSeverity.error:
        return Icons.error_outline_rounded;
      case EventSeverity.warning:
        return Icons.warning_amber_rounded;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final EventStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      EventStatus.active => (AppColors.warningSoft, AppColors.warning),
      EventStatus.acknowledged => (AppColors.successSoft, AppColors.success),
      EventStatus.resolved => (context.appSurface, context.appTextSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, fontSize: 9),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 10, color: context.appTextMuted),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 11, color: context.appTextPrimary),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 0.5, thickness: 0.5),
      ],
    );
  }
}
