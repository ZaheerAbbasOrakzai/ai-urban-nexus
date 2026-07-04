// lib/app.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/config/app_theme.dart';
import 'core/config/app_routes.dart';
import 'core/services/auth_service.dart';
import 'models/user_model.dart';

import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/map/map_screen.dart';
import 'features/route_planner/route_planner_screen.dart';
import 'models/route_model.dart';
import 'features/notifications/alerts_screen.dart';
import 'features/crime_detection/crime_detection_screen.dart';
import 'features/energy/energy_forecast_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/traffic_prediction/traffic_prediction_screen.dart';
import 'features/smart_traffic/smart_traffic_screen.dart';
import 'features/admin/admin_analytics_screen.dart';
import 'features/diagnostics/health_check_screen.dart';

class AiUrbanNexusApp extends StatelessWidget {
  const AiUrbanNexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    final GoRouter router = GoRouter(
      initialLocation: AppRoutes.splash,
      debugLogDiagnostics: true,
      routes: [
        GoRoute(
            path: AppRoutes.splash,
            name: AppRoutes.splash,
            builder: (_, __) => const SplashScreen()),
        GoRoute(
            path: AppRoutes.login,
            name: AppRoutes.login,
            builder: (_, __) => const LoginScreen()),
        GoRoute(
            path: AppRoutes.register,
            name: AppRoutes.register,
            builder: (_, __) => const RegisterScreen()),
        GoRoute(
            path: AppRoutes.dashboard,
            name: AppRoutes.dashboard,
            builder: (_, __) => const DashboardScreen()),
        GoRoute(
          path: AppRoutes.map,
          name: AppRoutes.map,
          builder: (_, state) {
            final extra = state.extra;
            return MapScreen(
              highlightedRoute:
                  extra is AlternativeRoute ? extra : null,
            );
          },
        ),
        GoRoute(
            path: AppRoutes.routePlanner,
            name: AppRoutes.routePlanner,
            builder: (_, __) => const RoutePlannerScreen()),
        GoRoute(
            path: AppRoutes.smartTraffic,
            name: AppRoutes.smartTraffic,
            builder: (_, __) => const SmartTrafficScreen()),
        GoRoute(
            path: AppRoutes.trafficPrediction,
            name: AppRoutes.trafficPrediction,
            builder: (_, __) => const TrafficPredictionScreen()),
        GoRoute(
            path: AppRoutes.alerts,
            name: AppRoutes.alerts,
            builder: (_, __) => const AlertsScreen()),
        GoRoute(
            path: AppRoutes.crimeDetection,
            name: AppRoutes.crimeDetection,
            builder: (_, __) => const CrimeDetectionScreen()),
        GoRoute(
            path: AppRoutes.energyForecast,
            name: AppRoutes.energyForecast,
            builder: (_, __) => const EnergyForecastScreen()),
        GoRoute(
            path: AppRoutes.profile,
            name: AppRoutes.profile,
            builder: (_, __) => const ProfileScreen()),
        GoRoute(
            path: AppRoutes.adminAnalytics,
            name: AppRoutes.adminAnalytics,
            builder: (_, __) => const AdminAnalyticsScreen()),
        GoRoute(
            path: AppRoutes.healthCheck,
            name: AppRoutes.healthCheck,
            builder: (_, __) => const HealthCheckScreen()),
      ],
      redirect: (context, state) async {
        final String path = state.uri.path;
        final bool isAuthFlow = path == AppRoutes.login ||
            path == AppRoutes.register ||
            path == AppRoutes.splash;

        // Check persisted auth state
        final bool isLoggedIn = await AuthService().isLoggedIn();
        final user = isLoggedIn ? await AuthService().getCurrentUser() : null;

        if (!isLoggedIn && !isAuthFlow) {
          return AppRoutes.login;
        }
        if (isLoggedIn &&
            (path == AppRoutes.login || path == AppRoutes.register)) {
          return AppRoutes.dashboard;
        }

        if (path == AppRoutes.adminAnalytics) {
          final role = user?.role;
          final bool allowed = role == UserRole.admin ||
              role == UserRole.securityLead ||
              role == UserRole.energyManager;
          if (!allowed) {
            return AppRoutes.dashboard;
          }
        }
        return null;
      },
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Text('404 - Page not found: ${state.uri}'),
        ),
      ),
    );

    return MaterialApp.router(
      title: 'AI Urban Nexus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
