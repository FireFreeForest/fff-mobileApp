import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/risk_style.dart';
import '../../core/utils/date_format_utils.dart';
import '../../data/device_repository.dart';
import '../../models/device.dart';
import '../../models/device_status.dart';
import '../../models/realtime_event.dart';
import '../../services/realtime_service.dart';
import '../../services/realtime_updater.dart';
import '../../shared/widgets/app_header.dart';
import '../../shared/widgets/empty_state.dart';
import '../../state/auth_controller.dart';

enum _NodeFilter { all, danger, warning, offline }

class NodesScreen extends StatefulWidget {
  const NodesScreen({super.key});

  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

class _NodesScreenState extends State<NodesScreen> {
  final _searchController = TextEditingController();
  List<DeviceStatus> _statuses = const [];
  _NodeFilter _filter = _NodeFilter.all;
  bool _loading = true;
  String? _error;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _realtimeSubscription = context.read<RealtimeService>().events.listen(
      _onRealtimeEvent,
    );
    _load();
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  int _compareStatuses(DeviceStatus a, DeviceStatus b) {
    final urgency = b.riskLevel.urgency.compareTo(a.riskLevel.urgency);
    if (urgency != 0) return urgency;
    return a.device.deviceId.compareTo(b.device.deviceId);
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (!mounted) return;

    if (event.type == RealtimeTypes.reconnected) {
      unawaited(_load(showSpinner: false));
      return;
    }

    final deviceId = event.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;

    final index = _statuses.indexWhere(
      (status) =>
          status.device.deviceId == deviceId || status.device.id == deviceId,
    );
    if (index < 0) {
      if (event.isTelemetry || event.type == RealtimeTypes.deviceStatus) {
        unawaited(_load(showSpinner: false));
      }
      return;
    }

    final updated = applyRealtimeToStatus(_statuses[index], event);
    if (identical(updated, _statuses[index])) return;

    setState(() {
      final statuses = [..._statuses];
      statuses[index] = updated;
      statuses.sort(_compareStatuses);
      _statuses = statuses;
    });
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final query = _searchController.text.trim();
      final repository = context.read<DeviceRepository>();
      final statuses = query.isEmpty
          ? await repository.listStatuses()
          : await repository.listStatuses(query: query);
      statuses.sort(_compareStatuses);

      if (!mounted) return;
      setState(() {
        _statuses = statuses;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Daftar node belum dapat dimuat.';
      });
    }
  }

  List<DeviceStatus> get _visibleStatuses {
    final query = _searchController.text.trim().toLowerCase();

    return _statuses.where((status) {
      final matchesFilter = switch (_filter) {
        _NodeFilter.all => true,
        _NodeFilter.danger =>
          status.riskLevel == RiskLevel.bahaya ||
              status.riskLevel == RiskLevel.darurat,
        _NodeFilter.warning => status.riskLevel == RiskLevel.waspada,
        _NodeFilter.offline => status.connection == DeviceConnection.offline,
      };
      if (!matchesFilter) return false;
      if (query.isEmpty) return true;

      final device = status.device;
      return device.deviceId.toLowerCase().contains(query) ||
          device.name.toLowerCase().contains(query) ||
          device.locationName.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final online = _statuses
        .where((status) => status.connection == DeviceConnection.online)
        .length;
    final visible = _visibleStatuses;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => _load(showSpinner: false),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: AppHeader(
                  title: 'Node',
                  subtitle: '${_statuses.length} terpasang · $online online',
                  actions: [
                    if (auth.canManageDevices)
                      IconButton(
                        onPressed: () async {
                          await context.push('/nodes/add');
                          if (mounted) {
                            await _load(showSpinner: false);
                          }
                        },
                        tooltip: 'Tambah node',
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                    IconButton(
                      onPressed: () => context.push('/settings'),
                      tooltip: 'Pengaturan',
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _load(showSpinner: false),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Cari ID, nama, atau lokasi',
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: context.appTextMuted,
                      ),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _buildFilters()),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: _ErrorBanner(
                      message: _error!,
                      onRetry: () => _load(),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Container(
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
                        'URUTAN URGENSI',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        'ASAP / ADC',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading && _statuses.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.sensors_off_outlined,
                    title: _statuses.isEmpty
                        ? 'Belum ada node'
                        : 'Node tidak ditemukan',
                    message: _statuses.isEmpty
                        ? 'Node yang terdaftar di backend akan muncul di sini.'
                        : 'Coba ubah kata pencarian atau filter status.',
                  ),
                )
              else
                SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final status = visible[index];
                    return _NodeRow(
                      status: status,
                      onTap: () async {
                        await context.push(
                          '/nodes/${Uri.encodeComponent(status.device.deviceId)}',
                        );
                        if (mounted) {
                          await _load(showSpinner: false);
                        }
                      },
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    const filters = <_NodeFilter, String>{
      _NodeFilter.all: 'Semua',
      _NodeFilter.danger: 'Bahaya',
      _NodeFilter.warning: 'Waspada',
      _NodeFilter.offline: 'Offline',
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: filters.entries.map((entry) {
          final selected = _filter == entry.key;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              onTap: () => setState(() => _filter = entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.primaryDark
                        : context.appTextSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({required this.status, required this.onTap});

  final DeviceStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final device = status.device;
    final fire = status.fire;
    final offline = status.connection == DeviceConnection.offline;
    final color = offline ? context.appTextMuted : status.riskLevel.color;
    final smoke = fire?.smokeLevel;
    final smokeCritical = smoke != null && smoke >= AppConfig.smokeThresholdAdc;

    final statusLabel = offline
        ? 'Offline'
        : [
            status.riskLevel.label,
            if (fire?.flameDetected == true) 'Api',
          ].join(' · ');

    final lastSeen = status.lastTelemetryAt ?? status.lastSeenAt;
    final connectionLabel = offline
        ? 'Offline · ${relativeTime(lastSeen)}'
        : 'Online · ${relativeTime(lastSeen)}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.appBorder)),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${device.deviceId} · ${device.locationLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 12.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      connectionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontSize: 10, color: context.appTextMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 76,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      smoke == null ? '--' : '$smoke',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w300,
                        color: offline
                            ? context.appTextMuted
                            : smokeCritical
                            ? AppColors.danger
                            : context.appTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w400,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: context.appTextMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.appTextPrimary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Ulangi')),
        ],
      ),
    );
  }
}
