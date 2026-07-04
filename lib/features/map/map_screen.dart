// lib/features/map/map_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_routes.dart';
import 'package:ai_urban_nexus_mobile/core/services/socket_service.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_colors.dart';
import 'package:ai_urban_nexus_mobile/models/route_model.dart';
import 'package:ai_urban_nexus_mobile/core/services/api_service.dart';
import 'package:ai_urban_nexus_mobile/core/config/google_maps_config.dart';
import 'package:url_launcher/url_launcher.dart';

class MapScreen extends ConsumerStatefulWidget {
  final AlternativeRoute? highlightedRoute;

  const MapScreen({super.key, this.highlightedRoute});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  gm.GoogleMapController? _mapController;
  late final SocketService _socketService;
  final Set<gm.Marker> _markers = {};
  final Set<gm.Polyline> _polylines = {};
  final Set<gm.Circle> _circles = {};
  StreamSubscription<DatabaseEvent>? _crimeSub;
  gm.CameraPosition _initialCamera = const gm.CameraPosition(
    target: gm.LatLng(31.5204, 74.3587),
    zoom: 12.5,
  );

  double _estimateEnergyKwh(AlternativeRoute r) {
    const double basePerKm = 0.18;
    final double safetyAdj = 1 - (r.safetyScore / 100) * 0.05;
    return (r.distanceKm * basePerKm * safetyAdj).clamp(0.1, 9.9);
  }

  Widget _metricPill(IconData icon, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _sendSos() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final online = await ApiService.isOnline();
      if (!online) {
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
            content: Text('Location services are disabled. Enable GPS to send SOS.'),
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
              content: Text('Location permission denied. Cannot send SOS.'),
            ),
          );
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await ApiService.sendSosAlert(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      messenger.showSnackBar(
        const SnackBar(content: Text('SOS alert sent from map.')),
      );

      final message =
          'SOS Emergency from AI Urban Nexus Live Map\nLat: ${pos.latitude.toStringAsFixed(5)}, '
          'Lng: ${pos.longitude.toStringAsFixed(5)}';
      await _sendEmergencyNotification(message);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to send SOS. Please try again.')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _socketService = ref.read(socketServiceProvider);
    _socketService.onVehiclesUpdate = (vehicles) {
      if (!mounted) return;
      _refreshOverlays();
    };
    _socketService.connect();
    _listenCrimeAlerts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupInitialOverlays();
    });
  }

  @override
  void dispose() {
    _crimeSub?.cancel();
    _socketService.disconnect();
    _mapController?.dispose();
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

  void _setupInitialOverlays() {
    final highlighted = widget.highlightedRoute;
    if (highlighted != null && highlighted.polyline.isNotEmpty) {
      final points = highlighted.polyline
          .map((p) => gm.LatLng(p.latitude, p.longitude))
          .toList();
      _polylines.add(gm.Polyline(
        polylineId: const gm.PolylineId('best_route'),
        points: points,
        color: AppColors.low,
        width: 5,
      ));
      _initialCamera = gm.CameraPosition(target: points.first, zoom: 14.0);
    }
    _refreshOverlays();
    _fetchTrafficMarkers();
  }

  Future<void> _fetchTrafficMarkers() async {
    try {
      final online = await ApiService.isOnline();
      if (!online) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No internet connection.')),
          );
        }
        return;
      }
      // Use Sahiwal context here since the highlighted campus route is in Sahiwal.
      final res = await ApiService.predictTraffic('Sahiwal', 5, 1200, 35);
      final level = res.toLowerCase();
      final isHigh = level.contains('high') || level.contains('critical');
      final isMedium = level.contains('moderate') || level.contains('medium');

      final markerColor = isHigh
          ? gm.BitmapDescriptor.defaultMarkerWithHue(0.0)
          : (isMedium
              ? gm.BitmapDescriptor.defaultMarkerWithHue(30.0)
              : gm.BitmapDescriptor.defaultMarker);

      // Junction near Sahiwal context (close to COMSATS Sahiwal campus)
      const junctionPos = gm.LatLng(30.6686, 73.1030);

      _markers.add(gm.Marker(
        markerId: const gm.MarkerId('junction_5'),
        position: junctionPos,
        infoWindow: gm.InfoWindow(title: 'Junction 5', snippet: res),
        icon: markerColor,
      ));

      _circles.removeWhere((c) => c.circleId.value == 'traffic_j5');
      _circles.add(gm.Circle(
        circleId: const gm.CircleId('traffic_j5'),
        center: junctionPos,
        radius: isHigh
            ? 400
            : isMedium
                ? 250
                : 150,
        strokeColor: isHigh
            ? AppColors.critical
            : isMedium
                ? AppColors.high
                : Colors.green,
        fillColor: (isHigh
                ? AppColors.critical
                : isMedium
                    ? AppColors.high
                    : Colors.green)
            .withValues(alpha: 0.15),
        strokeWidth: 2,
      ));

      setState(() {});
    } catch (_) {}
  }

  Future<void> _centerOnUser() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final current = gm.LatLng(pos.latitude, pos.longitude);

      _initialCamera = gm.CameraPosition(target: current, zoom: 13);
      if (_mapController != null) {
        await _mapController!.animateCamera(
          gm.CameraUpdate.newLatLngZoom(current, 13),
        );
      }
    } catch (_) {
      // Silent fail – user may deny permission
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
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;
      final p = gm.LatLng(lat / 1e5, lng / 1e5);
      path.add(p);
    }
    return path;
  }

  Future<List<gm.LatLng>> _getDirectionsPath(
      gm.LatLng origin, gm.LatLng destination) async {
    const key = GoogleMapsConfig.routesApiKey;
    if (key.isEmpty) {
      return [];
    }
    if (!await ApiService.isOnline()) {
      return [];
    }

    try {
      final resp = await Dio().post(
        'https://routes.googleapis.com/directions/v2:computeRoutes?key=$key',
        data: {
          'origin': {
            'location': {
              'latLng': {
                'latitude': origin.latitude,
                'longitude': origin.longitude,
              },
            },
          },
          'destination': {
            'location': {
              'latLng': {
                'latitude': destination.latitude,
                'longitude': destination.longitude,
              },
            },
          },
          'travelMode': 'DRIVE',
          'routingPreference': 'TRAFFIC_AWARE',
          'computeAlternativeRoutes': false,
          'languageCode': 'en-US',
          'units': 'METRIC',
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-FieldMask':
                'routes.polyline.encodedPolyline',
          },
        ),
      );

      final data = resp.data as Map;
      final routes = (data['routes'] as List?) ?? [];
      if (routes.isEmpty) {
        return [];
      }

      final route = routes.first as Map;
      final poly = route['polyline'] as Map?;
      final encoded = poly?['encodedPolyline'] as String?;
      if (encoded == null || encoded.isEmpty) {
        return [];
      }

      return _decodePolyline(encoded);
    } catch (e) {
      if (kDebugMode) {
        // Print the error in debug builds so we can see why the
        // Routes API call failed (e.g. 403, 400, key issues).
        // This keeps release builds clean while helping with setup.
        // ignore: avoid_print
        print('Routes API error in _getDirectionsPath: $e');
      }
      return [];
    }
  }

  void _refreshOverlays() {
    _markers.removeWhere((m) => m.markerId.value.startsWith('veh_'));
    _circles.removeWhere((c) => c.circleId.value.startsWith('crime_'));
    final vehicles = ref.read(socketServiceProvider).vehicles;
    for (final v in vehicles) {
      final pos = gm.LatLng(v.position.latitude, v.position.longitude);
      _markers.add(gm.Marker(
        markerId: gm.MarkerId('veh_${v.id}'),
        position: pos,
        infoWindow: gm.InfoWindow(
            title: v.displayName,
            snippet: '${v.speed.toStringAsFixed(0)} km/h'),
      ));
      if (v.isStolen) {
        _circles.add(gm.Circle(
          circleId: gm.CircleId('crime_${v.id}'),
          center: pos,
          radius: 120,
          strokeColor: AppColors.critical,
          fillColor: AppColors.critical.withValues(alpha: 0.12),
          strokeWidth: 2,
        ));
      }
    }
    setState(() {});
  }

  Future<void> _getLocationAndDrawRoute() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final current = gm.LatLng(pos.latitude, pos.longitude);
      // Destination: COMSATS University Islamabad, Sahiwal Campus
      const destination = gm.LatLng(30.6686, 73.1030);

      // Decide polyline color using traffic + crime risk
      var color = Colors.green;
      try {
        // Use Sahiwal context for this campus route.
        final res = await ApiService.predictTraffic('Sahiwal', 5, 1200, 35);
        final level = res.toLowerCase();
        if (level.contains('heavy') || level.contains('jam')) {
          color = Colors.red;
        } else if (level.contains('moderate') || level.contains('high')) {
          color = Colors.orange;
        }
      } catch (_) {}

      final vehicles = ref.read(socketServiceProvider).vehicles;
      final hasStolen = vehicles.any((v) => v.isStolen);
      if (hasStolen) {
        color = Colors.red;
      }

      const key = GoogleMapsConfig.apiKey;
      if (key.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Google Maps key is not configured. Please configure GoogleMapsConfig.apiKey or check the Health Check screen.'),
            ),
          );
        }
        return;
      }

      final online = await ApiService.isOnline();
      if (!online) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No internet connection. Cannot fetch real driving route.'),
            ),
          );
        }
        return;
      }

      var path = await _getDirectionsPath(current, destination);

      // If Google cannot provide a driving route even though the
      // key and internet are OK, fall back to a simple straight line
      // between the user and COMSATS so the viva/demo still shows a route.
      if (path.isEmpty) {
        path = [current, destination];
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Demo route shown (approximate path). Check the Health Check screen → Google Routes API tile for cloud status.'),
            ),
          );
        }
      }

      _polylines.removeWhere((p) => p.polylineId.value == 'user_route');
      _polylines.add(gm.Polyline(
        polylineId: const gm.PolylineId('user_route'),
        color: color,
        width: 8,
        points: path,
      ));

      _markers.removeWhere((m) => m.markerId.value == 'user_origin');
      _markers.removeWhere((m) => m.markerId.value == 'user_dest');
      _markers.add(gm.Marker(
        markerId: const gm.MarkerId('user_origin'),
        position: current,
        infoWindow: const gm.InfoWindow(title: 'Your Location'),
      ));
      _markers.add(gm.Marker(
        markerId: const gm.MarkerId('user_dest'),
        position: destination,
        infoWindow: const gm.InfoWindow(title: 'COMSATS Sahiwal'),
        icon: gm.BitmapDescriptor.defaultMarkerWithHue(
          gm.BitmapDescriptor.hueBlue,
        ),
      ));

      setState(() {});

      await _mapController?.animateCamera(
        gm.CameraUpdate.newLatLngZoom(current, 12),
      );
    } catch (_) {
      // Silent fail – location may be disabled or permission denied
    }
  }

  void _listenCrimeAlerts() {
    _crimeSub?.cancel();
    final ref = FirebaseDatabase.instance.ref('crime_alerts');
    _crimeSub = ref.onChildAdded.listen((event) {
      final v = event.snapshot.value;
      if (v is Map) {
        final plate = v['plate']?.toString() ?? 'UNKNOWN';
        final lat = (v['latitude'] as num?)?.toDouble();
        final lng = (v['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final pos = gm.LatLng(lat, lng);
          setState(() {
            final id = event.snapshot.key ?? 'crime_${lat}_$lng';
            final markerId = gm.MarkerId('crime_$id');
            final circleId = gm.CircleId('crime_$id');
            _markers.removeWhere((m) => m.markerId == markerId);
            _circles.removeWhere((c) => c.circleId == circleId);
            _markers.add(
              gm.Marker(
                markerId: markerId,
                position: pos,
                icon: gm.BitmapDescriptor.defaultMarkerWithHue(
                  gm.BitmapDescriptor.hueRed,
                ),
                infoWindow: gm.InfoWindow(
                  title: 'Crime Alert',
                  snippet: 'Stolen vehicle $plate',
                  onTap: () {
                    context.go(AppRoutes.alerts);
                  },
                ),
              ),
            );
            _circles.add(
              gm.Circle(
                circleId: circleId,
                center: pos,
                radius: 150,
                strokeColor: AppColors.critical,
                fillColor: AppColors.critical.withValues(alpha: 0.12),
                strokeWidth: 2,
              ),
            );
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vehicles = ref.watch(socketServiceProvider).vehicles;
    final highlighted = widget.highlightedRoute;

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
          title: const Text('Live Traffic Map'),
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
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.home, color: Colors.white),
              padding: const EdgeInsets.all(16),
              onPressed: () => context.go(AppRoutes.dashboard),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
          gm.GoogleMap(
            initialCameraPosition: _initialCamera,
            onMapCreated: (c) {
              _mapController = c;
              _centerOnUser();
            },
            myLocationEnabled: true,
            trafficEnabled: true,
            markers: _markers,
            polylines: _polylines,
            circles: _circles,
            mapToolbarEnabled: false,
            compassEnabled: true,
          ),
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                color: Colors.white.withValues(alpha: 0.95),
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
                            'Vehicles: ${vehicles.length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_police,
                              size: 16, color: AppColors.critical),
                          const SizedBox(width: 4),
                          Text(
                            'Stolen: ${vehicles.where((v) => v.isStolen).length}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                color: Colors.white.withValues(alpha: 0.9),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _LegendDot(color: AppColors.critical),
                          const SizedBox(width: 4),
                          const Text('High Risk'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _LegendDot(color: AppColors.high),
                          const SizedBox(width: 4),
                          const Text('Medium Risk'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _LegendDot(color: Colors.green),
                          const SizedBox(width: 4),
                          const Text('Low Risk'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (highlighted != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  color: Colors.white.withValues(alpha: 0.97),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        _metricPill(Icons.access_time,
                            "${highlighted.durationMin} min"),
                        _metricPill(Icons.straighten,
                            "${highlighted.distanceKm.toStringAsFixed(1)} km"),
                        _metricPill(Icons.battery_charging_full,
                            "${_estimateEnergyKwh(highlighted).toStringAsFixed(2)} kWh"),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: null,
            backgroundColor: AppColors.primary,
            onPressed: _getLocationAndDrawRoute,
            child: const Icon(Icons.navigation),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: null,
            backgroundColor: AppColors.critical,
            icon: const Icon(Icons.sos, color: Colors.white),
            label: const Text(
              'SOS',
              style: TextStyle(color: Colors.white),
            ),
            onPressed: _sendSos,
          ),
        ],
      ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;

  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
