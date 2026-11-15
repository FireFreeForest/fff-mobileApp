import 'package:go_router/go_router.dart';

import '../features/analytics/analytics_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/history/history_screen.dart';
import '../features/nodes/add_node_screen.dart';
import '../features/nodes/node_detail_screen.dart';
import '../features/nodes/nodes_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/status/status_screen.dart';
import '../state/auth_controller.dart';

GoRouter createRouter(AuthController authController) {
  return GoRouter(
    initialLocation: '/status',
    refreshListenable: authController,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isLogin = location == '/login';
      final isSplash = location == '/splash';

      switch (authController.status) {
        case AuthStatus.unknown:
          return isSplash ? null : '/splash';
        case AuthStatus.unauthenticated:
          return isLogin ? null : '/login';
        case AuthStatus.authenticated:
          if (isLogin || isSplash) {
            return '/status';
          }
          return null;
      }
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) {
          return AppShell(location: state.uri.path, child: child);
        },
        routes: [
          GoRoute(
            path: '/status',
            builder: (context, state) => const StatusScreen(),
          ),
          GoRoute(
            path: '/nodes',
            builder: (context, state) => const NodesScreen(),
          ),
          GoRoute(
            path: '/analytics',
            builder: (context, state) => const AnalyticsScreen(),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/nodes/add',
        builder: (context, state) => const AddNodeScreen(),
      ),
      GoRoute(
        path: '/nodes/:deviceId',
        builder: (context, state) {
          return NodeDetailScreen(
            deviceId: state.pathParameters['deviceId'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
