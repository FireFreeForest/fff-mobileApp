import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_format_utils.dart';
import '../../data/device_repository.dart';
import '../../data/event_repository.dart';
import '../../models/device.dart';
import '../../models/event.dart';
import '../../models/realtime_event.dart';
import '../../services/realtime_service.dart';
import '../../shared/widgets/app_header.dart';
import 'event_detail_sheet.dart';

enum _HistoryFilter { all, danger, warning, offline }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Map<String, Device> _devicesById = {};
  List<Event> _events = const [];
  _HistoryFilter _filter = _HistoryFilter.all;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exporting = false;
  String? _error;
  int _page = 1;
  int _total = 0;
  bool _hasMore = false;
  int _requestId = 0;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  Timer? _realtimeRefreshTimer;

  @override
  void initState() {
    super.initState();
    _realtimeSubscription = context.read<RealtimeService>().events.listen(
      _onRealtimeEvent,
    );
    _load(reset: true);
  }

  @override
  void dispose() {
    _realtimeRefreshTimer?.cancel();
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (!mounted) return;

    if (event.type == RealtimeTypes.reconnected) {
      unawaited(_load(reset: true, showSpinner: false));
      return;
    }

    if (!event.isEvent) return;

    final payload = event.eventPayload;
    final device = payload?.device;
    if (payload != null && device != null && payload.deviceId.isNotEmpty) {
      _devicesById[payload.deviceId] = device;
    }
    if (payload != null && device != null) {
      if (device.id.isNotEmpty) {
        _devicesById[device.id] = device;
      }
      if (device.deviceId.isNotEmpty) {
        _devicesById[device.deviceId] = device;
      }
    }

    if (_realtimeRefreshTimer?.isActive ?? false) return;
    _realtimeRefreshTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        unawaited(_load(reset: true, showSpinner: false));
      }
    });
  }

  Future<void> _load({required bool reset, bool showSpinner = true}) async {
    final requestId = ++_requestId;

    if (reset) {
      setState(() {
        _page = 1;
        _hasMore = false;
        if (showSpinner) {
          _loading = true;
        }
        _error = null;
      });
    }

    try {
      final eventsFuture = _fetchPage(1);
      final devicesFuture = reset
          ? context.read<DeviceRepository>().listAllDevices().catchError(
              (_) => <Device>[],
            )
          : Future.value(<Device>[]);
      final results = await Future.wait<Object>([eventsFuture, devicesFuture]);

      if (!mounted || requestId != _requestId) return;
      final page = results[0] as PaginatedEvents;
      final devices = results[1] as List<Device>;

      setState(() {
        _events = [...page.items];
        _page = 1;
        _total = page.total;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
        if (devices.isNotEmpty) {
          _devicesById
            ..clear()
            ..addEntries(devices.map((device) => MapEntry(device.id, device)));
        }
      });
    } on ApiException catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'Riwayat kejadian belum dapat dimuat.';
      });
    }
  }

  Future<PaginatedEvents> _fetchPage(int page) async {
    final repository = context.read<EventRepository>();
    final result = await repository.listEvents(
      severity: _severityQuery,
      eventType: _eventTypeQuery,
      page: page,
      perPage: 20,
    );
    return PaginatedEvents(
      items: result.items,
      page: result.page,
      perPage: result.perPage,
      total: result.total,
    );
  }

  String? get _severityQuery {
    switch (_filter) {
      case _HistoryFilter.danger:
        return 'critical';
      case _HistoryFilter.warning:
        return 'warning';
      case _HistoryFilter.all:
      case _HistoryFilter.offline:
        return null;
    }
  }

  String? get _eventTypeQuery =>
      _filter == _HistoryFilter.offline ? 'DEVICE_OFFLINE' : null;

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;

    final requestId = _requestId;
    setState(() {
      _loadingMore = true;
      _error = null;
    });

    try {
      final nextPage = await _fetchPage(_page + 1);
      if (!mounted || requestId != _requestId) return;

      final existingIds = _events.map((event) => event.id).toSet();
      final newEvents = nextPage.items
          .where((event) => !existingIds.contains(event.id))
          .toList();

      setState(() {
        _events = [..._events, ...newEvents];
        _page = nextPage.page;
        _total = nextPage.total;
        _hasMore = nextPage.hasMore;
        _loadingMore = false;
      });
    } on ApiException catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadingMore = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadingMore = false;
        _error = 'Kejadian berikutnya belum dapat dimuat.';
      });
    }
  }

  void _selectFilter(_HistoryFilter filter) {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _events = const [];
      _total = 0;
      _hasMore = false;
    });
    _load(reset: true);
  }

  void _updateEvent(Event updated) {
    final index = _events.indexWhere((event) => event.id == updated.id);
    if (index < 0) return;
    setState(() {
      _events = [..._events]..[index] = updated;
    });
  }

  Future<void> _exportCsv() async {
    if (_exporting || _events.isEmpty) return;

    setState(() {
      _exporting = true;
      _error = null;
    });

    try {
      final events = await _fetchAllForExport();
      final rows = <String>[
        'waktu_wib,device_id,nama_node,lokasi,jenis,severity,status,pesan',
        for (final event in events) _csvRow(event),
      ];
      final bytes = Uint8List.fromList(utf8.encode(rows.join('\r\n')));
      final nowWib = toWib(DateTime.now())!;
      final timestamp =
          '${nowWib.year}'
          '${nowWib.month.toString().padLeft(2, '0')}'
          '${nowWib.day.toString().padLeft(2, '0')}-'
          '${nowWib.hour.toString().padLeft(2, '0')}'
          '${nowWib.minute.toString().padLeft(2, '0')}';

      await SharePlus.instance.share(
        ShareParams(
          subject: 'Riwayat kejadian Fire Free Forest',
          text: 'Riwayat kejadian Fire Free Forest ($timestamp WIB).',
          files: [XFile.fromData(bytes, mimeType: 'text/csv')],
          fileNameOverrides: ['riwayat-fff-$timestamp.csv'],
        ),
      );

      if (!mounted) return;
      setState(() => _exporting = false);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = 'CSV belum dapat diekspor.';
      });
    }
  }

  Future<List<Event>> _fetchAllForExport() async {
    final repository = context.read<EventRepository>();
    final events = <Event>[];
    var page = 1;

    while (page <= 20) {
      final result = await repository.listEvents(
        severity: _severityQuery,
        eventType: _eventTypeQuery,
        page: page,
        perPage: 100,
      );
      events.addAll(result.items);
      if (result.items.isEmpty || events.length >= result.total) {
        break;
      }
      page++;
    }

    return events;
  }

  String _csvRow(Event event) {
    final device = event.device ?? _devicesById[event.deviceId];
    final values = <String>[
      formatWibDateTime(event.triggeredAt ?? event.createdAt),
      device?.deviceId ?? event.deviceCode,
      device?.displayName ?? event.deviceName,
      device?.locationLabel ?? event.deviceLocation,
      event.typeLabel,
      event.severity.label,
      event.status.label,
      event.message,
    ];
    return values.map(_csvCell).join(',');
  }

  String _csvCell(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupedEvents();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => _load(reset: true, showSpinner: false),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: AppHeader(
                  title: 'Riwayat',
                  subtitle: 'Seluruh node · Waktu WIB',
                  actions: [
                    TextButton.icon(
                      onPressed: _events.isEmpty || _exporting
                          ? null
                          : _exportCsv,
                      style: TextButton.styleFrom(
                        backgroundColor: context.appSurface,
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      icon: _exporting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 16),
                      label: const Text(
                        'Ekspor CSV',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: _FilterBar(selected: _filter, onSelected: _selectFilter),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$_total kejadian · Semua node',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: context.appTextSecondary,
                        ),
                      ),
                      Text(
                        'Terbaru dahulu',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: context.appTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading && _events.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _events.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(
                    message: _error!,
                    onRetry: () => _load(reset: true),
                  ),
                )
              else ...[
                if (_loading)
                  const SliverToBoxAdapter(
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.primary,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        0,
                      ),
                      child: _InlineError(
                        message: _error!,
                        onRetry: () => _load(reset: true),
                      ),
                    ),
                  ),
                if (_events.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(filter: _filter),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final group = groups[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: _EventGroup(
                            events: group.events,
                            date: group.date,
                            deviceById: _devicesById,
                            onTap: (event) => _openEvent(event),
                          ),
                        );
                      }, childCount: groups.length),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    child: _PaginationFooter(
                      loading: _loadingMore,
                      hasMore: _hasMore,
                      onLoadMore: _loadMore,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<_EventGroupData> _groupedEvents() {
    final groups = <String, _EventGroupData>{};
    for (final event in _events) {
      final wib = toWib(event.triggeredAt ?? event.createdAt);
      if (wib == null) continue;
      final key = '${wib.year}-${wib.month}-${wib.day}';
      final group = groups.putIfAbsent(
        key,
        () => _EventGroupData(
          date: DateTime(wib.year, wib.month, wib.day),
          events: [],
        ),
      );
      group.events.add(event);
    }
    return groups.values.toList();
  }

  void _openEvent(Event event) {
    showEventDetailSheet(
      context,
      event: event,
      device: event.device ?? _devicesById[event.deviceId],
      onUpdated: _updateEvent,
    );
  }
}

class PaginatedEvents {
  const PaginatedEvents({
    required this.items,
    required this.page,
    required this.perPage,
    required this.total,
  });

  final List<Event> items;
  final int page;
  final int perPage;
  final int total;

  bool get hasMore => page * perPage < total;
}

class _EventGroupData {
  _EventGroupData({required this.date, required this.events});

  final DateTime date;
  final List<Event> events;
}

class _EventGroup extends StatelessWidget {
  const _EventGroup({
    required this.events,
    required this.date,
    required this.deviceById,
    required this.onTap,
  });

  final List<Event> events;
  final DateTime date;
  final Map<String, Device> deviceById;
  final ValueChanged<Event> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _dayLabel(date),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(fontSize: 9, color: context.appTextSecondary),
            ),
            Text(
              '${formatWibDate(date)} · ${events.length} kejadian',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(fontSize: 9, color: context.appTextMuted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(
            children: [
              for (var index = 0; index < events.length; index++) ...[
                if (index > 0) const Divider(height: 0.5, thickness: 0.5),
                _EventRow(
                  event: events[index],
                  device:
                      events[index].device ??
                      deviceById[events[index].deviceId],
                  onTap: () => onTap(events[index]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _dayLabel(DateTime date) {
    final nowWib = toWib(DateTime.now());
    if (nowWib != null) {
      final today = DateTime(nowWib.year, nowWib.month, nowWib.day);
      final difference = today.difference(date).inDays;
      if (difference == 0) return 'HARI INI';
      if (difference == 1) return 'KEMARIN';
    }
    return formatWibDate(date).toUpperCase();
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.device,
    required this.onTap,
  });

  final Event event;
  final Device? device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor(event.severity);
    final time = formatWibTime(event.triggeredAt ?? event.createdAt);
    final subtitle = device == null
        ? event.message
        : '${device!.locationLabel} · ${event.message}';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 38,
              child: Text(
                time,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 11, color: context.appTextSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          device?.deviceId ?? event.deviceCode,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: context.appTextPrimary,
                              ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        event.severity.label,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontSize: 8.5, color: severityColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    event.typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 11.5,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 9,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _StatusChip(status: event.status),
                ],
              ),
            ),
          ],
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
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final EventStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      EventStatus.active => (AppColors.warningSoft, AppColors.warning),
      EventStatus.acknowledged => (AppColors.successSoft, AppColors.success),
      EventStatus.resolved => (context.appBackground, context.appTextSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, fontSize: 9),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final _HistoryFilter selected;
  final ValueChanged<_HistoryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          for (final filter in _HistoryFilter.values)
            Expanded(
              child: _FilterButton(
                label: _label(filter),
                selected: selected == filter,
                onTap: () => onSelected(filter),
              ),
            ),
        ],
      ),
    );
  }

  String _label(_HistoryFilter filter) {
    switch (filter) {
      case _HistoryFilter.all:
        return 'Semua';
      case _HistoryFilter.danger:
        return 'Bahaya';
      case _HistoryFilter.warning:
        return 'Waspada';
      case _HistoryFilter.offline:
        return 'Offline';
    }
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primaryDark : context.appTextSecondary,
          ),
        ),
      ),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
  });

  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (!hasMore) {
      return const SizedBox.shrink();
    }
    return OutlinedButton(
      onPressed: onLoadMore,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
      child: const Text('Muat lebih banyak'),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 44, color: context.appTextMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final _HistoryFilter filter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 44, color: context.appTextMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            filter == _HistoryFilter.all
                ? 'Belum ada kejadian tercatat.'
                : 'Tidak ada kejadian untuk filter ini.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
