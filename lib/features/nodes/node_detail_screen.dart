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
import '../../data/event_repository.dart';
import '../../data/geocoding_repository.dart';
import '../../models/device.dart';
import '../../models/device_status.dart';
import '../../models/event.dart';
import '../../models/realtime_event.dart';
import '../../models/telemetry.dart';
import '../../services/realtime_service.dart';
import '../../services/realtime_updater.dart';
import '../../shared/widgets/app_header.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/smoke_chart.dart';
import '../../shared/widgets/aggregate_chart.dart';
import '../../shared/widgets/surface_card.dart';
import '../../state/auth_controller.dart';
import 'widgets/pump_control_card.dart';
import 'location_picker_screen.dart';

enum _TrendRange { oneHour, sixHours, oneDay, sevenDays, custom }

class NodeDetailScreen extends StatefulWidget {
  const NodeDetailScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<NodeDetailScreen> createState() => _NodeDetailScreenState();
}

class _NodeDetailScreenState extends State<NodeDetailScreen> {
  static const _maxFireHistory = 30;

  _DetailData? _data;
  bool _loading = true;
  String? _error;
  _TrendRange _trendRange = _TrendRange.oneDay;
  DateTimeRange? _customRange;
  bool _aggregateLoading = false;
  Map<String, dynamic>? _environmentAggregate;
  Map<String, dynamic>? _fireAggregate;
  List<Event> _recentEvents = const [];
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
    super.dispose();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (!mounted) return;

    if (event.type == RealtimeTypes.reconnected) {
      unawaited(_load(showSpinner: false));
      return;
    }

    final data = _data;
    if (!_matchesDevice(event, data)) return;

    if (event.type == RealtimeTypes.commandAck ||
        event.type == RealtimeTypes.commandTimeout) {
      unawaited(_load(showSpinner: false));
      return;
    }

    if (event.isEvent) {
      unawaited(_load(showSpinner: false));
      return;
    }

    if (data == null) {
      if (event.isTelemetry || event.type == RealtimeTypes.deviceStatus) {
        unawaited(_load(showSpinner: false));
      }
      return;
    }

    final updatedStatus = applyRealtimeToStatus(data.status, event);
    var fireHistory = data.fireHistory;
    var historyChanged = false;

    if (event.type == RealtimeTypes.telemetryFire) {
      final payload = event.telemetry;
      if (payload.isNotEmpty) {
        final fire = TelemetryFire.fromJson(payload);
        fireHistory = [
          ...data.fireHistory.where((reading) => reading.id != fire.id),
          fire,
        ]..sort((a, b) => _readingTime(a).compareTo(_readingTime(b)));

        if (fireHistory.length > _maxFireHistory) {
          fireHistory = fireHistory.sublist(
            fireHistory.length - _maxFireHistory,
          );
        }
        historyChanged = true;
      }
    }

    if (identical(updatedStatus, data.status) && !historyChanged) return;

    setState(() {
      _data = _DetailData(status: updatedStatus, fireHistory: fireHistory);
    });
  }

  bool _matchesDevice(RealtimeEvent event, _DetailData? data) {
    final deviceId = event.deviceId;
    if (deviceId == null || deviceId.isEmpty) return false;
    return deviceId == widget.deviceId || deviceId == data?.status.device.id;
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final repository = context.read<DeviceRepository>();
      final status = await repository.getStatus(widget.deviceId);
      var mergedStatus = status;
      try {
        final latest = await repository.getLatest(widget.deviceId);
        mergedStatus = latest.copyWith(
          device: status.device,
          connection: status.connection,
          lastSeenAt: status.lastSeenAt,
          onlineSince: status.onlineSince,
          uptimeSeconds: status.uptimeSeconds,
        );
      } catch (_) {
        mergedStatus = status;
      }

      var fireHistory = <TelemetryFire>[];
      try {
        final history = await repository.listFireHistory(
          widget.deviceId,
          perPage: 30,
        );
        fireHistory = [...history.items];
      } catch (_) {
        fireHistory = [];
      }

      var recentEvents = <Event>[];
      try {
        final events = await context.read<EventRepository>().listEvents(
          deviceId: widget.deviceId,
          perPage: 5,
        );
        recentEvents = events.items;
      } catch (_) {
        recentEvents = [];
      }

      fireHistory.sort((a, b) => _readingTime(a).compareTo(_readingTime(b)));

      if (!mounted) return;
      setState(() {
        _data = _DetailData(status: mergedStatus, fireHistory: fireHistory);
        _recentEvents = recentEvents;
        _loading = false;
        _error = null;
      });
      await _loadAggregates(showSpinner: false);
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
        _error = 'Detail node belum dapat dimuat.';
      });
    }
  }

  DateTime _readingTime(TelemetryFire reading) {
    return reading.recordedAt ??
        reading.receivedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _selectTrendRange(_TrendRange range) async {
    if (range == _TrendRange.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: now.subtract(const Duration(days: 90)),
        lastDate: now,
        initialDateRange:
            _customRange ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 1)),
              end: now,
            ),
        helpText: 'Rentang data node',
        saveText: 'Terapkan',
      );
      if (picked == null || !mounted) return;
      if (picked.duration > const Duration(days: 30)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rentang kustom maksimal 30 hari.')),
        );
        return;
      }
      setState(() {
        _trendRange = range;
        _customRange = picked;
      });
    } else {
      setState(() => _trendRange = range);
    }
    await _loadAggregates();
  }

  Future<void> _loadAggregates({bool showSpinner = true}) async {
    if (!mounted) return;
    if (showSpinner) {
      setState(() => _aggregateLoading = true);
    } else {
      setState(() => _aggregateLoading = true);
    }
    try {
      final now = DateTime.now();
      final range = _customRange;
      final from = switch (_trendRange) {
        _TrendRange.oneHour => now.subtract(const Duration(hours: 1)),
        _TrendRange.sixHours => now.subtract(const Duration(hours: 6)),
        _TrendRange.oneDay => now.subtract(const Duration(hours: 24)),
        _TrendRange.sevenDays => now.subtract(const Duration(days: 7)),
        _TrendRange.custom =>
          range?.start ?? now.subtract(const Duration(hours: 24)),
      };
      final to = _trendRange == _TrendRange.custom ? (range?.end ?? now) : now;
      final spanMinutes = to.difference(from).inMinutes;
      final interval = switch (_trendRange) {
        _TrendRange.oneHour => 0,
        _TrendRange.sixHours => 5,
        _TrendRange.oneDay => 15,
        _TrendRange.sevenDays => 60,
        _TrendRange.custom =>
          spanMinutes <= 60
              ? 0
              : spanMinutes <= 360
              ? 5
              : spanMinutes <= 1440
              ? 15
              : 60,
      };
      final repository = context.read<DeviceRepository>();
      final results = await Future.wait([
        repository.aggregateEnvironment(
          widget.deviceId,
          from: from,
          to: to,
          interval: interval,
        ),
        repository.aggregateFire(
          widget.deviceId,
          from: from,
          to: to,
          interval: interval,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _environmentAggregate = results[0];
        _fireAggregate = results[1];
        _aggregateLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _aggregateLoading = false);
    }
  }

  Future<void> _editNode(BuildContext context) async {
    final status = _data?.status;
    if (status == null) return;
    final nameController = TextEditingController(text: status.device.name);
    final locationController = TextEditingController(
      text: status.device.locationName,
    );
    LatLng? location = status.device.hasLocation
        ? LatLng(status.device.latitude!, status.device.longitude!)
        : null;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          decoration: BoxDecoration(
                            color: context.appBorder,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusPill,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'Ubah node',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nama node',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: 'Nama lokasi',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await Navigator.of(context)
                              .push<LatLng>(
                                MaterialPageRoute(
                                  builder: (_) => LocationPickerScreen(
                                    initialLocation: location,
                                  ),
                                ),
                              );
                          if (picked == null) return;
                          setSheetState(() => location = picked);
                          try {
                            final label = await context
                                .read<GeocodingRepository>()
                                .reverseLabel(
                                  latitude: picked.latitude,
                                  longitude: picked.longitude,
                                );
                            if (label != null) {
                              setSheetState(
                                () => locationController.text = label,
                              );
                            }
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.map_outlined),
                        label: Text(
                          location == null
                              ? 'Pilih lokasi di peta'
                              : '${location!.latitude.toStringAsFixed(5)}, ${location!.longitude.toStringAsFixed(5)}',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: const Text('Simpan perubahan'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (result != true || !mounted) return;

    try {
      await context.read<DeviceRepository>().updateDevice(
        deviceId: widget.deviceId,
        name: nameController.text.trim(),
        locationName: locationController.text.trim(),
        latitude: location?.latitude ?? status.device.latitude ?? 0,
        longitude: location?.longitude ?? status.device.longitude ?? 0,
      );
      nameController.dispose();
      locationController.dispose();
      await _load(showSpinner: false);
    } on ApiException catch (error) {
      nameController.dispose();
      locationController.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus node?'),
        content: Text(
          'Node ${widget.deviceId} dan seluruh data perangkatnya akan dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<DeviceRepository>().deleteDevice(widget.deviceId);
      if (!mounted) return;
      context.go('/nodes');
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final auth = context.watch<AuthController>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _DetailHeader(
              device: data?.status.device,
              fallbackDeviceId: widget.deviceId,
              canDelete: auth.canManageDevices,
              canEdit: auth.canManageDevices,
              onEdit: () => _editNode(context),
              onDelete: () => _confirmDelete(context),
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/nodes');
                }
              },
            ),
            Expanded(child: _buildBody(data, canOperate: auth.canOperate)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(_DetailData? data, {required bool canOperate}) {
    if (_loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && data == null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Gagal memuat node',
        message: _error!,
        action: FilledButton(
          onPressed: () => _load(),
          child: const Text('Coba lagi'),
        ),
      );
    }

    if (data == null) {
      return const EmptyState(
        icon: Icons.sensors_off_outlined,
        title: 'Node tidak ditemukan',
        message: 'Data node tidak tersedia.',
      );
    }

    final status = data.status;
    final fire = status.fire;
    final environment = status.environment;
    final temperature = environment?.temperature;
    final humidity = environment?.humidity;
    final soil = environment?.soilMoisture;
    final smoke = fire?.smokeLevel;
    final flameLevel = fire?.flameLevel;
    final smokeCritical = smoke != null && smoke >= AppConfig.smokeThresholdAdc;
    final temperatureHigh = temperature != null && temperature >= 40;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(showSpinner: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _ErrorBanner(
                message: _error!,
                onRetry: () => _load(showSpinner: false),
              ),
            ),
          _StatusCard(status: status),
          const SizedBox(height: AppSpacing.xl),
          _SectionHeader(title: 'PEMBACAAN SENSOR', trailing: 'Data langsung'),
          const SizedBox(height: AppSpacing.sm),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 0,
            ),
            child: Column(
              children: [
                _SensorRow(
                  icon: Icons.local_fire_department_outlined,
                  title: 'Api',
                  caption: 'Bahaya jika api terdeteksi',
                  value: fire == null
                      ? '--'
                      : fire.flameDetected
                      ? 'Terdeteksi'
                      : 'Tidak terdeteksi',
                  valueCaption: 'Sensor api',
                  valueColor: fire?.flameDetected == true
                      ? AppColors.danger
                      : context.appTextPrimary,
                ),
                const Divider(),
                _SensorRow(
                  icon: Icons.flare_outlined,
                  title: 'Level api',
                  caption: 'Nilai analog sensor api',
                  value: flameLevel == null ? '--' : '$flameLevel',
                  valueCaption: 'ADC',
                  valueColor: context.appTextPrimary,
                ),
                const Divider(),
                _SensorRow(
                  icon: Icons.air_rounded,
                  title: 'Asap',
                  caption: 'Ambang bahaya ≥ ${AppConfig.smokeThresholdAdc} ADC',
                  value: smoke == null ? '--' : '$smoke',
                  valueCaption: 'MQ2 · ADC',
                  valueColor: smokeCritical
                      ? AppColors.danger
                      : context.appTextPrimary,
                ),
                const Divider(),
                _SensorRow(
                  icon: Icons.thermostat_outlined,
                  title: 'Suhu udara',
                  caption: 'Waspada ≥ 40°C',
                  value: temperature == null
                      ? '--'
                      : '${temperature.toStringAsFixed(1)}°C',
                  valueCaption: 'DHT11',
                  valueColor: temperatureHigh
                      ? AppColors.warning
                      : context.appTextPrimary,
                ),
                const Divider(),
                _SensorRow(
                  icon: Icons.water_drop_outlined,
                  title: 'Kelembapan udara',
                  caption: 'Kering jika < 35%',
                  value: humidity == null
                      ? '--'
                      : '${humidity.toStringAsFixed(0)}%',
                  valueCaption: 'DHT11',
                  valueColor: humidity != null && humidity < 35
                      ? AppColors.warning
                      : context.appTextPrimary,
                ),
                const Divider(),
                _SensorRow(
                  icon: Icons.grass_outlined,
                  title: 'Kelembapan tanah',
                  caption: 'Nilai mentah sensor tanah',
                  value: soil == null ? '--' : soil.toStringAsFixed(0),
                  valueCaption: 'Sensor tanah · ADC',
                  valueColor: context.appTextPrimary,
                ),
                const Divider(),
                _SensorRow(
                  icon: Icons.water_outlined,
                  title: 'Pompa air',
                  caption: 'Status dari perangkat',
                  value: fire == null
                      ? '--'
                      : fire.pump
                      ? 'Menyala'
                      : 'Mati',
                  valueCaption: 'Pompa',
                  valueColor: fire?.pump == true
                      ? AppColors.primary
                      : context.appTextSecondary,
                ),
                const Divider(),
                _SensorRow(
                  icon: Icons.notifications_active_outlined,
                  title: 'Buzzer',
                  caption: 'Status dari perangkat',
                  value: fire == null
                      ? '--'
                      : fire.buzzer
                      ? 'Menyala'
                      : 'Mati',
                  valueCaption: 'Buzzer',
                  valueColor: fire?.buzzer == true
                      ? AppColors.warning
                      : context.appTextSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionHeader(title: 'ASAP (MQ2)'),
          const SizedBox(height: AppSpacing.sm),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${data.fireHistory.length} pembacaan terakhir',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      smoke == null ? '--' : '$smoke ADC',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w300,
                        color: smokeCritical
                            ? AppColors.danger
                            : context.appTextPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SmokeChart(
                  readings: data.fireHistory,
                  threshold: AppConfig.smokeThresholdAdc,
                ),
                if (data.fireHistory.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _ChartTimeLabels(readings: data.fireHistory),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Ambang bahaya ≥ ${AppConfig.smokeThresholdAdc} ADC · '
                  'Nilai mentah sensor asap · Waktu WIB',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 10, color: context.appTextMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionHeader(title: 'KONTROL POMPA'),
          const SizedBox(height: AppSpacing.sm),
          PumpControlCard(
            deviceId: status.device.deviceId,
            pumpOn: fire?.pump,
            online: status.connection == DeviceConnection.online,
            canOperate: canOperate,
            onCommandSettled: () => _load(showSpinner: false),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionHeader(title: 'GRAFIK SENSOR AGREGAT'),
          const SizedBox(height: AppSpacing.sm),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final range in const {
                      _TrendRange.oneHour: '1J',
                      _TrendRange.sixHours: '6J',
                      _TrendRange.oneDay: '24J',
                      _TrendRange.sevenDays: '7H',
                    }.entries)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: range.key == _TrendRange.sevenDays
                                ? 0
                                : AppSpacing.xs,
                          ),
                          child: ChoiceChip(
                            label: Center(child: Text(range.value)),
                            selected: _trendRange == range.key,
                            showCheckmark: false,
                            selectedColor: AppColors.primary.withValues(
                              alpha: 0.16,
                            ),
                            side: BorderSide(
                              color: _trendRange == range.key
                                  ? AppColors.primary
                                  : context.appBorder,
                            ),
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: _trendRange == range.key
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _trendRange == range.key
                                  ? AppColors.primaryDark
                                  : context.appTextSecondary,
                            ),
                            onSelected: (selected) {
                              if (!selected) return;
                              _selectTrendRange(range.key);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _selectTrendRange(_TrendRange.custom),
                    icon: const Icon(Icons.calendar_month_outlined, size: 17),
                    label: Text(
                      _trendRange == _TrendRange.custom && _customRange != null
                          ? '${formatWibDate(_customRange!.start)} - ${formatWibDate(_customRange!.end)}'
                          : 'Rentang kustom',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_aggregateLoading)
                  const SizedBox(
                    height: 180,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Column(
                    children: [
                      AggregateChart(
                        environment: _environmentAggregate,
                        fire: null,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const Divider(),
                      const SizedBox(height: AppSpacing.sm),
                      AggregateChart(environment: null, fire: _fireAggregate),
                      const SizedBox(height: AppSpacing.lg),
                      _PumpAggregateSummary(data: _fireAggregate),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const _SectionHeader(title: 'LOKASI NODE'),
          const SizedBox(height: AppSpacing.sm),
          _LocationCard(device: status.device),
          const SizedBox(height: AppSpacing.xl),
          const _SectionHeader(title: 'AKTIVITAS TERBARU'),
          const SizedBox(height: AppSpacing.sm),
          _RecentActivityCard(events: _recentEvents),
          const SizedBox(height: AppSpacing.xl),
          const _SectionHeader(title: 'INFORMASI NODE'),
          const SizedBox(height: AppSpacing.sm),
          SurfaceCard(
            child: Column(
              children: [
                _InfoRow(label: 'ID node', value: status.device.deviceId),
                const Divider(),
                _InfoRow(
                  label: 'Firmware',
                  value: status.device.firmwareVersion.trim().isEmpty
                      ? 'Belum tercatat'
                      : status.device.firmwareVersion,
                ),
                const Divider(),
                _InfoRow(
                  label: 'Terakhir terlihat',
                  value: formatWibDateTime(
                    status.lastSeenAt ?? status.device.lastSeenAt,
                  ),
                ),
                const Divider(),
                _InfoRow(
                  label: 'Koordinat',
                  value: status.device.hasLocation
                      ? '${status.device.latitude!.toStringAsFixed(5)}, '
                            '${status.device.longitude!.toStringAsFixed(5)}'
                      : 'Belum diatur',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    if (!device.hasLocation) {
      return const SurfaceCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Center(child: Text('Lokasi belum diatur')),
        ),
      );
    }

    final point = LatLng(device.latitude!, device.longitude!);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: SizedBox(
          height: 220,
          child: Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 12,
                    minZoom: 4,
                    maxZoom: 18,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.firefreeforest',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 44,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_on_rounded,
                            size: 42,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.appSurface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    device.locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
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

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.events});

  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const SurfaceCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Center(child: Text('Belum ada aktivitas.')),
        ),
      );
    }

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.notifications_outlined,
                  size: 18,
                  color: AppColors.warning,
                ),
              ),
              title: Text(
                events[i].typeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${events[i].status.label} · ${relativeTime(events[i].triggeredAt ?? events[i].createdAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PumpAggregateSummary extends StatelessWidget {
  const _PumpAggregateSummary({required this.data});

  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    final raw = data?['points'];
    final points = raw is List
        ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : const <Map<String, dynamic>>[];
    final ratios = points
        .map((point) => (point['pump_on_ratio'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final average = ratios.isEmpty
        ? null
        : ratios.reduce((a, b) => a + b) / ratios.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.water_outlined, color: AppColors.primaryDark),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'POMPA AIR',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(letterSpacing: 1, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  average == null
                      ? 'Belum ada data ON'
                      : '${(average * 100).toStringAsFixed(0)}% rata-rata ON',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailData {
  const _DetailData({required this.status, required this.fireHistory});

  final DeviceStatus status;
  final List<TelemetryFire> fireHistory;
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.device,
    required this.fallbackDeviceId,
    required this.onBack,
    required this.canDelete,
    required this.canEdit,
    required this.onDelete,
    required this.onEdit,
  });

  final Device? device;
  final String fallbackDeviceId;
  final VoidCallback onBack;
  final bool canDelete;
  final bool canEdit;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final title = device?.displayName.isNotEmpty == true
        ? device!.displayName
        : fallbackDeviceId;
    final subtitle = device == null
        ? fallbackDeviceId
        : '${device!.deviceId} · ${device!.locationLabel}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Kembali',
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.appTextMuted),
                ),
              ],
            ),
          ),
          const ThemeQuickToggle(),
          if (canEdit || canDelete)
            PopupMenuButton<String>(
              tooltip: 'Aksi node',
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                if (canEdit)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Ubah node'),
                      ],
                    ),
                  ),
                if (canDelete)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.danger,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Hapus node',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

String _formatUptime(int seconds) {
  if (seconds <= 0) return '0 menit';
  final duration = Duration(seconds: seconds);
  if (duration.inDays > 0) {
    return '${duration.inDays} hari ${duration.inHours % 24} jam';
  }
  if (duration.inHours > 0) {
    return '${duration.inHours} jam ${duration.inMinutes % 60} menit';
  }
  return '${duration.inMinutes} menit';
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final offline = status.connection == DeviceConnection.offline;
    final risk = offline ? RiskLevel.unknown : status.riskLevel;
    final color = offline ? context.appTextMuted : risk.color;
    final background = offline
        ? context.appSurface
        : context.isDarkMode
        ? risk.darkSoftColor
        : risk.softColor;
    final flame = status.fire?.flameDetected == true;
    final label = offline
        ? 'Offline'
        : [risk.label, if (flame) 'Api terdeteksi'].join(' · ');
    final lastUpdate = status.lastTelemetryAt ?? status.lastSeenAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              Text(
                status.connection.label,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 10, color: context.appTextSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Pembaruan ${relativeTime(lastUpdate)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 10, color: context.appTextSecondary),
          ),
          if (status.connection == DeviceConnection.online) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Uptime ${_formatUptime(status.uptimeSeconds)}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 10, color: AppColors.success),
            ),
          ],
          if (!offline && status.hasTelemetry) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Telemetri terakhir ${formatWibTime(lastUpdate)} WIB',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 9, color: context.appTextMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelSmall),
        if (trailing != null)
          Text(
            trailing!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 10, color: context.appTextMuted),
          ),
      ],
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({
    required this.icon,
    required this.title,
    required this.caption,
    required this.value,
    required this.valueCaption,
    required this.valueColor,
  });

  final IconData icon;
  final String title;
  final String caption;
  final String value;
  final String valueCaption;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 19, color: context.appTextSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: 3),
                Text(
                  caption,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 9, color: context.appTextSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: valueColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                valueCaption,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 8.5, color: context.appTextMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.appTextSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.appTextPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartTimeLabels extends StatelessWidget {
  const _ChartTimeLabels({required this.readings});

  final List<TelemetryFire> readings;

  @override
  Widget build(BuildContext context) {
    final first = readings.first;
    final last = readings.last;
    final firstAt = first.recordedAt ?? first.receivedAt;
    final lastAt = last.recordedAt ?? last.receivedAt;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          formatWibTime(firstAt),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 9, color: context.appTextMuted),
        ),
        Text(
          formatWibTime(lastAt),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 9, color: context.appTextMuted),
        ),
      ],
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
