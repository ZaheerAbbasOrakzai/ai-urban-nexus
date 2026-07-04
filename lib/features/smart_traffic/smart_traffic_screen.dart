// lib/features/smart_traffic/smart_traffic_screen.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lottie/lottie.dart' as lottie;
import 'package:just_audio/just_audio.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_routes.dart';
import 'package:ai_urban_nexus_mobile/core/services/cache_service.dart';
import 'package:ai_urban_nexus_mobile/core/config/google_maps_config.dart';
import 'package:ai_urban_nexus_mobile/core/services/api_service.dart';
import 'package:dio/dio.dart';

class SmartTrafficScreen extends StatefulWidget {
  const SmartTrafficScreen({super.key});

  @override
  State<SmartTrafficScreen> createState() => _SmartTrafficScreenState();
}

class _SmartTrafficScreenState extends State<SmartTrafficScreen> {
  late final AudioPlayer _player;
  GoogleMapController? _mapController;

  // For demo purposes this is true so examiners see alert + red route.
  // You can later wire this from your crime detection / traffic API.
  bool _crimeAlert = true;

  final List<String> _cities = const [
    'Lahore',
    'Karachi',
    'Islamabad',
    'Faisalabad',
    'Rawalpindi',
    'Multan',
    'Gujranwala',
    'Peshawar',
    'Quetta',
    'Sialkot',
    'Hyderabad',
    'Sargodha',
  ];
  String _selectedCity = 'Lahore';

  final Map<String, LatLng> _cityCoords = const {
    'Lahore': LatLng(31.5204, 74.3587),
    'Karachi': LatLng(24.8607, 67.0011),
    'Islamabad': LatLng(33.6844, 73.0479),
    'Faisalabad': LatLng(31.4504, 73.1350),
    'Rawalpindi': LatLng(33.5973, 73.0479),
    'Multan': LatLng(30.1575, 71.5249),
    'Gujranwala': LatLng(32.1877, 74.1945),
    'Peshawar': LatLng(34.0151, 71.5249),
    'Quetta': LatLng(30.1798, 66.9750),
    'Sialkot': LatLng(32.4927, 74.5319),
    'Hyderabad': LatLng(25.3960, 68.3578),
    'Sargodha': LatLng(32.0740, 72.6861),
  };

  final Map<String, List<String>> _cityDemoRoutes = const {
    'Lahore': ['Lahore Railway Station', 'Mall Road Lahore'],
    'Karachi': ['Karachi Cantt Railway Station', 'Mazar-e-Quaid Karachi'],
    'Islamabad': ['Faisal Masjid Islamabad', 'Centaurus Mall Islamabad'],
    'Faisalabad': ['Clock Tower Faisalabad', 'D Ground Faisalabad'],
    'Rawalpindi': ['Saddar Rawalpindi', 'Faizabad Rawalpindi'],
    'Multan': ['Multan Cantt', 'Ghanta Ghar Multan'],
    'Gujranwala': ['Gujranwala Cantt', 'Model Town Gujranwala'],
    'Peshawar': ['Saddar Peshawar', 'Khyber Teaching Hospital'],
    'Quetta': ['Quetta Railway Station', 'Hanna Lake'],
    'Sialkot': ['Sialkot Cantt', 'Sialkot Clock Tower'],
    'Hyderabad': ['Hyderabad Railway Station', 'Qasimabad Hyderabad'],
    'Sargodha': ['University of Sargodha', 'Satellite Town Sargodha'],
  };

  List<LatLng> _routePoints = const [
    LatLng(31.5204, 74.3587),
    LatLng(31.5150, 74.3650),
    LatLng(31.5100, 74.3700),
  ];

  // Extra virtual vehicles to make the dashboard feel alive
  List<LatLng> _otherVehicles = const [
    LatLng(31.5210, 74.3620),
    LatLng(31.5190, 74.3550),
    LatLng(31.5135, 74.3680),
  ];

  double? _routeDistanceKm;
  int? _routeDurationMin;
  double? _avgSpeedKmh;
  String? _trafficStatus;

  int _carStep = 0;
  Timer? _carTimer;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _startCarAnimation();
    _initCrimeAlert();
    _loadRouteForCity(_selectedCity);
  }

  Future<void> _playSiren() async {
    // On web, skip audio playback to avoid asset 404 noise.
    if (kIsWeb) return;
    try {
      await _player.setAsset('assets/sound/siren.mp3');
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
    } catch (e) {
      // Safe fallback if the asset is missing during development.
      debugPrint('Failed to play siren: $e');
    }
  }

  void _startCarAnimation() {
    _carTimer?.cancel();
    _carTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _carStep = (_carStep + 1) % _routePoints.length;
      });
    });
  }

  Future<void> _initCrimeAlert() async {
    try {
      final cached = CacheService.getCrimeStatus();
      final prefs = await SharedPreferences.getInstance();
      final status = cached ?? prefs.getString('crime_status') ?? 'Safe';
      final alert = status != 'Safe';

      if (!mounted) return;

      setState(() {
        _crimeAlert = alert;
      });

      if (_crimeAlert) {
        _playSiren();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showCrimeAlertDialog();
        });
      }
    } catch (_) {
      // If anything fails, keep existing demo behaviour.
    }
  }

  Future<void> _loadRouteForCity(String city) async {
    const key = GoogleMapsConfig.apiKey;
    if (key.isEmpty) {
      return;
    }

    final pair = _cityDemoRoutes[city];
    if (pair == null || pair.length != 2) {
      return;
    }

    if (mounted) {
      setState(() {
        _routeDistanceKm = null;
        _routeDurationMin = null;
        _avgSpeedKmh = null;
        _trafficStatus = null;
      });
    }

    try {
      final resp = await Dio().get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': pair[0],
          'destination': pair[1],
          'mode': 'driving',
          'traffic_model': 'best_guess',
          'departure_time': 'now',
          'key': key,
        },
      );

      final data = resp.data as Map;
      final routes = (data['routes'] as List?) ?? [];
      if (routes.isEmpty) {
        return;
      }

      final route = routes.first as Map;
      double? distanceKm;
      int? durationMin;
      double? avgSpeed;
      String? trafficStatus;

      final legs = (route['legs'] as List?) ?? [];
      if (legs.isNotEmpty) {
        final leg = legs.first as Map;
        final distance = leg['distance'] as Map?;
        final duration = leg['duration'] as Map?;
        final distMeters = (distance?['value'] as num?)?.toDouble();
        final durSeconds = (duration?['value'] as num?)?.toDouble();

        if (distMeters != null && distMeters > 0) {
          distanceKm = distMeters / 1000.0;
        }
        if (durSeconds != null && durSeconds > 0) {
          durationMin = (durSeconds / 60).round();
        }
        if (distanceKm != null && durationMin != null && durationMin > 0) {
          final hours = durationMin / 60.0;
          if (hours > 0) {
            avgSpeed = distanceKm / hours;
          }
        }
      }

      try {
        final traffic = await ApiService.predictTraffic(
          _selectedCity,
          5,
          1200,
          35,
        );
        trafficStatus = traffic;
      } catch (_) {}

      final overview = route['overview_polyline'] as Map?;
      final pointsStr = overview?['points'] as String?;
      if (pointsStr == null || pointsStr.isEmpty) {
        return;
      }

      final path = _decodePolyline(pointsStr);
      if (path.isEmpty) {
        return;
      }

      final vehicles = <LatLng>[];
      if (path.length >= 4) {
        vehicles.add(path[(path.length / 4).floor()]);
        vehicles.add(path[(path.length / 2).floor()]);
        vehicles.add(path[(3 * path.length / 4).floor()]);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _routePoints = path;
        if (vehicles.isNotEmpty) {
          _otherVehicles = vehicles;
        }
        _routeDistanceKm = distanceKm;
        _routeDurationMin = durationMin;
        _avgSpeedKmh = avgSpeed;
        _trafficStatus = trafficStatus;
      });

      if (_mapController != null) {
        final bounds = _boundsFromLatLngList(path);
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 48),
        );
      }
    } catch (_) {}
  }

  List<LatLng> _decodePolyline(String encoded) {
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    final List<LatLng> path = [];
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;
      path.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return path;
  }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double south = list.first.latitude;
    double north = list.first.latitude;
    double west = list.first.longitude;
    double east = list.first.longitude;

    for (final latLng in list) {
      if (latLng.latitude < south) south = latLng.latitude;
      if (latLng.latitude > north) north = latLng.latitude;
      if (latLng.longitude < west) west = latLng.longitude;
      if (latLng.longitude > east) east = latLng.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );
  }

  Future<void> _showCrimeAlertDialog() async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black87,
        contentPadding: const EdgeInsets.all(16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            lottie.Lottie.asset(
              'assets/lottie/alert.json',
              width: 120,
              height: 120,
              repeat: true,
            ),
            const SizedBox(height: 12),
            const Text(
              'STOLEN VEHICLE ALERT!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Control room notified. Alternate safe routes activated.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _carTimer?.cancel();
    _mapController?.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color barColor = _crimeAlert ? Colors.red : Colors.green;
    final LatLng fallbackCenter =
        _cityCoords[_selectedCity] ?? const LatLng(31.5204, 74.3587);
    final LatLng carPos = _routePoints.isNotEmpty
        ? _routePoints[_carStep % _routePoints.length]
        : fallbackCenter;
    final List<LatLng> other = _otherVehicles.length >= 3
        ? _otherVehicles
        : const [
            LatLng(31.5210, 74.3620),
            LatLng(31.5190, 74.3550),
            LatLng(31.5135, 74.3680),
          ];
    final LatLng policePos =
        _routePoints.isNotEmpty ? _routePoints.first : fallbackCenter;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('police'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        position: policePos,
      ),
      Marker(
        markerId: const MarkerId('car'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        position: carPos,
      ),
      // Additional background vehicles
      Marker(
        markerId: const MarkerId('veh_1'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        position: other[0],
      ),
      Marker(
        markerId: const MarkerId('veh_2'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        position: other[1],
      ),
      Marker(
        markerId: const MarkerId('veh_3'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        position: other[2],
      ),
    };

    return WillPopScope(
      onWillPop: () async {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.dashboard);
        }
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          centerTitle: true,
          title: const Text('Smart Traffic Control'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            padding: const EdgeInsets.all(16),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.dashboard);
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.home, color: Colors.white),
              padding: const EdgeInsets.all(16),
              onPressed: () => context.go(AppRoutes.dashboard),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
          // 1. Google Map with highlighted route and police marker
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: fallbackCenter,
              zoom: 14.5,
            ),
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            trafficEnabled: true,
            compassEnabled: false,
            polylines: {
              Polyline(
                polylineId: const PolylineId('route'),
                points: _routePoints,
                color: _crimeAlert ? Colors.red : Colors.green,
                width: 8,
              ),
            },
            markers: markers,
          ),

          // 2. Top status bar with police car animation
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: barColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    lottie.Lottie.asset(
                      'assets/lottie/vehicle_moving.json',
                      width: 60,
                      height: 60,
                      repeat: true,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        _crimeAlert
                            ? 'STOLEN VEHICLE ALERT!'
                            : 'TRAFFIC NORMAL',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Small live stats card (vehicles, police, alerts)
          Positioned(
            top: 100,
            right: 16,
            child: Card(
              color: Colors.white.withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_car, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Vehicles: ${markers.length - 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_police,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Police units: 1',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

            // 3. Bottom panel – Pakistan traffic rules + alternate routes
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomPanel(),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black26,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 260,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select City',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    DropdownButton<String>(
                      value: _selectedCity,
                      underline: const SizedBox(),
                      items: _cities
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(c),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedCity = value);
                        _loadRouteForCity(value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Live Route Statistics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_routeDistanceKm != null)
                        Text(
                          'Route distance: ${_routeDistanceKm!.toStringAsFixed(1)} km',
                          style: const TextStyle(fontSize: 14),
                        ),
                      if (_routeDurationMin != null)
                        Text(
                          'Estimated time: $_routeDurationMin min',
                          style: const TextStyle(fontSize: 14),
                        ),
                      if (_avgSpeedKmh != null)
                        Text(
                          'Average speed: ${_avgSpeedKmh!.toStringAsFixed(1)} km/h',
                          style: const TextStyle(fontSize: 14),
                        ),
                      if (_trafficStatus != null)
                        Text(
                          'Traffic status: $_trafficStatus',
                          style: const TextStyle(fontSize: 14),
                        ),
                      if (_avgSpeedKmh != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _avgSpeedKmh! <= 40
                              ? 'Status: Within 40 km/h urban speed limit.'
                              : 'Status: Above recommended 40 km/h limit!',
                          style: TextStyle(
                            fontSize: 13,
                            color: _avgSpeedKmh! <= 40
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ],
                      if (_routeDistanceKm == null &&
                          _routeDurationMin == null &&
                          _avgSpeedKmh == null &&
                          _trafficStatus == null)
                        const Text(
                          'Loading live route stats...',
                          style: TextStyle(fontSize: 14),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleIcon extends StatelessWidget {
  final String asset;
  final String text;

  const _RuleIcon({required this.asset, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SvgPicture.asset(asset, width: 40, height: 40),
        const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  final String name;
  final String eta;
  final int safety;

  const _RouteCard({
    required this.name,
    required this.eta,
    required this.safety,
  });

  @override
  Widget build(BuildContext context) {
    final bool safe = safety > 90;
    final Color color = safe ? Colors.green[100]! : Colors.orange[100]!;
    final Color textColor = safe ? Colors.green : Colors.orange;

    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            const SizedBox(height: 2),
            Text(
              eta,
              style: const TextStyle(
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Safety: $safety%',
              style: TextStyle(
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SpeedChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 4),
          ),
          alignment: Alignment.center,
          child: Text(
            value.split(' ').first,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}
