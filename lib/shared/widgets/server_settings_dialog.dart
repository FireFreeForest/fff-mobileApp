import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/server_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

class ServerSettingsDialog extends StatefulWidget {
  const ServerSettingsDialog({super.key, required this.currentUrl});

  final String currentUrl;

  @override
  State<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  late final TextEditingController _controller;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final normalized = ServerConfig.normalize(_controller.text);
      await context.read<ApiClient>().probeHealth(normalized);
      if (!mounted) return;
      Navigator.of(context).pop(normalized);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = error.message;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Server tidak dapat dihubungi. Periksa alamat dan jaringan.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Server backend'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Alamat API Fire Free Forest. Koneksi diuji ke /healthz sebelum disimpan.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.appTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              enabled: !_checking,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              onSubmitted: (_) {
                if (!_checking) _save();
              },
              decoration: const InputDecoration(
                labelText: 'Alamat server',
                hintText: 'http://192.168.1.12:8080',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.danger,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _checking ? null : _save,
          child: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Tes & simpan'),
        ),
      ],
    );
  }
}
