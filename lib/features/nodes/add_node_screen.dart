import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/device_repository.dart';
import '../../data/geocoding_repository.dart';
import '../../data/provisioning_service.dart';
import '../../models/device.dart';
import '../../state/auth_controller.dart';
import '../../shared/widgets/app_header.dart';
import 'location_picker_screen.dart';

class AddNodeScreen extends StatefulWidget {
  const AddNodeScreen({super.key});

  @override
  State<AddNodeScreen> createState() => _AddNodeScreenState();
}

class _AddNodeScreenState extends State<AddNodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _locationNameController = TextEditingController();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();

  LatLng? _location;
  Device? _createdDevice;
  bool _obscurePassword = true;
  bool _checking = false;
  bool _connected = false;
  bool _submitting = false;
  bool _geocoding = false;
  bool _geocodeFailed = false;
  bool _locationNameAutoFilled = false;
  bool _updatingLocationName = false;
  int _geocodeRequest = 0;
  String? _connectionMessage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locationNameController.addListener(_onLocationNameChanged);
  }

  void _onLocationNameChanged() {
    if (_updatingLocationName || !_locationNameAutoFilled) return;
    setState(() => _locationNameAutoFilled = false);
  }

  @override
  void dispose() {
    _locationNameController
      ..removeListener(_onLocationNameChanged)
      ..dispose();
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
    await _fillLocationName(result);
  }

  Future<void> _fillLocationName(LatLng location) async {
    final current = _locationNameController.text.trim();
    if (current.isNotEmpty && !_locationNameAutoFilled) return;

    final request = ++_geocodeRequest;
    setState(() {
      _geocoding = true;
      _geocodeFailed = false;
    });

    try {
      final label = await context.read<GeocodingRepository>().reverseLabel(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      if (!mounted || request != _geocodeRequest) return;
      final canReplace =
          _locationNameController.text.trim().isEmpty ||
          _locationNameAutoFilled;
      if (label == null) {
        setState(() => _geocodeFailed = true);
        return;
      }
      if (!canReplace) return;

      _updatingLocationName = true;
      _locationNameController.text = label;
      _locationNameController.selection = TextSelection.collapsed(
        offset: label.length,
      );
      _updatingLocationName = false;
      setState(() => _locationNameAutoFilled = true);
      _formKey.currentState?.validate();
    } catch (_) {
      if (!mounted || request != _geocodeRequest) return;
      setState(() => _geocodeFailed = true);
    } finally {
      if (mounted && request == _geocodeRequest) {
        setState(() => _geocoding = false);
      }
    }
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
    final locationName = _locationNameController.text.trim();
    final location = _location!;
    final deviceRepository = context.read<DeviceRepository>();
    final provisioningService = context.read<ProvisioningService>();

    try {
      var device = _createdDevice;
      if (device == null) {
        device = await deviceRepository.createDevice(
          name: locationName,
          locationName: locationName,
          latitude: location.latitude,
          longitude: location.longitude,
        );
        _createdDevice = device;
      } else {
        device = await deviceRepository.updateDevice(
          deviceId: device.deviceId,
          name: locationName,
          locationName: locationName,
          latitude: location.latitude,
          longitude: location.longitude,
        );
        _createdDevice = device;
      }
      identityReady = true;
      final deviceId = device.deviceId;

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
              '$deviceId akan berpindah ke WiFi lokasi. Node muncul '
              'di daftar setelah mengirim data pertama, biasanya dalam 60 detik.',
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
      appBar: AppBar(
        toolbarHeight: 82,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.sm),
            child: ThemeQuickToggle(),
          ),
        ],
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
                  ?.copyWith(color: context.appTextMuted),
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
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'ID perangkat dibuat otomatis oleh server saat node '
                            'disimpan. Tidak perlu mengetik ID dari stiker.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _FieldLabel(
                    label: 'Nama lokasi',
                    helper: _geocoding
                        ? 'Mengisi nama lokasi dari peta…'
                        : _geocodeFailed
                        ? 'Nama lokasi tidak ditemukan; isi manual.'
                        : 'Diisi otomatis dari peta; bisa diubah.',
                    child: TextFormField(
                      controller: _locationNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Contoh: Pos pantau Sebangau',
                        prefixIcon: const Icon(Icons.place_outlined),
                        suffixIcon: _geocoding
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
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
                                  color: context.appSurface,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSm,
                                  ),
                                  border: Border.all(
                                    color: field.hasError
                                        ? AppColors.danger
                                        : context.appBorder,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
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
                                                  ? context.appTextMuted
                                                  : context.appTextPrimary,
                                            ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: context.appTextMuted,
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
                        Icon(
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
                                  color: context.appTextSecondary,
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
                      color: context.appTextMuted,
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
        color: context.appSurface,
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
                        : context.appTextSecondary,
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
                    ?.copyWith(fontSize: 12, color: context.appTextPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: context.appTextSecondary,
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
            color: context.appTextSecondary,
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontSize: 10, color: context.appTextMuted),
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
              ?.copyWith(fontSize: 11, color: context.appTextPrimary),
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[
          const SizedBox(height: 5),
          Text(
            helper!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 9,
              color: context.appTextMuted,
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
          Icon(
            Icons.admin_panel_settings_outlined,
            size: 48,
            color: context.appTextMuted,
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
