// lib/features/dashboard/dashboard_screen.dart

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_colors.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_routes.dart';
import 'package:ai_urban_nexus_mobile/core/widgets/stat_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_urban_nexus_mobile/core/services/api_service.dart';
import 'package:ai_urban_nexus_mobile/core/services/hf_space_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ai_urban_nexus_mobile/core/services/auth_service.dart';
import 'package:ai_urban_nexus_mobile/models/user_model.dart';
import 'package:ai_urban_nexus_mobile/core/services/cache_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ai_urban_nexus_mobile/core/services/notification_service.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../map/map_screen.dart';
import '../route_planner/route_planner_screen.dart';
import '../smart_traffic/smart_traffic_screen.dart';
import '../notifications/alerts_screen.dart';
import '../crime_detection/crime_detection_screen.dart';
import '../energy/energy_forecast_screen.dart';
import '../profile/profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  // FIXED: Removed `static const` — these widgets are NOT const-constructible
  static final List<Widget> _screens = <Widget>[
    const _HomeTab(),
    const MapScreen(),
    const RoutePlannerScreen(),
    const SmartTrafficScreen(),
    const AlertsScreen(),
    const CrimeDetectionScreen(),
    const EnergyForecastScreen(),
    const ProfileScreen(), // Now works perfectly
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return false;
        }
        // Already on home tab: block back to avoid accidental app exit
        return false;
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: _screens,
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          backgroundColor: const Color(0xFF1E293B),
          elevation: 20,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded), label: "Home"),
            BottomNavigationBarItem(icon: Icon(Icons.map_rounded), label: "Map"),
            BottomNavigationBarItem(
                icon: Icon(Icons.route_rounded), label: "Routes"),
            BottomNavigationBarItem(
                icon: Icon(Icons.traffic_rounded), label: "Traffic"),
            BottomNavigationBarItem(
                icon: Icon(Icons.notifications_rounded), label: "Alerts"),
            BottomNavigationBarItem(
                icon: Icon(Icons.security_rounded), label: "Crime"),
            BottomNavigationBarItem(
                icon: Icon(Icons.bolt_rounded), label: "Energy"),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded), label: "Profile"),
          ],
        ),
      ),
    );
  }
}

// ────────────────────── Home Tab (Fully const-correct) ──────────────────────
class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final GlobalKey<_StatsGridState> _statsKey = GlobalKey<_StatsGridState>();

  bool isUrdu = false;

  int todayCrimeCount = 0;
  int todayTrafficDensity = 0;

  String cityMoodText = "";
  Color cityMoodColor = Colors.green;

  StreamSubscription<DatabaseEvent>? _crimeCountSub;
  StreamSubscription<DatabaseEvent>? _trafficDensitySub;

  @override
  void initState() {
    super.initState();

    final db = FirebaseDatabase.instance.ref();

    _crimeCountSub =
        db.child("crime_alerts_today/count").onValue.listen((event) {
      final value = event.snapshot.value;
      if (!mounted) return;
      if (value != null) {
        setState(() {
          todayCrimeCount = int.tryParse(value.toString()) ?? 0;
          _updateCityMood();
        });
      }
    });

    _trafficDensitySub =
        db.child("traffic/today_density").onValue.listen((event) {
      final value = event.snapshot.value;
      if (!mounted) return;
      if (value != null) {
        setState(() {
          todayTrafficDensity = int.tryParse(value.toString()) ?? 0;
          _updateCityMood();
        });
      }
    });

    _saveUserLogin();
    _updateCityMood();
  }

  void _updateCityMood() {
    if (todayCrimeCount > 8) {
      cityMoodText =
          isUrdu ? "آج شہر غصے میں ہے 😤" : "City is Angry Today 😤";
      cityMoodColor = Colors.red.shade700;
    } else if (todayTrafficDensity > 70) {
      cityMoodText =
          isUrdu ? "آج شہر تنگ ہے 😓" : "City is Frustrated Today 😓";
      cityMoodColor = Colors.orange.shade700;
    } else {
      cityMoodText =
          isUrdu ? "آج شہر خوش ہے 😊" : "City is Happy Today 😊";
      cityMoodColor = Colors.green.shade600;
    }
  }

  Future<void> _saveUserLogin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final loginRef =
        FirebaseDatabase.instance.ref("users/${user.uid}/last_login");

    await loginRef.set({
      "timestamp": ServerValue.timestamp,
      "email": user.email ?? "",
      "uid": user.uid,
    });
  }

  @override
  void dispose() {
    _crimeCountSub?.cancel();
    _trafficDensitySub?.cancel();
    super.dispose();
  }

  Future<void> _sendEmergencyNotification(String message) async {
    final numbers = ['+923367971778', '+923068369001'];
    // Open default SMS app with both numbers and prefilled body
    final smsUri = Uri(
      scheme: 'sms',
      path: numbers.join(','),
      queryParameters: {'body': message},
    );

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open SMS app.')),
      );
    }

    // Also try WhatsApp for each number (optional, if installed)
    for (final num in numbers) {
      final uri = Uri.parse(
        'whatsapp://send?phone=$num&text=${Uri.encodeComponent(message)}',
      );
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _testApi(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final online = await ApiService.isOnline();
      if (!online) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No internet connection. Space not reachable.'),
          ),
        );
        return;
      }

      final result = await HFSpaceService.predictText(
        'AI Urban Nexus health check for Lahore traffic and energy',
      );

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result ?? 'Space did not return a result.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to query AI Urban Nexus Space.'),
        ),
      );
    }
  }

  Future<void> _triggerSos(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    if (!await ApiService.isOnline()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No internet connection. SOS could not be sent.'),
        ),
      );
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('Location services are disabled. Enable GPS to send SOS.'),
        ),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(
          const SnackBar(
            content:
                Text('Location permission denied. Cannot send SOS.'),
          ),
        );
        return;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await ApiService.sendSosAlert(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      await NotificationService.show(
        'SOS EMERGENCY',
        'SOS alert sent with your current location.',
      );

      final message =
          'SOS Emergency from AI Urban Nexus\nLat: ${pos.latitude.toStringAsFixed(5)}, '
          'Lng: ${pos.longitude.toStringAsFixed(5)}';
      await _sendEmergencyNotification(message);

      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('SOS sent successfully.')),
      );
    } catch (_) {
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to send SOS. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Urban Nexus"),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  isUrdu = !isUrdu;
                  _updateCityMood();
                });
              },
              child: Chip(
                backgroundColor: Colors.blueGrey.shade900,
                label: Text(
                  isUrdu ? "EN" : "اردو",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: isUrdu ? "JameelNoori" : null,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.cloud),
            onPressed: () => context.go(AppRoutes.healthCheck),
            tooltip: "Test API",
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _statsKey.currentState?.reload(),
            tooltip: "Refresh",
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // TITLE PAGE (Exact same as your image)
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      "assets/images/comsats_logo.jpg",
                      height: 80,
                    ), // COMSATS logo
                    const SizedBox(height: 20),
                    const Text(
                      "COMSATS University Islamabad,\nSahiwal Campus",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "AI Urban Nexus",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "By\nZaheer Abbas\t\t\t\tCIIT/SP22-BCS-165/SWL\nImtiaz Hussain\t\t\tCIIT/SP22-BCS-171/SWL",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cityMoodColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: cityMoodColor.withOpacity(0.8),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cityMoodColor.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: 1.05,
                          duration: const Duration(seconds: 2),
                          curve: Curves.easeInOut,
                          child: Text(
                            cityMoodText.isEmpty
                                ? (isUrdu
                                    ? "آج شہر خوش ہے 😊"
                                    : "City is Happy Today 😊")
                                : cityMoodText,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontFamily: "JameelNoori",
                              fontWeight: FontWeight.bold,
                              color: cityMoodColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // MAIN DASHBOARD CARDS (ALL 4 APIs)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _card(
                    "Energy Forecast",
                    Icons.electric_bolt,
                    Colors.orange,
                    AppRoutes.energyForecast,
                  ),
                  _card(
                    "Traffic Prediction",
                    Icons.traffic,
                    Colors.red,
                    AppRoutes.trafficPrediction,
                  ),
                  _card(
                    "Crime Detection",
                    Icons.security,
                    Colors.purple,
                    AppRoutes.crimeDetection,
                  ),
                  _card(
                    "Safe Route Planner",
                    Icons.navigation,
                    Colors.green,
                    AppRoutes.routePlanner,
                  ),
                ],
              ),

              const SizedBox(height: 32),

              const Text(
                "Live Statistics",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _StatsGrid(key: _statsKey),

              const SizedBox(height: 32),

              const Text(
                "Quick Actions",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const _QuickActionsGrid(),

              const SizedBox(height: 24),
              const Center(
                child: Text(
                  "AI Urban Nexus © 2025 • COMSATS University Islamabad, Sahiwal",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.red.shade700,
        heroTag: null,
        onPressed: () => _triggerSos(context),
        label: const Text(
          "بھائی مدد کرو!",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: "JameelNoori",
            color: Colors.white,
          ),
        ),
        icon: const Icon(Icons.emergency, size: 32, color: Colors.white),
      ),
    );
  }

  Widget _card(
    String title,
    IconData icon,
    Color color,
    String route,
  ) {
    return GestureDetector(
      onTap: () => context.go(route),
      child: Card(
        elevation: 8,
        color: color.withOpacity(0.1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 50, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsGrid extends StatefulWidget {
  const _StatsGrid({super.key});

  @override
  State<_StatsGrid> createState() => _StatsGridState();
}

class _StatsGridState extends State<_StatsGrid> {
  String energy = "Loading...";
  String traffic = "Loading...";
  String crimeStatus = "Safe";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final bool online = await ApiService.isOnline();

    if (!online) {
      final energyCache = CacheService.getEnergy();
      final trafficCache = CacheService.getTraffic();
      final crimeCache = CacheService.getCrimeStatus();
      final prefs = await SharedPreferences.getInstance();
      final storedCrime =
          crimeCache ?? prefs.getString('crime_status') ?? 'Safe';

      if (!mounted) return;
      setState(() {
        energy = energyCache != null
            ? '${energyCache['value']} (cached)'
            : 'No internet connection.';
        traffic = trafficCache != null
            ? '$trafficCache (cached)'
            : 'No internet connection.';
        crimeStatus = storedCrime;
      });
      return;
    }

    // Use Sahiwal as the primary city context for dashboard summaries.
    final e = await ApiService.predictEnergy("Sahiwal");
    final t = await ApiService.predictTraffic("Sahiwal", 5, 1200, 35);
    final prefs = await SharedPreferences.getInstance();
    final storedCrime = prefs.getString('crime_status') ?? 'Safe';

    final nextDate = DateTime.now()
        .add(const Duration(days: 1))
        .toIso8601String()
        .split('T')
        .first;
    await CacheService.setEnergy("Sahiwal", e, nextDate);
    await CacheService.setTraffic("Sahiwal", t);
    await CacheService.setCrimeStatus(storedCrime);

    if (!mounted) return;
    setState(() {
      energy = e;
      traffic = t;
      crimeStatus = storedCrime;
    });
  }

  void reload() => _loadData();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final double aspect =
        width < 360 ? 0.75 : (width < 400 ? 0.85 : 0.9);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: aspect,
      children: [
        StatCard(
          title: "Energy Demand\nTomorrow",
          value: energy,
          icon: Icons.electric_bolt,
          color: Colors.orange,
          onTap: () => context.go(AppRoutes.energyForecast),
        ),
        StatCard(
          title: "Traffic Status",
          value: traffic,
          icon: Icons.traffic,
          color: traffic.contains("Jam") ? Colors.red : Colors.green,
          onTap: () => context.go(AppRoutes.trafficPrediction),
        ),
        StreamBuilder<DatabaseEvent>(
          stream: ApiService.getCrimeAlerts(),
          builder: (context, snapshot) {
            int activeCount = 0;
            if (snapshot.hasData) {
              activeCount = snapshot.data!.snapshot.children.length;
            }
            final displayValue = '$crimeStatus • $activeCount alerts';
            return StatCard(
              title: "Crime Alert",
              value: displayValue,
              icon: Icons.security,
              color: crimeStatus == "Safe" ? Colors.green : Colors.red,
              onTap: () => context.go(AppRoutes.crimeDetection),
            );
          },
        ),
        StatCard(
          title: "Safe Route\nPlanner",
          value: "Find Now",
          icon: Icons.navigation,
          color: Colors.blue,
          onTap: () => context.go(AppRoutes.routePlanner),
        ),
      ],
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: AuthService().getCurrentUser(),
      builder: (context, snapshot) {
        final role = snapshot.data?.role ?? UserRole.viewer;
        final bool showAdmin = role == UserRole.admin ||
            role == UserRole.securityLead ||
            role == UserRole.energyManager;

        final List<Widget> items = [
          const _QuickActionCard(
            title: "Live Map",
            description: "View real‑time traffic, vehicles and city routes.",
            icon: Icons.map_rounded,
            route: AppRoutes.map,
          ),
          const _QuickActionCard(
            title: "Route Planner",
            description:
                "Plan safest & fastest routes with time, distance, energy.",
            icon: Icons.route_rounded,
            route: AppRoutes.routePlanner,
          ),
          const _QuickActionCard(
            title: "Traffic Prediction",
            description: "AI model for live speed, congestion & suggestions.",
            icon: Icons.traffic_rounded,
            route: AppRoutes.trafficPrediction,
          ),
          const _QuickActionCard(
            title: "Smart Traffic",
            description: "Google Map, siren alert & Pakistan traffic rules.",
            icon: Icons.local_police_rounded,
            route: AppRoutes.smartTraffic,
          ),
          const _QuickActionCard(
            title: "Crime Detection",
            description: "Scan vehicles and detect stolen cars using AI.",
            icon: Icons.security_rounded,
            route: AppRoutes.crimeDetection,
          ),
          const _QuickActionCard(
            title: "Energy Forecast",
            description: "Predict next 24 hours city energy demand.",
            icon: Icons.bolt_rounded,
            route: AppRoutes.energyForecast,
          ),
        ];

        if (showAdmin) {
          items.add(const _QuickActionCard(
            title: "Admin Analytics",
            description: "View crime, traffic, energy & route KPIs.",
            icon: Icons.analytics_rounded,
            route: AppRoutes.adminAnalytics,
          ));
        }

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          // Slightly taller cards to avoid any vertical overflow on small screens
          childAspectRatio: 0.95,
          children: items,
        );
      },
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String route;

  const _QuickActionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(route),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
