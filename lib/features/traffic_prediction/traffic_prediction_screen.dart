// lib/features/traffic_prediction/traffic_prediction_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_routes.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_colors.dart';
import 'package:ai_urban_nexus_mobile/core/services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:ai_urban_nexus_mobile/core/services/cache_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:dio/dio.dart';
import 'package:ai_urban_nexus_mobile/models/traffic_cognition_result.dart';
import 'package:ai_urban_nexus_mobile/core/config/google_maps_config.dart';

class TrafficPredictionScreen extends StatefulWidget {
  const TrafficPredictionScreen({super.key});

  @override
  State<TrafficPredictionScreen> createState() =>
      _TrafficPredictionScreenState();
}

class _TrafficPredictionScreenState extends State<TrafficPredictionScreen> {
  bool _isLoading = false;
  Map<String, dynamic> _result = {};
  Map<String, dynamic>? _lastFeatures;
  gm.GoogleMapController? _mapController;
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  Set<gm.Polyline> _polylines = {};
  String _routeInfo = '';

  // Use the full 12-city training set used by the backend models.
  final List<String> _cities = [
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

  String _selectedTime = 'Morning';
  String _selectedDay = 'Monday';

  final List<String> _times = [
    'Morning',
    'Afternoon',
    'Evening',
    'Night',
  ];

  final List<String> _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  final Map<String, gm.LatLng> _cityCoords = {
    'Lahore': const gm.LatLng(31.5204, 74.3587),
    'Karachi': const gm.LatLng(24.8607, 67.0011),
    'Islamabad': const gm.LatLng(33.6844, 73.0479),
    'Faisalabad': const gm.LatLng(31.4504, 73.1350),
    'Rawalpindi': const gm.LatLng(33.5973, 73.0479),
    'Multan': const gm.LatLng(30.1575, 71.5249),
    'Gujranwala': const gm.LatLng(32.1877, 74.1945),
    'Peshawar': const gm.LatLng(34.0151, 71.5249),
    'Quetta': const gm.LatLng(30.1798, 66.9750),
    'Sialkot': const gm.LatLng(32.4927, 74.5319),
    'Hyderabad': const gm.LatLng(25.3960, 68.3578),
    'Sargodha': const gm.LatLng(32.0740, 72.6861),
  };

  List<String> _routesForCity(String city) {
    switch (city) {
      case 'Karachi':
        return const [
          'Shahrah-e-Faisal',
          'MA Jinnah Road',
          'Korangi Expressway',
          'University Road',
        ];
      case 'Islamabad':
        return const [
          'Kashmir Highway',
          'Islamabad Expressway',
          'Islamabad Highway → Zero Point',
        ];
      case 'Rawalpindi':
        return const [
          'Murree Road',
          'Peshawar Road',
          'GT Road → Saddar',
        ];
      case 'Lahore':
      default:
        return const [
          'Mall Road → Jail Road',
          'Canal Bank Road',
          'DHA Phase 5 Link Road',
          'Ferozepur Road Bypass',
          'Liberty → Gulberg Route',
        ];
    }
  }

  Future<void> _predictTraffic() async {
    setState(() => _isLoading = true);

    final online = await ApiService.isOnline();
    if (!online) {
      final cached = CacheService.getTraffic();
      if (mounted) {
        setState(() => _isLoading = false);
        if (cached != null) {
          setState(() {
            _result = {
              'congestion_level': cached,
              'predicted_speed': '-',
              'delay_minutes': '-',
              'suggestion': 'Offline: showing last known status',
              'simulated_routes': _routesForCity(_selectedCity),
            };
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Offline: showing last known traffic prediction.')),
          );
        } else {
          setState(() {
            _result = {
              'error': true,
              'message': 'No internet connection.',
            };
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No internet connection.')),
          );
        }
      }
      return;
    }
    final nearbyRoutes = _routesForCity(_selectedCity);

    // Map time-of-day and day-of-week to realistic traffic features
    final bool isWeekend =
        _selectedDay == 'Saturday' || _selectedDay == 'Sunday';
    bool isPeakHour = false;
    int vehicles;
    double speed;
    double temperature;

    switch (_selectedTime) {
      case 'Morning':
        isPeakHour = !isWeekend;
        vehicles = isWeekend ? 900 : 2300;
        speed = isWeekend ? 40 : 22;
        temperature = 24;
        break;
      case 'Afternoon':
        isPeakHour = false;
        vehicles = isWeekend ? 1500 : 1700;
        speed = isWeekend ? 35 : 30;
        temperature = 34;
        break;
      case 'Evening':
        isPeakHour = !isWeekend;
        vehicles = isWeekend ? 1200 : 2400;
        speed = isWeekend ? 32 : 20;
        temperature = 30;
        break;
      case 'Night':
      default:
        isPeakHour = false;
        vehicles = isWeekend ? 700 : 900;
        speed = isWeekend ? 45 : 40;
        temperature = 26;
        break;
    }

    const int junctionId = 5;
    const bool accident = false;

    try {
      setState(() {
        _lastFeatures = {
          'city': _selectedCity,
          'junction': junctionId,
          'vehicles': vehicles,
          'speed': speed,
          'temperature': temperature,
          'isPeakHour': isPeakHour,
          'accident': accident,
          'timeOfDay': _selectedTime,
          'dayOfWeek': _selectedDay,
        };
      });

      final raw = await ApiService.predictTraffic(
        _selectedCity,
        junctionId,
        vehicles,
        speed,
        temperature: temperature,
        isPeakHour: isPeakHour,
        accident: accident,
      );

      Map<String, dynamic> data;
      if (raw == 'Retry later' || raw == 'No internet connection.') {
        data = {
          'error': true,
          'message': raw,
        };
      } else {
        data = _buildTrafficSummary(raw, nearbyRoutes, includeDelay: true);
      }

      final bool hasError =
          data['error'] == true || data.containsKey('error');
      if (!hasError) {
        final level = data['congestion_level']?.toString() ?? 'Unknown';
        await ApiService.saveTrafficAlert(
          city: _selectedCity,
          junction: junctionId,
          level: level,
          vehicles: vehicles,
          triggeredBy: 'traffic_prediction',
        );
        await CacheService.setTraffic(_selectedCity, level);
      }

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _result = data;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _result = {
          'error': 'No internet or server down',
        };
      });
    }
  }

  Future<void> _fetchSmartRoute() async {
    final messenger = ScaffoldMessenger.of(context);
    final destText = _destinationController.text.trim();
    if (destText.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please enter a destination for the route.')),
      );
      return;
    }

    const key = GoogleMapsConfig.apiKey;
    if (key.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Google Maps API key is not configured.')),
      );
      return;
    }

    if (!await ApiService.isOnline()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No internet connection.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _routeInfo = '';
    });

    try {
      final originText = _originController.text.trim();
      final origin = originText.isEmpty
          ? '${_cityCoords[_selectedCity]?.latitude},${_cityCoords[_selectedCity]?.longitude}'
          : originText;

      final resp = await Dio().get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': origin,
          'destination': destText,
          'mode': 'driving',
          'traffic_model': 'best_guess',
          'departure_time': 'now',
          'key': key,
        },
      );

      final data = resp.data as Map;
      final routes = (data['routes'] as List?) ?? [];
      if (routes.isEmpty) {
        setState(() {
          _routeInfo = 'No route found for this origin and destination.';
          _polylines = {};
        });
      } else {
        final route = routes.first as Map;
        final legs = (route['legs'] as List?) ?? [];
        if (legs.isNotEmpty) {
          final leg = legs.first as Map;
          final distanceText =
              ((leg['distance'] as Map?)?['text'] ?? '').toString();
          final durationText =
              ((leg['duration'] as Map?)?['text'] ?? '').toString();
          final inTrafficText =
              ((leg['duration_in_traffic'] as Map?)?['text'] ??
                      durationText)
                  .toString();

          _routeInfo =
              'Distance: $distanceText • Time: $durationText • In traffic: $inTrafficText';
        }

        final overview = route['overview_polyline'] as Map?;
        final pointsStr = overview?['points'] as String?;
        if (pointsStr != null && pointsStr.isNotEmpty) {
          final path = _decodePolyline(pointsStr);
          _polylines = {
            gm.Polyline(
              polylineId: const gm.PolylineId('smart_route'),
              color: Colors.blueAccent,
              width: 6,
              points: path,
            ),
          };

          if (path.isNotEmpty && _mapController != null) {
            final bounds = _boundsFromLatLngList(path);
            await _mapController!.animateCamera(
              gm.CameraUpdate.newLatLngBounds(bounds, 48),
            );
          }
        } else {
          _polylines = {};
        }

        // AI insights for this smart route using existing traffic model
        final contextRoutes = <String>[
          'Route: $origin → $destText',
          ..._routesForCity(_selectedCity),
        ];

        final raw = await ApiService.predictTraffic(
          _selectedCity,
          5,
          1200,
          35,
        );

        Map<String, dynamic> dataMap;
        if (raw == 'Retry later' || raw == 'No internet connection.') {
          dataMap = {
            'error': true,
            'message': raw,
          };
        } else {
          dataMap = _buildTrafficSummary(raw, contextRoutes);
        }

        final bool hasError =
            dataMap['error'] == true || dataMap.containsKey('error');
        if (!hasError) {
          final level = dataMap['congestion_level']?.toString() ?? 'Unknown';
          const int junctionId = 0;
          const int vehicles = 0;
          await ApiService.saveTrafficAlert(
            city: _selectedCity,
            junction: junctionId,
            level: level,
            vehicles: vehicles,
            triggeredBy: 'traffic_prediction_smart_route',
          );

          await CacheService.setTraffic(_selectedCity, level);
        }

        if (mounted) {
          setState(() {
            _result = dataMap;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _routeInfo = 'Failed to fetch route. Please try again.';
          _polylines = {};
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<gm.LatLng> _decodePolyline(String encoded) {
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    final List<gm.LatLng> path = [];
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
      path.add(gm.LatLng(lat / 1e5, lng / 1e5));
    }
    return path;
  }

  gm.LatLngBounds _boundsFromLatLngList(List<gm.LatLng> list) {
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

    return gm.LatLngBounds(
      southwest: gm.LatLng(south, west),
      northeast: gm.LatLng(north, east),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _predictTraffic();
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeFormatted = DateFormat('hh:mm a').format(now);
    final dateFormatted = DateFormat('EEEE, dd MMMM yyyy').format(now);

    final bool hasError =
        _result['error'] == true || _result.containsKey('error');
    final bool hasResult = _result.isNotEmpty && !hasError;
    final String congestionLevel =
        _result['congestion_level']?.toString() ?? 'Unknown';

    final List<dynamic> simulatedRoutesRaw =
        (_result['simulated_routes'] as List?) ?? const [];

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
          title: const Text(
            'Traffic Congestion Prediction',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
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
          elevation: 0,
        ),
        body: SafeArea(
        child: Stack(
          children: [
            // Full-screen Google Map with live traffic and smart route overlay
            Positioned.fill(
              child: gm.GoogleMap(
                initialCameraPosition: gm.CameraPosition(
                  target: _cityCoords[_selectedCity] ??
                      const gm.LatLng(31.5204, 74.3587),
                  zoom: 12,
                ),
                onMapCreated: (c) => _mapController = c,
                trafficEnabled: true,
                myLocationEnabled: false,
                polylines: _polylines,
                mapToolbarEnabled: false,
                zoomControlsEnabled: false,
              ),
            ),

            // Draggable bottom sheet with all controls and AI cards
            DraggableScrollableSheet(
              initialChildSize: 0.35,
              minChildSize: 0.2,
              maxChildSize: 0.85,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        child: ListView(
                          controller: scrollController,
                          children: [
                            // Grab handle
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin:
                                    const EdgeInsets.only(bottom: 12, top: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey[400],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),

                            // Current Time Card
                            Card(
                              elevation: 6,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    const Icon(Icons.access_time_filled,
                                        size: 50, color: Colors.indigo),
                                    const SizedBox(height: 10),
                                    Text(
                                      timeFormatted,
                                      style: const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      dateFormatted,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // City Selector
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Select City',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedCity,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
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
                                final target = _cityCoords[value];
                                if (target != null && _mapController != null) {
                                  _mapController!.animateCamera(
                                    gm.CameraUpdate.newCameraPosition(
                                      gm.CameraPosition(
                                          target: target, zoom: 12),
                                    ),
                                  );
                                }
                              },
                            ),

                            const SizedBox(height: 12),

                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Time of Day',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedTime,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              items: _times
                                  .map(
                                    (t) => DropdownMenuItem<String>(
                                      value: t,
                                      child: Text(t),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _selectedTime = value);
                              },
                            ),

                            const SizedBox(height: 12),

                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Day of Week',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedDay,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              items: _days
                                  .map(
                                    (d) => DropdownMenuItem<String>(
                                      value: d,
                                      child: Text(d),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _selectedDay = value);
                              },
                            ),

                            const SizedBox(height: 16),

                            // Origin & Destination Inputs
                            TextField(
                              controller: _originController,
                              decoration: const InputDecoration(
                                labelText: 'Origin (optional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _destinationController,
                              decoration: const InputDecoration(
                                labelText: 'Destination',
                                border: OutlineInputBorder(),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Predict Button (city-level congestion)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isLoading ? null : _predictTraffic,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 3,
                                        ),
                                      )
                                    : const Icon(Icons.analytics, size: 28),
                                label: Text(
                                  _isLoading
                                      ? 'Analyzing Traffic...'
                                      : 'Predict Traffic',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo.shade600,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Smart Route Button
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _isLoading ? null : _fetchSmartRoute,
                                icon: const Icon(Icons.alt_route),
                                label: const Text(
                                    'Get Smart Route & AI Insights'),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Result Card
                            if (hasResult)
                              Card(
                                elevation: 10,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                color:
                                    _getCongestionColor(congestionLevel),
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'TRAFFIC CONGESTION STATUS',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () {},
                                              style:
                                                  OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: const BorderSide(
                                                    color: Colors.white70),
                                              ),
                                              icon: const Icon(
                                                  Icons.info_outline),
                                              label: const Text(
                                                  'Required Details'),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () {},
                                              style:
                                                  OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: const BorderSide(
                                                    color: Colors.white70),
                                              ),
                                              icon: const Icon(
                                                  Icons.recommend_outlined),
                                              label: const Text(
                                                  'Recommended Details'),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 20),

                                      // Speed
                                      _buildInfoRow(
                                        Icons.speed,
                                        'Predicted Speed',
                                        '${_result["predicted_speed"]} km/h',
                                        Colors.white,
                                      ),

                                      _buildInfoRow(
                                        Icons.timer,
                                        'Predicted Delay',
                                        '${_result["delay_minutes"] ?? '-'} minutes',
                                        Colors.white,
                                      ),

                                      // Congestion Level
                                      _buildInfoRow(
                                        Icons.traffic,
                                        'Congestion Level',
                                        congestionLevel,
                                        Colors.white,
                                      ),

                                      // AI Suggestion
                                      _buildInfoRow(
                                        Icons.lightbulb,
                                        'AI Recommendation',
                                        _result['suggestion']?.toString() ??
                                            '-',
                                        Colors.white,
                                      ),

                                      const Divider(
                                          height: 40,
                                          color: Colors.white70),

                                      // Crime Alert Status
                                      if (congestionLevel == 'Heavy')
                                        const Column(
                                          children: [
                                            Icon(
                                                Icons
                                                    .warning_amber_rounded,
                                                size: 60,
                                                color: Colors.orange),
                                            SizedBox(height: 10),
                                            Text(
                                              'CRIME ALERT ACTIVE',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            Text(
                                              'Stolen vehicle detected – Alternate routes activated',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                            SizedBox(height: 15),
                                          ],
                                        ),

                                      if (simulatedRoutesRaw.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Recommended Safe Routes',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        for (final route in
                                            simulatedRoutesRaw)
                                          Padding(
                                            padding: const EdgeInsets
                                                .symmetric(vertical: 4),
                                            child: Row(
                                              children: [
                                                Icon(
                                                    Icons.directions_car,
                                                    color:
                                                        Colors.green[200]),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    route.toString(),
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),

                            if (hasResult) _buildCognitionTable(),

                            if (hasError)
                              Card(
                                color: Colors.red[50],
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    'Connection Error: ${_result["message"] ?? _result["details"] ?? _result["error"]}',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),

                            // Smart Route Info + AI Insights panel
                            if (_routeInfo.isNotEmpty || hasResult)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                margin:
                                    const EdgeInsets.only(bottom: 8, top: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey[900],
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Smart Route Info',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (_routeInfo.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _routeInfo,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                    if (hasResult) ...[
                                      const SizedBox(height: 8),
                                      const Text(
                                        'AI Insights',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _result['suggestion']
                                                ?.toString() ??
                                            '-',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _buildTrafficSummary(
      String raw, List<String> routes,
      {bool includeDelay = false}) {
    final cognition = TrafficCognitionResult.fromRawText(
      raw,
      routes,
      includeDelay: includeDelay,
    );
    return cognition.toMap();
  }

  Widget _buildCognitionTable() {
    final features = _lastFeatures;

    final List<DataRow> rows = [];

    if (features != null) {
      rows.addAll([
        _kvRow('City', features['city']?.toString() ?? _selectedCity),
        _kvRow('Time of day',
            features['timeOfDay']?.toString() ?? _selectedTime),
        _kvRow('Day of week',
            features['dayOfWeek']?.toString() ?? _selectedDay),
        _kvRow('Junction ID', features['junction']?.toString() ?? '-'),
        _kvRow('Vehicles count', features['vehicles']?.toString() ?? '-'),
        _kvRow('Input speed (km/h)', features['speed']?.toString() ?? '-'),
        _kvRow('Temperature (°C)',
            features['temperature']?.toString() ?? '-'),
        _kvRow('Peak hour',
            (features['isPeakHour'] == true) ? 'Yes' : 'No'),
        _kvRow('Accident',
            (features['accident'] == true) ? 'Yes' : 'No'),
      ]);
    }

    rows.addAll([
      _kvRow('Predicted congestion',
          _result['congestion_level']?.toString() ?? '-'),
      _kvRow('Predicted speed (km/h)',
          _result['predicted_speed']?.toString() ?? '-'),
      _kvRow('Predicted delay (min)',
          _result['delay_minutes']?.toString() ?? '-'),
      _kvRow('AI recommendation', _result['suggestion']?.toString() ?? '-'),
    ]);

    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(
              label: Text(
                'Parameter',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'Value',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          rows: rows,
        ),
      ),
    );
  }

  DataRow _kvRow(String key, String value) {
    return DataRow(
      cells: [
        DataCell(Text(key)),
        DataCell(Text(value)),
      ],
    );
  }

  Widget _buildInfoRow(
      IconData icon, String label, String value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor.withValues(alpha: 0.9),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCongestionColor(String level) {
    switch (level) {
      case 'Heavy':
      case 'High':
        return Colors.red.shade600;
      case 'Moderate':
      case 'Medium':
        return Colors.orange.shade600;
      case 'Light':
      case 'Low':
      default:
        return Colors.green.shade600;
    }
  }
}
