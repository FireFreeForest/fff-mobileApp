import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/device_repository.dart';
import '../../data/provisioning_service.dart';
import '../../state/auth_controller.dart';
import 'location_picker_screen.dart';

class AddNodeScreen extends StatefulWidget {
  const AddNodeScreen({super.key});

  @override
  State<AddNodeScreen> createState() => _AddNodeScreenState();
}

class _AddNodeScreenState extends State<AddNodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _locationNameController = TextEditingController();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  LatLng? _location;
  bool _obscurePassword = true;
  bool _checking = false;
  bool _connected = false;
  bool _submitting = false;
  String? _connectionMessage;
  String? _error;

  @override
  void dispose() {
    _deviceIdController.dispose();
    _locationNameController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _connectionMessage = null;
    });

    try {
      final status = await context.read<ProvisioningService>().checkStatus();
      if (!mounted) return;
      setState(() {
        _checking = false;
        _connected = true;
        _connectionMessage = status.firmwareVersion.isEmpty
            ? 'Node terhubung dan siap dikonfigurasi.'
            : 'Node terhubung · firmware ${status.firmwareVersion}';
      });
    } on ProvisioningException catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _connected = false;
        _connectionMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _connected = false;
        _connectionMessage =
            'Node belum dapat dihubungi. Sambungkan ponsel ke WiFi FFF-Setup.';
      });
    }
  }

  Future<void> _pickLocation(FormFieldState<LatLng> field) async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(initialLocation: _location),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _location = result);
    field.didChange(result);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    var identityReady = false;
    final deviceId = _deviceIdController.text.trim();
    final locationName = _locationNameController.text.trim();
    final location = _location!;
    final deviceRepository = context.read<DeviceRepository>();
    final provisioningService = context.read<ProvisioningService>();

    try {
      try {
        await deviceRepository.createDevice(
          deviceId: deviceId,
          name: locationName,
          locationName: locationName,
          latitude: location.latitude,
          longitude: location.longitude,
        );
      } on ApiException catch (error) {
        if (!error.isConflict) rethrow;
      }
      identityReady = true;

      await provisioningService.provision(
        ssid: _ssidController.text.trim(),
        password: _passwordController.text,
        deviceId: deviceId,
        name: locationName,
        locationName: locationName,
        latitude: location.latitude,
        longitude: location.longitude,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.success,
              size: 40,
            ),
            title: const Text('Node siap disambungkan'),
            content: Text(
              '$deviceId akan berpindah ke WiFi lokasi. Node muncul di daftar '
              'setelah mengirim data pertama, biasanya dalam 60 detik.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Kembali ke daftar'),
              ),
            ],
          );
        },
      );

      if (mounted) context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = identityReady
            ? '${error.message} Identitas node sudah tersimpan; ulangi provisioning setelah terhubung ke FFF-Setup.'
            : error.message;
      });
    } on ProvisioningException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = identityReady
            ? '${error.message} Identitas node sudah tersimpan; ulangi provisioning setelah terhubung ke FFF-Setup.'
            : error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = identityReady
            ? 'Provisioning belum selesai. Identitas node sudah tersimpan; periksa koneksi FFF-Setup lalu coba lagi.'
            : 'Node belum dapat disambungkan. Periksa formulir dan koneksi FFF-Setup.';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 82,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tambah node',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 3),
            Text(
              'Sambungkan perangkat ESP8266 baru',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      body: !auth.canManageDevices
          ? const _NoAccess()
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                children: [
                  const _SectionTitle(
                    title: 'SEBELUM MENYAMBUNGKAN',
                    trailing: '3 langkah',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _SetupCard(
                    checking: _checking,
                    connected: _connected,
                    connectionMessage: _connectionMessage,
                    onCheck: _checkConnection,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _SectionTitle(title: 'IDENTITAS NODE'),
                  const SizedBox(height: AppSpacing.sm),
                  _FieldLabel(
                    label: 'ID perangkat',
                    helper: 'Gunakan ID pada stiker perangkat ESP8266.',
                    child: TextFormField(
                      controller: _deviceIdController,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9._-]'),
                        ),
                        LengthLimitingTextInputFormatter(64),
                      ],
                      decoration: const InputDecoration(
                        hintText: 'Contoh: ESP-XXXXXX',
                        prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'ID perangkat wajib diisi.';
                        if (!RegExp(r'^[A-Za-z0-9._-]{3,64}$').hasMatch(text)) {
                          return 'Gunakan 3–64 huruf, angka, titik, garis bawah, atau strip.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _FieldLabel(
                    label: 'Nama lokasi',
                    helper: 'Nama ini tampil pada daftar dan peta node.',
                    child: TextFormField(
                      controller: _locationNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Contoh: Pos pantau Sebangau',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                      validator: (value) {
                        if ((value?.trim() ?? '').isEmpty) {
                          return 'Nama lokasi wajib diisi.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FormField<LatLng>(
                    initialValue: _location,
                    validator: (_) => _location == null
                        ? 'Pilih titik lokasi node di peta.'
                        : null,
                    builder: (field) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel(
                            label: 'Koordinat lokasi',
                            child: InkWell(
                              onTap: () => _pickLocation(field),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusSm,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSm,
                                  ),
                                  border: Border.all(
                                    color: field.hasError
                                        ? AppColors.danger
                                        : AppColors.border,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.map_outlined,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        _location == null
                                            ? 'Pilih lokasi node di peta'
                                            : '${_location!.latitude.toStringAsFixed(6)}, '
                                                  '${_location!.longitude.toStringAsFixed(6)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: _location == null
                                                  ? AppColors.textMuted
                                                  : AppColors.textPrimary,
                                            ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppColors.textMuted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (field.hasError) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              field.errorText!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppColors.danger,
                                    fontSize: 10,
                                  ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _SectionTitle(
                    title: 'JARINGAN WIFI',
                    trailing: '2,4 GHz',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _FieldLabel(
                    label: 'Nama WiFi (SSID)',
                    child: TextFormField(
                      controller: _ssidController,
                      decoration: const InputDecoration(
                        hintText: 'Masukkan nama WiFi 2,4 GHz',
                        prefixIcon: Icon(Icons.wifi_rounded),
                      ),
                      validator: (value) {
                        if ((value?.trim() ?? '').isEmpty) {
                          return 'Nama WiFi wajib diisi.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _FieldLabel(
                    label: 'Kata sandi WiFi',
                    helper: 'Kosongkan jika jaringan terbuka. Gunakan WiFi 2,4 GHz; 5 GHz tidak didukung ESP8266.',
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Masukkan kata sandi WiFi',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Tampilkan kata sandi'
                              : 'Sembunyikan kata sandi',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.infoSoft,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Pastikan ponsel masih terhubung ke FFF-Setup. Setelah disimpan, node akan berpindah ke WiFi lokasi.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: Text(
                      _submitting ? 'Menyambungkan…' : 'Sambungkan node',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Tunggu hingga 60 detik. Node akan muncul di daftar setelah berhasil tersambung.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 9,
                      color: AppColors.textMuted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.checking,
    required this.connected,
    required this.connectionMessage,
    required this.onCheck,
  });

  final bool checking;
  final bool connected;
  final String? connectionMessage;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        children: [
          const _SetupStep(
            number: '1',
            title: 'Nyalakan ESP8266',
            detail: 'Hubungkan daya USB 5V. Tahan tombol FLASH 5 detik sampai lampu indikator berkedip.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SetupStep(
            number: '2',
            title: 'Hubungkan ponsel ke node',
            detail: 'Buka WiFi ponsel, lalu pilih FFF-Setup. Kembali ke aplikasi setelah tersambung.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SetupStep(
            number: '3',
            title: 'Atur WiFi & lokasi',
            detail: 'Isi data di bawah. Gunakan WiFi 2,4 GHz; jaringan 5 GHz tidak didukung ESP8266.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  connectionMessage ?? 'Belum memeriksa koneksi node.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: connected
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton.icon(
                onPressed: checking ? null : onCheck,
                icon: checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        connected
                            ? Icons.check_circle_outline_rounded
                            : Icons.wifi_find_rounded,
                        size: 16,
                      ),
                label: Text(connected ? 'Terhubung' : 'Cek koneksi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 23,
          height: 23,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.infoSoft,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(fontSize: 10, color: AppColors.primary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 12, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 9,
            letterSpacing: 0.8,
            color: AppColors.textSecondary,
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontSize: 10, color: AppColors.textMuted),
          ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.child, this.helper});

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 11, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[
          const SizedBox(height: 5),
          Text(
            helper!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 9,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.admin_panel_settings_outlined,
            size: 48,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Hanya admin yang dapat menambahkan node.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
