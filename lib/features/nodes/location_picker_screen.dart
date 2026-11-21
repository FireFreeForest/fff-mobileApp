import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/app_header.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initialLocation});

  final LatLng? initialLocation;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _defaultCenter = LatLng(-2.2, 113.9);

  LatLng? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialLocation;
  }

  @override
  Widget build(BuildContext context) {
    final center = _selected ?? _defaultCenter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih lokasi node'),
        actions: [
          const ThemeQuickToggle(),
          TextButton(
            onPressed: _selected == null
                ? null
                : () => Navigator.of(context).pop(_selected),
            child: const Text('Simpan'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: _selected == null ? 6.5 : 12,
                minZoom: 4,
                maxZoom: 18,
                onTap: (_, point) => setState(() => _selected = point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.firefreeforest',
                ),
                if (_selected != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selected!,
                        width: 46,
                        height: 46,
                        alignment: Alignment.topCenter,
                        child: const Icon(
                          Icons.location_on_rounded,
                          size: 44,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                const SimpleAttributionWidget(
                  source: Text('OpenStreetMap contributors'),
                ),
              ],
            ),
          ),
          Positioned(
            left: AppSpacing.lg,
            top: AppSpacing.lg,
            right: AppSpacing.lg,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: context.appSurface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                'Ketuk peta untuk menempatkan titik lokasi node.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 10, color: context.appTextSecondary),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KOORDINAT NODE',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(fontSize: 9, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _selected == null
                          ? 'Belum ada titik dipilih'
                          : '${_selected!.latitude.toStringAsFixed(6)}, '
                                '${_selected!.longitude.toStringAsFixed(6)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: _selected == null
                          ? null
                          : () => Navigator.of(context).pop(_selected),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Gunakan lokasi ini'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
