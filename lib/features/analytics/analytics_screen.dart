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
import '../../data/dashboard_repository.dart';
import '../../data/device_repository.dart';
import '../../models/dashboard_summary.dart';
import '../../models/device.dart';
import '../../models/device_status.dart';
import '../../models/event.dart';
import '../../models/realtime_event.dart';
import '../../services/realtime_service.dart';
import '../../shared/widgets/app_header.dart';

const _smokeThreshold = 500;

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  _AnalyticsData? _data;
  bool _loading = true;
  String? _error;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;
  Timer? _realtimeRefreshTimer;

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
    _realtimeRefreshTimer?.cancel();
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (!mounted) return;

    if (event.type == RealtimeTypes.reconnected) {
      unawaited(_load(showSpinner: false));
      return;
    }

    final affectsAnalytics =
        event.isTelemetry ||
        event.isEvent ||
        event.type == RealtimeTypes.riskUpdated ||
        event.type == RealtimeTypes.deviceStatus;
    if (!affectsAnalytics) return;

    if (_realtimeRefreshTimer?.isActive ?? false) return;
    _realtimeRefreshTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        unawaited(_load(showSpinner: false));
      }
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
      final dashboardRepository = context.read<DashboardRepository>();
      final deviceRepository = context.read<DeviceRepository>();
      final results = await Future.wait<Object>([
        dashboardRepository.getSummary(),
        deviceRepository.listStatuses(),
      ]);

      final statuses = results[1] as List<DeviceStatus>;
      statuses.sort((a, b) {
        final aSmoke = a.fire?.smokeLevel ?? -1;
        final bSmoke = b.fire?.smokeLevel ?? -1;
        final smoke = bSmoke.compareTo(aSmoke);
        if (smoke != 0) return smoke;
        return a.device.deviceId.compareTo(b.device.deviceId);
      });

      if (!mounted) return;
      setState(() {
        _data = _AnalyticsData(
          summary: results[0] as DashboardSummary,
          statuses: statuses,
        );
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
        _error = 'Ringkasan analitik belum dapat dimuat.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

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
                  title: 'Analitik',
                  subtitle: 'Seluruh node · ${AppConfig.regionLabel}',
                ),
              ),
              if (_loading && data == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && data == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(message: _error!, onRetry: () => _load()),
                )
              else if (data != null) ...[
                if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: _InlineError(
                        message: _error!,
                        onRetry: () => _load(showSpinner: false),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(child: _MetricGrid(data: data)),
                SliverToBoxAdapter(child: _RiskDistribution(data: data)),
                SliverToBoxAdapter(
                  child: _NodeRanking(statuses: data.statuses),
                ),
                SliverToBoxAdapter(
                  child: _RecentEvents(
                    events: data.summary.recentEvents,
                    statuses: data.statuses,
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xxl),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsData {
  const _AnalyticsData({required this.summary, required this.statuses});

  final DashboardSummary summary;
  final List<DeviceStatus> statuses;

  List<DeviceStatus> get _withFire =>
      statuses.where((status) => status.fire != null).toList();

  int get onlineCount => statuses
      .where((status) => status.connection == DeviceConnection.online)
      .length;

  double? get averageSmoke {
    final readings = _withFire;
    if (readings.isEmpty) return null;
    final total = readings.fold<int>(
      0,
      (sum, status) => sum + (status.fire?.smokeLevel ?? 0),
    );
    return total / readings.length;
  }

  DeviceStatus? get highestSmoke => _withFire.isEmpty ? null : _withFire.first;

  int get aboveThreshold => _withFire
      .where((status) => (status.fire?.smokeLevel ?? 0) >= _smokeThreshold)
      .length;

  Map<RiskLevel, int> get riskCounts {
    final counts = <RiskLevel, int>{
      RiskLevel.normal: 0,
      RiskLevel.waspada: 0,
      RiskLevel.bahaya: 0,
      RiskLevel.darurat: 0,
      RiskLevel.unknown: 0,
    };
    for (final status in statuses) {
      counts[status.riskLevel] = (counts[status.riskLevel] ?? 0) + 1;
    }
    return counts;
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.data});

  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final average = data.averageSmoke;
    final highest = data.highestSmoke;
    final highestSmoke = highest?.fire?.smokeLevel;
    final hasStatuses = data.statuses.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisExtent: 104,
        children: [
          _MetricCard(
            icon: Icons.air_rounded,
            label: 'Rata-rata asap',
            value: average == null ? '—' : average.toStringAsFixed(0),
            unit: average == null ? null : 'ADC',
            caption: '${data.onlineCount} node online',
          ),
          _MetricCard(
            icon: Icons.trending_up_rounded,
            label: 'Nilai tertinggi',
            value: highestSmoke?.toString() ?? '—',
            unit: highestSmoke == null ? null : 'ADC',
            caption: highest == null
                ? 'Belum ada telemetri'
                : '${highest.device.deviceId} · ${highest.device.locationLabel}',
            color: AppColors.danger,
          ),
          _MetricCard(
            icon: Icons.warning_amber_rounded,
            label: 'Di atas ambang',
            value: hasStatuses
                ? '${data.aboveThreshold} / ${data.statuses.length}'
                : '—',
            caption: 'Ambang ≥ $_smokeThreshold ADC',
            color: data.aboveThreshold > 0
                ? AppColors.danger
                : context.appTextPrimary,
          ),
          _MetricCard(
            icon: Icons.notifications_active_outlined,
            label: 'Event aktif',
            value: data.summary.activeEvents.toString(),
            caption: _severityCaption(data.summary.activeEventsBySeverity),
            color: data.summary.activeEvents > 0
                ? AppColors.warning
                : context.appTextPrimary,
          ),
        ],
      ),
    );
  }

  String _severityCaption(Map<String, int> counts) {
    final critical = (counts['critical'] ?? 0) + (counts['error'] ?? 0);
    final warning = counts['warning'] ?? 0;
    if (critical == 0 && warning == 0) return 'Tidak ada peringatan';
    return '$critical bahaya · $warning waspada';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.unit,
    this.color = AppColors.textPrimary,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? unit;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final valueColor = color == AppColors.textPrimary
        ? context.appTextPrimary
        : color;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: context.appTextMuted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 10, color: context.appTextSecondary),
                ),
              ),
            ],
          ),
          const Spacer(),
          RichText(
            maxLines: 1,
            text: TextSpan(
              text: value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w400,
                color: valueColor,
              ),
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.appTextMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 8.5, color: context.appTextMuted),
          ),
        ],
      ),
    );
  }
}

class _RiskDistribution extends StatelessWidget {
  const _RiskDistribution({required this.data});

  final _AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final counts = data.riskCounts;
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    final visibleRisks = RiskLevel.values
        .where((risk) => (counts[risk] ?? 0) > 0)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'DISTRIBUSI RISIKO', trailing: '$total node'),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: context.appBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  child: SizedBox(
                    height: 8,
                    child: total == 0
                        ? ColoredBox(color: context.appBorder)
                        : Row(
                            children: [
                              for (final risk in visibleRisks)
                                Expanded(
                                  flex: counts[risk] ?? 0,
                                  child: ColoredBox(color: risk.color),
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final risk in visibleRisks)
                      _RiskLegend(risk: risk, count: counts[risk] ?? 0),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskLegend extends StatelessWidget {
  const _RiskLegend({required this.risk, required this.count});

  final RiskLevel risk;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 88),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: risk.softColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: risk.color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: risk.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${risk.label}  $count',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: risk.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeRanking extends StatelessWidget {
  const _NodeRanking({required this.statuses});

  final List<DeviceStatus> statuses;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'PERINGKAT NODE',
            trailing: 'Nilai asap terbaru',
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: statuses.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(child: Text('Belum ada node terpasang.')),
                  )
                : Column(
                    children: [
                      for (var index = 0; index < statuses.length; index++) ...[
                        if (index > 0) const Divider(height: 1, thickness: 0.5),
                        _RankingRow(rank: index + 1, status: statuses[index]),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.rank, required this.status});

  final int rank;
  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final smoke = status.fire?.smokeLevel;
    final fraction = smoke == null ? 0.0 : (smoke / 1023).clamp(0.0, 1.0);
    final color = smoke == null ? context.appTextMuted : status.riskLevel.color;

    return InkWell(
      onTap: () => context.push('/nodes/${status.device.deviceId}'),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                rank.toString().padLeft(2, '0'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 9, color: context.appTextMuted),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${status.device.deviceId} · ${status.device.locationLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                    child: SizedBox(
                      height: 3,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(color: context.appBorder),
                          ),
                          FractionallySizedBox(
                            widthFactor: fraction,
                            child: ColoredBox(color: color),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 42,
              child: Text(
                smoke?.toString() ?? '—',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w400, color: color),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 52,
              child: Text(
                status.riskLevel.label,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 8, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentEvents extends StatelessWidget {
  const _RecentEvents({required this.events, required this.statuses});

  final List<Event> events;
  final List<DeviceStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final deviceCodes = {
      for (final status in statuses) status.device.id: status.device.deviceId,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'KEJADIAN TERBARU',
            trailing: '5 terakhir',
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: events.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(child: Text('Belum ada kejadian terbaru.')),
                  )
                : Column(
                    children: [
                      for (var index = 0; index < events.length; index++) ...[
                        if (index > 0) const Divider(height: 1, thickness: 0.5),
                        _EventRow(
                          event: events[index],
                          deviceCode:
                              events[index].device?.deviceId ??
                              deviceCodes[events[index].deviceId] ??
                              events[index].deviceCode,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.deviceCode});

  final Event event;
  final String deviceCode;

  @override
  Widget build(BuildContext context) {
    final color = _eventColor(event.severity);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(_eventIcon(event.severity), size: 14, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.typeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.appTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$deviceCode · ${event.status.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 9.5, color: context.appTextMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                event.severity.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                relativeTime(event.triggeredAt ?? event.createdAt),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 8.5, color: context.appTextMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _eventColor(EventSeverity severity) {
    switch (severity) {
      case EventSeverity.critical:
        return AppColors.emergency;
      case EventSeverity.error:
        return AppColors.danger;
      case EventSeverity.warning:
        return AppColors.warning;
    }
  }

  IconData _eventIcon(EventSeverity severity) {
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(fontSize: 9, color: context.appTextSecondary),
        ),
        Text(
          trailing,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(fontSize: 9, color: context.appTextMuted),
        ),
      ],
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
