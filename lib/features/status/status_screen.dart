import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
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
import '../../shared/widgets/app_logo.dart';

const _defaultCenter = LatLng(-2.5, 118.0);
const _defaultZoom = 4.5;
const _sheetCollapsed = 0.30;

enum _StatusFilter { all, danger, warning, offline }

extension on _StatusFilter {
  String get label {
    return switch (this) {
      _StatusFilter.all => 'Semua',
      _StatusFilter.danger => 'Bahaya',
      _StatusFilter.warning => 'Waspada',
      _StatusFilter.offline => 'Offline',
    };
  }

  Color get color {
    return switch (this) {
      _StatusFilter.all => AppColors.textPrimary,
      _StatusFilter.danger => AppColors.danger,
      _StatusFilter.warning => AppColors.warning,
      _StatusFilter.offline => AppColors.textMuted,
    };
  }

  bool matches(DeviceStatus status) {
    return switch (this) {
      _StatusFilter.all => true,
      _StatusFilter.danger =>
        status.riskLevel == RiskLevel.bahaya ||
            status.riskLevel == RiskLevel.darurat,
      _StatusFilter.warning => status.riskLevel == RiskLevel.waspada,
      _StatusFilter.offline => status.connection == DeviceConnection.offline,
    };
  }
}

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  List<DeviceStatus> _statuses = const [];
  DeviceStatus? _selected;
  _StatusFilter _filter = _StatusFilter.all;
  bool _loading = true;
  bool _hasFitted = false;
  bool _showMarkerLabels = false;
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
    _sheetController.dispose();
    _mapController.dispose();
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

      if (_selected?.device.deviceId == deviceId) {
        _selected = updated;
      }
    });
  }

  List<DeviceStatus> get _visibleStatuses {
    return _statuses.where(_filter.matches).toList();
  }

  List<DeviceStatus> get _locatedStatuses {
    return _visibleStatuses
        .where((status) => status.device.hasLocation)
        .toList();
  }

  int _countFor(_StatusFilter filter) {
    return _statuses.where(filter.matches).length;
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final statuses = await context.read<DeviceRepository>().listStatuses();
      statuses.sort(_compareStatuses);

      if (!mounted) return;
      var shouldFit = false;
      var selectionLost = false;
      setState(() {
        _statuses = statuses;
        _loading = false;
        _error = null;

        final selectedId = _selected?.device.deviceId;
        if (selectedId == null) {
          _selected = null;
        } else {
          final matches = _visibleStatuses
              .where((status) => status.device.deviceId == selectedId)
              .toList();
          _selected = matches.isEmpty ? null : matches.first;
        }

        selectionLost = selectedId != null && _selected == null;
        shouldFit = !_hasFitted && _locatedStatuses.isNotEmpty;
      });

      if (selectionLost) {
        _animateSheet(_sheetCollapsed);
      }
      if (shouldFit) {
        _hasFitted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitNodes());
      }
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
        _error = 'Status wilayah belum dapat dimuat.';
      });
    }
  }

  void _setFilter(_StatusFilter filter) {
    if (_filter == filter) return;

    setState(() {
      _filter = filter;
      _selected = null;
    });
    _animateSheet(_sheetCollapsed);

    final located = _locatedStatuses;
    if (located.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitNodes());
    }
  }

  void _fitNodes() {
    final located = _locatedStatuses;
    if (located.isEmpty) {
      _mapController.move(_defaultCenter, _defaultZoom);
      return;
    }

    final points = located
        .map(
          (status) => LatLng(status.device.latitude!, status.device.longitude!),
        )
        .toList();

    if (points.length == 1) {
      _mapController.move(points.first, 12);
      return;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(48, 190, 48, 270),
        maxZoom: 13,
      ),
    );
  }

  void _focusNode(DeviceStatus status) {
    setState(() => _selected = status);

    if (status.device.hasLocation) {
      final point = LatLng(status.device.latitude!, status.device.longitude!);
      final camera = _mapController.camera;
      _mapController.move(point, camera.zoom < 11 ? 11 : camera.zoom);
    }
  }

  void _clearSelection() {
    setState(() => _selected = null);
  }

  void _animateSheet(double size) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sheetController.isAttached) return;
      _sheetController.animateTo(
        size,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    final showLabels = camera.zoom >= 10;
    if (showLabels == _showMarkerLabels) return;
    setState(() => _showMarkerLabels = showLabels);
  }

  LatLng get _initialCenter {
    final located = _locatedStatuses;
    if (located.isEmpty) return _defaultCenter;
    final latitude =
        located
            .map((status) => status.device.latitude!)
            .reduce((a, b) => a + b) /
        located.length;
    final longitude =
        located
            .map((status) => status.device.longitude!)
            .reduce((a, b) => a + b) /
        located.length;
    return LatLng(latitude, longitude);
  }

  double get _initialZoom => _locatedStatuses.isEmpty ? _defaultZoom : 7;

  @override
  Widget build(BuildContext context) {
    final visible = _visibleStatuses;
    final online = _statuses
        .where((status) => status.connection == DeviceConnection.online)
        .length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: _initialZoom,
                minZoom: 4,
                maxZoom: 18,
                backgroundColor: AppColors.background,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onPositionChanged: _handlePositionChanged,
                onTap: (_, _) {
                  if (_selected != null) {
                    _clearSelection();
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.firefreeforest',
                  maxNativeZoom: 19,
                ),
                MarkerLayer(
                  markers: _locatedStatuses
                      .map(
                        (status) => Marker(
                          point: LatLng(
                            status.device.latitude!,
                            status.device.longitude!,
                          ),
                          width: 76,
                          height: 58,
                          alignment: Alignment.topCenter,
                          child: _MapMarker(
                            status: status,
                            selected:
                                _selected?.device.deviceId ==
                                status.device.deviceId,
                            showLabel:
                                _showMarkerLabels ||
                                _selected?.device.deviceId ==
                                    status.device.deviceId,
                            onTap: () => _focusNode(status),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SimpleAttributionWidget(
                  source: Text(
                    'OpenStreetMap contributors',
                    style: TextStyle(fontSize: 8),
                  ),
                ),
              ],
            ),
          ),
          if (_loading && _statuses.isEmpty)
            const Center(child: CircularProgressIndicator()),
          if (_selected == null)
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: _sheetCollapsed,
              minChildSize: 0.16,
              maxChildSize: 0.70,
              snap: true,
              snapSizes: const [0.16, _sheetCollapsed, 0.70],
              builder: (context, scrollController) {
                return _StatusSheet(
                  scrollController: scrollController,
                  statuses: visible,
                  total: _statuses.length,
                  online: visible
                      .where(
                        (status) =>
                            status.connection == DeviceConnection.online,
                      )
                      .length,
                  filter: _filter,
                  loading: _loading,
                  error: _error,
                  onSelect: _focusNode,
                  onResetFilter: () => _setFilter(_StatusFilter.all),
                );
              },
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: _selected == null
                  ? const SizedBox.shrink(key: ValueKey('no-selected-node'))
                  : _SelectedNodePanel(
                      key: ValueKey(_selected!.device.deviceId),
                      status: _selected!,
                      total: _statuses.length,
                      onOpenDetail: () {
                        context.push(
                          '/nodes/'
                          '${Uri.encodeComponent(_selected!.device.deviceId)}',
                        );
                      },
                      onClearSelection: _clearSelection,
                    ),
            ),
          ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  _TopBar(
                    total: _statuses.length,
                    online: online,
                    onSettings: () => context.push('/settings'),
                    onRefresh: () => _load(showSpinner: false),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _StatusErrorBanner(
                      message: _error!,
                      onRetry: () => _load(),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _FilterBar(
                          selected: _filter,
                          counts: {
                            for (final filter in _StatusFilter.values)
                              filter: _countFor(filter),
                          },
                          onSelect: _setFilter,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _MapActionButton(
                        icon: Icons.my_location_rounded,
                        tooltip: 'Pusatkan peta',
                        onPressed: _fitNodes,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _MapLegend(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.total,
    required this.online,
    required this.onSettings,
    required this.onRefresh,
  });

  final int total;
  final int online;
  final VoidCallback onSettings;
  final VoidCallback onRefresh;

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
        color: AppColors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const AppLogo(size: 36),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fire Free Forest',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '$total node · $online online · ${AppConfig.regionLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          IconButton(
            onPressed: onSettings,
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final _StatusFilter selected;
  final Map<_StatusFilter, int> counts;
  final ValueChanged<_StatusFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _StatusFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final filter = _StatusFilter.values[index];
          return _FilterChip(
            filter: filter,
            count: counts[filter] ?? 0,
            selected: selected == filter,
            onTap: () => onSelect(filter),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.filter,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final _StatusFilter filter;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = filter.color;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter ${filter.label}, $count node',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.15)
                : AppColors.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
            boxShadow: selected
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                filter.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? color : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.16)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: selected ? color : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.96),
      elevation: 1,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 19, color: AppColors.textPrimary),
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: const [
          _LegendItem(color: AppColors.success, label: 'Normal'),
          _LegendItem(color: AppColors.warning, label: 'Waspada'),
          _LegendItem(color: AppColors.danger, label: 'Bahaya'),
          _LegendItem(color: AppColors.emergency, label: 'Darurat'),
          _LegendItem(color: AppColors.textMuted, label: 'Offline'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 8, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({
    required this.status,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final DeviceStatus status;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final offline = status.connection == DeviceConnection.offline;
    final color = offline ? AppColors.textMuted : status.riskLevel.color;
    final size = selected ? 34.0 : 28.0;

    return Semantics(
      button: true,
      label:
          '${status.device.deviceId}, ${status.connection.label}, '
          '${status.riskLevel.label}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: selected ? 0.24 : 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color.withValues(alpha: selected ? 0.9 : 0.45),
                        width: selected ? 2.5 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.30),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Container(
                        width: selected ? 12 : 9,
                        height: selected ? 12 : 9,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 3.4,
                            height: 3.4,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: _ConnectionBadge(
                      online: !offline,
                      color: offline ? AppColors.textMuted : AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 16,
              child: showLabel
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusPill,
                        ),
                        border: Border.all(
                          color: color.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        status.device.deviceId,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.online, required this.color});

  final bool online;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 1.8),
      ),
      child: Icon(
        online ? Icons.check_rounded : Icons.remove_rounded,
        size: 7,
        color: Colors.white,
      ),
    );
  }
}

class _StatusSheet extends StatelessWidget {
  const _StatusSheet({
    required this.scrollController,
    required this.statuses,
    required this.total,
    required this.online,
    required this.filter,
    required this.loading,
    required this.error,
    required this.onSelect,
    required this.onResetFilter,
  });

  final ScrollController scrollController;
  final List<DeviceStatus> statuses;
  final int total;
  final int online;
  final _StatusFilter filter;
  final bool loading;
  final String? error;
  final ValueChanged<DeviceStatus> onSelect;
  final VoidCallback onResetFilter;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 22,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'STATUS WILAYAH',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const Spacer(),
                    Text(
                      filter == _StatusFilter.all
                          ? '${statuses.length} node'
                          : '${filter.label} · ${statuses.length}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontSize: 9, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _SummaryBody(
                  statuses: statuses,
                  total: total,
                  online: online,
                  filter: filter,
                  loading: loading,
                  error: error,
                  onSelect: onSelect,
                  onResetFilter: onResetFilter,
                ),
                SizedBox(height: bottomInset + AppSpacing.lg),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.statuses,
    required this.total,
    required this.online,
    required this.filter,
    required this.loading,
    required this.error,
    required this.onSelect,
    required this.onResetFilter,
  });

  final List<DeviceStatus> statuses;
  final int total;
  final int online;
  final _StatusFilter filter;
  final bool loading;
  final String? error;
  final ValueChanged<DeviceStatus> onSelect;
  final VoidCallback onResetFilter;

  @override
  Widget build(BuildContext context) {
    final headline = statuses.isEmpty
        ? loading
              ? 'Memuat node...'
              : error != null
              ? 'Status belum termuat'
              : total == 0
              ? 'Belum ada node'
              : 'Tidak ada node pada filter'
        : '${statuses.length} node · $online online';
    final hint = loading
        ? 'Menyiapkan status node...'
        : error != null
        ? 'Periksa koneksi lalu muat ulang status wilayah.'
        : statuses.isEmpty
        ? (total == 0
              ? 'Tambahkan node melalui menu Node untuk mulai memantau.'
              : 'Geser filter di atas peta untuk melihat node lain.')
        : filter == _StatusFilter.all
        ? 'Ketuk penanda atau node untuk melihat detail.'
        : 'Difilter dari $total node · ketuk node untuk detail.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                headline,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (statuses.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.successSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  '$online online',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hint,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 10, color: AppColors.textMuted),
        ),
        if (statuses.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: statuses.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final status = statuses[index];
                return _NodeChip(status: status, onTap: () => onSelect(status));
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text(
                'DAFTAR NODE',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              Text(
                'Urut risiko',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 9, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var index = 0; index < statuses.length; index++) ...[
            _NodeRow(
              status: statuses[index],
              onTap: () => onSelect(statuses[index]),
            ),
            if (index != statuses.length - 1)
              const Divider(height: 1, color: AppColors.border),
          ],
        ] else if (filter != _StatusFilter.all && total > 0 && !loading) ...[
          const SizedBox(height: AppSpacing.md),
          _FilterEmpty(onReset: onResetFilter),
        ],
      ],
    );
  }
}

class _FilterEmpty extends StatelessWidget {
  const _FilterEmpty({required this.onReset});

  final VoidCallback onReset;

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
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.filter_alt_off_outlined,
            size: 18,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Tidak ada node yang cocok dengan filter ini.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 10, color: AppColors.textSecondary),
            ),
          ),
          TextButton(onPressed: onReset, child: const Text('Reset')),
        ],
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
    final offline = status.connection == DeviceConnection.offline;
    final color = offline ? AppColors.textMuted : status.riskLevel.color;
    final fire = status.fire;
    final smoke = fire?.smokeLevel;
    final lastSeen = status.lastTelemetryAt ?? status.lastSeenAt;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Icon(
                  offline ? Icons.wifi_off_rounded : status.riskLevel.icon,
                  size: 15,
                  color: color,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${device.deviceId} · ${device.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${device.locationLabel} · ${offline ? 'Offline' : '${status.connection.label} · ${status.riskLevel.label}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 9,
                        color: offline ? AppColors.textMuted : color,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      relativeTime(lastSeen),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontSize: 8, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    smoke == null ? '--' : '$smoke',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color:
                          smoke != null && smoke >= AppConfig.smokeThresholdAdc
                          ? AppColors.danger
                          : AppColors.textPrimary,
                    ),
                  ),
                  const Text(
                    'ADC',
                    style: TextStyle(fontSize: 8, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedNodePanel extends StatelessWidget {
  const _SelectedNodePanel({
    super.key,
    required this.status,
    required this.total,
    required this.onOpenDetail,
    required this.onClearSelection,
  });

  final DeviceStatus status;
  final int total;
  final VoidCallback onOpenDetail;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.70;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 22,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'NODE TERPILIH',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const Spacer(),
                    Text(
                      '$total node',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(fontSize: 9, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _SelectedBody(
                  status: status,
                  onOpenDetail: onOpenDetail,
                  onClearSelection: onClearSelection,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedBody extends StatelessWidget {
  const _SelectedBody({
    required this.status,
    required this.onOpenDetail,
    required this.onClearSelection,
  });

  final DeviceStatus status;
  final VoidCallback onOpenDetail;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final device = status.device;
    final offline = status.connection == DeviceConnection.offline;
    final risk = offline ? RiskLevel.unknown : status.riskLevel;
    final color = offline ? AppColors.textMuted : risk.color;
    final fire = status.fire;
    final smoke = fire?.smokeLevel;
    final lastSeen = status.lastTelemetryAt ?? status.lastSeenAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${device.deviceId} · ${device.displayName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: onClearSelection,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Tutup',
            ),
          ],
        ),
        Text(
          device.locationLabel,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 10, color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusPill(
              label: offline ? 'Offline' : 'Online',
              color: offline ? AppColors.textMuted : AppColors.success,
              icon: offline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
            ),
            _StatusPill(label: risk.label, color: color, icon: risk.icon),
            Text(
              relativeTime(lastSeen),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 9, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _MiniMetric(
              label: 'ASAP',
              value: smoke == null ? '--' : '$smoke',
              suffix: 'ADC',
            ),
            const SizedBox(width: AppSpacing.lg),
            _MiniMetric(
              label: 'SUHU',
              value:
                  status.environment?.temperature?.toStringAsFixed(1) ?? '--',
              suffix: '°C',
            ),
            const SizedBox(width: AppSpacing.lg),
            _MiniMetric(
              label: 'TANAH',
              value:
                  status.environment?.soilMoisture.toStringAsFixed(0) ?? '--',
              suffix: 'ADC',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onOpenDetail,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Buka detail node'),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeChip extends StatelessWidget {
  const _NodeChip({required this.status, required this.onTap});

  final DeviceStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final offline = status.connection == DeviceConnection.offline;
    final color = offline ? AppColors.textMuted : status.riskLevel.color;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              status.device.deviceId,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
            if (offline) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.wifi_off_rounded,
                size: 10,
                color: AppColors.textMuted,
              ),
            ],
            if (!status.device.hasLocation) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.location_off_outlined,
                size: 11,
                color: AppColors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.suffix,
  });

  final String label;
  final String value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 2),
            Text(
              suffix,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 8, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusErrorBanner extends StatelessWidget {
  const _StatusErrorBanner({required this.message, required this.onRetry});

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
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
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
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Ulangi')),
        ],
      ),
    );
  }
}
