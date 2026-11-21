import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/user_repository.dart';
import '../../models/user.dart';
import '../../shared/widgets/app_header.dart';
import '../../state/auth_controller.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/surface_card.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _searchController = TextEditingController();
  List<User> _users = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context.read<UserRepository>().listUsers(
        page: 1,
        perPage: 20,
        query: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _users = result.items;
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
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
        _error = 'Daftar pengguna belum dapat dimuat.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await context.read<UserRepository>().listUsers(
        page: _page + 1,
        perPage: 20,
        query: _searchController.text,
      );
      if (!mounted) return;
      final ids = _users.map((user) => user.id).toSet();
      setState(() {
        _users = [
          ..._users,
          ...result.items.where((user) => !ids.contains(user.id)),
        ];
        _page = result.page;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = 'Pengguna berikutnya belum dapat dimuat.';
      });
    }
  }

  Future<void> _showEditor({User? user}) async {
    final currentUser = context.read<AuthController>().user;
    final result = await showModalBottomSheet<_UserEditResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UserEditor(
        user: user,
        isSelf: user != null && currentUser?.id == user.id,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final repository = context.read<UserRepository>();
      if (user == null) {
        await repository.createUser(
          email: result.email!,
          password: result.password!,
          name: result.name,
          role: result.role,
        );
      } else {
        await repository.updateUser(
          userId: user.id,
          name: result.name,
          role: result.role,
          isActive: result.isActive,
          password: result.password,
        );
      }
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _users.where((user) => user.isActive).length;
    final adminCount = _users
        .where((user) => user.role == UserRole.admin)
        .length;
    final petugasCount = _users
        .where((user) => user.role == UserRole.petugas)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola pengguna'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.sm),
            child: ThemeQuickToggle(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Tambah pengguna'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            96,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryDark.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tim monitoring',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Kelola akses operator dan viewer.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _UserStat(
                    value: '${_users.length}',
                    label: 'Pengguna',
                    icon: Icons.people_alt_outlined,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _UserStat(
                    value: '$activeCount',
                    label: 'Aktif',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _UserStat(
                    value: '$adminCount',
                    label: 'Admin',
                    icon: Icons.admin_panel_settings_outlined,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _searchController,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Cari nama atau email',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: context.appTextMuted,
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _load();
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_users.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  '${_users.length} pengguna · $petugasCount petugas',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Gagal memuat pengguna',
                message: _error!,
                action: FilledButton(
                  onPressed: _load,
                  child: const Text('Coba lagi'),
                ),
              )
            else if (_users.isEmpty)
              const EmptyState(
                icon: Icons.people_outline_rounded,
                title: 'Pengguna tidak ditemukan',
                message: 'Tambahkan pengguna baru atau ubah pencarian.',
              )
            else
              ..._users.map(
                (user) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      onTap: () => _showEditor(user: user),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _roleColor(user.role)
                                  .withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _initials(user.displayName),
                                style: TextStyle(
                                  color: _roleColor(user.role),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  user.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _roleColor(user.role)
                                      .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  user.role.label,
                                  style: TextStyle(
                                    color: _roleColor(user.role),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: user.isActive
                                          ? AppColors.success
                                          : context.appTextMuted,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    user.isActive ? 'Aktif' : 'Nonaktif',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: user.isActive
                                              ? AppColors.success
                                              : context.appTextMuted,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_hasMore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: OutlinedButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: _loadingMore
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Muat lebih banyak'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

Color _roleColor(UserRole role) {
  switch (role) {
    case UserRole.admin:
      return AppColors.primaryDark;
    case UserRole.petugas:
      return AppColors.success;
    case UserRole.viewer:
      return const Color(0xFF8AA39A);
  }
}

class _UserStat extends StatelessWidget {
  const _UserStat({
    required this.value,
    required this.label,
    required this.icon,
    this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.primary;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _UserEditResult {
  const _UserEditResult({
    this.email,
    this.password,
    required this.name,
    required this.role,
    required this.isActive,
  });

  final String? email;
  final String? password;
  final String name;
  final UserRole role;
  final bool isActive;
}

class _UserEditor extends StatefulWidget {
  const _UserEditor({this.user, this.isSelf = false});

  final User? user;
  final bool isSelf;

  @override
  State<_UserEditor> createState() => _UserEditorState();
}

class _UserEditorState extends State<_UserEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late UserRole _role;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user?.name);
    _email = TextEditingController(text: widget.user?.email);
    _password = TextEditingController();
    _role = widget.user?.role ?? UserRole.viewer;
    _isActive = widget.user?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: context.appBackground,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
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
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  widget.user == null ? 'Tambah pengguna' : 'Ubah pengguna',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                if (widget.user == null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) => value == null || !value.contains('@')
                        ? 'Email tidak valid'
                        : null,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: widget.user == null
                        ? 'Password'
                        : 'Password baru (opsional)',
                  ),
                  validator: (value) {
                    if (widget.user == null &&
                        (value == null || value.length < 8)) {
                      return 'Minimal 8 karakter';
                    }
                    if (value != null && value.isNotEmpty && value.length < 8) {
                      return 'Minimal 8 karakter';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Peran'),
                  items: UserRole.values
                      .map(
                        (role) => DropdownMenuItem(
                          value: role,
                          child: Text(role.label),
                        ),
                      )
                      .toList(),
                  onChanged: widget.isSelf
                      ? null
                      : (value) {
                          if (value != null) setState(() => _role = value);
                        },
                ),
                if (widget.user != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Akun aktif'),
                    subtitle: widget.isSelf
                        ? const Text(
                            'Akun sendiri tidak dapat dinonaktifkan dari sini.',
                          )
                        : null,
                    value: _isActive,
                    onChanged: widget.isSelf
                        ? null
                        : (value) => setState(() => _isActive = value),
                  ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: () {
                    if (!_formKey.currentState!.validate()) return;
                    Navigator.of(context).pop(
                      _UserEditResult(
                        email: widget.user == null ? _email.text : null,
                        password: _password.text,
                        name: _name.text,
                        role: _role,
                        isActive: _isActive,
                      ),
                    );
                  },
                  child: Text(widget.user == null ? 'Tambah' : 'Simpan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
