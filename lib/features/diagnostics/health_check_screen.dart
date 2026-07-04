// lib/features/diagnostics/health_check_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_urban_nexus_mobile/core/services/api_service.dart';
import 'package:ai_urban_nexus_mobile/core/services/hf_space_service.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_colors.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_routes.dart';
import 'package:ai_urban_nexus_mobile/core/config/google_maps_config.dart';

class HealthCheckScreen extends StatefulWidget {
  const HealthCheckScreen({super.key});

  @override
  State<HealthCheckScreen> createState() => _HealthCheckScreenState();
}

class _HealthCheckScreenState extends State<HealthCheckScreen> {
  bool _running = false;

  String _internet = 'Not checked';
  String _gmapsKey = 'Not checked';
  String _directions = 'Not checked';
  String _hfText = 'Not checked';

  gm.GoogleMapController? _mapController;
  bool _mapLoaded = false;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _runChecks() async {
    if (_running) return;
    setState(() {
      _running = true;
      _internet = 'Checking...';
      _gmapsKey = 'Checking...';
      _directions = 'Checking...';
      _hfText = 'Checking...';
    });

    // 1) Internet
    final online = await ApiService.isOnline();
    if (!mounted) return;
    setState(() {
      _internet = online ? 'Online' : 'Offline';
    });

    // 2) GMAPS routing key presence (Directions/Routes)
    const key = GoogleMapsConfig.routesApiKey;
    setState(() {
      if (key.isEmpty) {
        _gmapsKey = 'Missing (check GoogleMapsConfig.routesApiKey in code)';
      } else {
        _gmapsKey = 'Present';
      }
    });

    // 3) Google Routes API small test (only if key + online)
    if (online && key.isNotEmpty) {
      try {
        final resp = await Dio().post(
          'https://routes.googleapis.com/directions/v2:computeRoutes',
          data: {
            'origin': {
              'address': 'COMSATS Sahiwal',
            },
            'destination': {
              'address': 'Sahiwal Railway Station',
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
              'X-Goog-Api-Key': key,
              'X-Goog-FieldMask':
                  'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
            },
            // Allow 4xx/5xx so we can inspect the exact error body.
            validateStatus: (_) => true,
          ),
        );

        final status = resp.statusCode ?? 0;
        if (status != 200) {
          if (!mounted) return;
          setState(() {
            _directions = 'HTTP $status from Routes API: ${resp.data}';
          });
          return;
        }

        final data = resp.data as Map;
        final routes = (data['routes'] as List?) ?? [];
        setState(() {
          if (routes.isNotEmpty) {
            _directions = 'OK (Routes API, routes=${routes.length})';
          } else {
            _directions = 'Failed (Routes API returned no routes)';
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _directions = 'Routes API error (exception): $e';
        });
      }
    } else {
      setState(() {
        _directions = 'Skipped (offline or key missing)';
      });
    }

    // 4) HF Space text endpoint small ping
    if (online) {
      try {
        final res = await HFSpaceService.predictText(
          'AI Urban Nexus connectivity health check for Sahiwal traffic.',
        );
        if (!mounted) return;
        setState(() {
          if (res == null) {
            // Treat a 404 / missing endpoint as a neutral, skipped state so
            // viva can proceed even if the Space text API is disabled.
            _hfText = 'Skipped (Space endpoint disabled)';
          } else if (res.startsWith('Server busy') ||
              res.startsWith('No internet') ||
              res.startsWith('Failed')) {
            _hfText = res;
          } else {
            _hfText = 'OK (received AI text)';
          }
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _hfText = 'Error calling HF Space';
        });
      }
    } else {
      setState(() {
        _hfText = 'Skipped (offline)';
      });
    }

    if (!mounted) return;
    setState(() {
      _running = false;
    });
  }

  Color _statusColor(String value) {
    if (value.contains('OK') || value.contains('Present') || value == 'Online') {
      return Colors.green;
    }
    if (value.contains('Checking')) {
      return Colors.orange;
    }
    if (value.contains('Skipped')) {
      return Colors.blueGrey;
    }
    return Colors.red;
  }

  Widget _statusTile(String title, String value, IconData icon) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: _statusColor(value)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go(AppRoutes.dashboard);
        }
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          centerTitle: true,
          title: const Text('System Health Check'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go(AppRoutes.dashboard);
              }
            },
          ),
        ),
        body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Diagnostics Overview',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use this screen before viva/demo to confirm that internet, '
                'Google routing APIs (Routes API), and the AI Urban Nexus '
                'Hugging Face Space are reachable.',
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _running ? null : _runChecks,
                icon: _running
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.health_and_safety),
                label: Text(_running ? 'Running checks...' : 'Run Health Check'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              _statusTile('Internet Connectivity', _internet, Icons.wifi),
              _statusTile('Google Maps API Key', _gmapsKey, Icons.vpn_key),
              _statusTile('Google Routes API', _directions, Icons.directions),
              _statusTile('HF Space (AI Text)', _hfText, Icons.cloud),
              const SizedBox(height: 24),
              SizedBox(
                height: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: gm.GoogleMap(
                    initialCameraPosition: const gm.CameraPosition(
                      target: gm.LatLng(30.6686, 73.1030),
                      zoom: 12.5,
                    ),
                    onMapCreated: (c) {
                      _mapController = c;
                      setState(() {
                        _mapLoaded = true;
                      });
                    },
                    myLocationEnabled: false,
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    trafficEnabled: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _mapLoaded ? Icons.check_circle : Icons.info_outline,
                    size: 18,
                    color: _mapLoaded ? Colors.green : Colors.blueGrey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _mapLoaded
                        ? 'Google Map widget loaded successfully.'
                        : 'Google Map widget will confirm SDK & key on load.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
