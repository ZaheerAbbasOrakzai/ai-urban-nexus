// lib/features/notifications/alerts_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_colors.dart';
import 'package:ai_urban_nexus_mobile/models/alert_model.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_routes.dart';
import 'package:firebase_database/firebase_database.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  static final List<AlertModel> _alerts = [];

  static void addAlert(AlertModel alert) {
    _alerts.insert(0, alert);
  }

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  DatabaseReference get _ref => FirebaseDatabase.instance.ref('crime_alerts');

  StreamSubscription<DatabaseEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _ref.onChildAdded.listen((event) {
      final v = event.snapshot.value;
      if (v is Map) {
        final plate = v['plate']?.toString() ?? 'UNKNOWN';
        final city = v['city']?.toString() ?? 'Unknown';
        final ts = v['timestamp']?.toString();
        final when = ts != null
            ? DateTime.tryParse(ts) ?? DateTime.now()
            : DateTime.now();
        AlertsScreen.addAlert(
          AlertModel(
            id: event.snapshot.key ?? when.millisecondsSinceEpoch.toString(),
            type: AlertType.crime,
            title: 'Stolen Vehicle Detected',
            message: 'Vehicle $plate flagged in $city',
            timestamp: when,
          ),
        );
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = AlertsScreen._alerts;
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
          elevation: 0,
          centerTitle: true,
          title: const Text("Alerts & Notifications"),
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
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: alerts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          "No alerts at the moment",
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        children: [
                          for (final alert in alerts)
                            Card(
                              margin:
                                  const EdgeInsets.symmetric(vertical: 8),
                              elevation: 6,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  radius: 30,
                                  backgroundColor: alert.color.withValues(
                                      alpha:
                                          0.15), // Fixed deprecated withOpacity
                                  child: Icon(
                                    alert.icon,
                                    color: alert.color,
                                    size: 32,
                                  ),
                                ),
                                title: Text(
                                  alert.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 6),
                                    Text(
                                      alert.message,
                                      style:
                                          const TextStyle(fontSize: 14),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _formatTime(alert.timestamp),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: TextButton.icon(
                                  onPressed: () {
                                    if (alert.type == AlertType.crime ||
                                        alert.type == AlertType.traffic) {
                                      context.go(AppRoutes.map);
                                    } else {
                                      context.go(AppRoutes.dashboard);
                                    }
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                  ),
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  label: const Text('Open'),
                                ),
                              ),
                            ),
                        ],
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final alertDay = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final difference = today.difference(alertDay).inDays;

    if (difference == 0) {
      final hour = dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = dateTime.hour >= 12 ? 'PM' : 'AM';
      return "Today at $hour:$minute $period";
    } else if (difference == 1) {
      return "Yesterday at ${_formatHour(dateTime)}";
    } else {
      return "${dateTime.day}/${dateTime.month}/${dateTime.year}";
    }
  }

  String _formatHour(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return "$hour:$minute $period";
  }
}
