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
import '../../models/telemetry.dart';
import '../../services/realtime_service.dart';
import '../../services/realtime_updater.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/smoke_chart.dart';
import '../../shared/widgets/surface_card.dart';
import '../../state/auth_controller.dart';
import 'widgets/pump_control_card.dart';

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

      fireHistory.sort((a, b) => _readingTime(a).compareTo(_readingTime(b)));

      if (!mounted) return;
      setState(() {
        _data = _DetailData(status: status, fireHistory: fireHistory);
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
        _error = 'Detail node belum dapat dimuat.';
      });
    }
  }

  DateTime _readingTime(TelemetryFire reading) {
    return reading.recordedAt ??
        reading.receivedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _DetailHeader(
              device: data?.status.device,
              fallbackDeviceId: widget.deviceId,
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
                      : AppColors.textPrimary,
                ),
                const Divider(),
                _SensorRow(
                  icon: Icons.flare_outlined,
                  title: 'Level api',
                  caption: 'Nilai analog sensor api',
                  value: flameLevel == null ? '--' : '$flameLevel',
                  valueCaption: 'ADC',
                  valueColor: AppColors.textPrimary,
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
                      : AppColors.textPrimary,
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
                      : AppColors.textPrimary,
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
                      : AppColors.textPrimary,
                ),
                const Divider(),
                _SensorRow(
                  icon: Icons.grass_outlined,
                  title: 'Kelembapan tanah',
                  caption: 'Nilai mentah sensor tanah',
                  value: soil == null ? '--' : soil.toStringAsFixed(0),
                  valueCaption: 'Sensor tanah · ADC',
                  valueColor: AppColors.textPrimary,
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
                      : AppColors.textSecondary,
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
                      : AppColors.textSecondary,
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
                            : AppColors.textPrimary,
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
                      ?.copyWith(fontSize: 10, color: AppColors.textMuted),
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
  });

  final Device? device;
  final String fallbackDeviceId;
  final VoidCallback onBack;

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
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final offline = status.connection == DeviceConnection.offline;
    final risk = offline ? RiskLevel.unknown : status.riskLevel;
    final color = offline ? AppColors.textMuted : risk.color;
    final background = offline ? AppColors.surface : risk.softColor;
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
                    ?.copyWith(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Pembaruan ${relativeTime(lastUpdate)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 10, color: AppColors.textSecondary),
          ),
          if (!offline && status.hasTelemetry) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Telemetri terakhir ${formatWibTime(lastUpdate)} WIB',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontSize: 9, color: AppColors.textMuted),
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
                ?.copyWith(fontSize: 10, color: AppColors.textMuted),
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
          Icon(icon, size: 19, color: AppColors.textSecondary),
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
                      ?.copyWith(fontSize: 9, color: AppColors.textSecondary),
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
                    ?.copyWith(fontSize: 8.5, color: AppColors.textMuted),
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
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textPrimary),
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
              ?.copyWith(fontSize: 9, color: AppColors.textMuted),
        ),
        Text(
          formatWibTime(lastAt),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 9, color: AppColors.textMuted),
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
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Ulangi')),
        ],
      ),
    );
  }
}
