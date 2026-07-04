import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_colors.dart';
import 'package:ai_urban_nexus_mobile/core/services/api_service.dart';

class AdminAnalyticsScreen extends StatelessWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Analytics'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'Realtime KPIs',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    _CrimeAnalyticsCard(),
                    const SizedBox(height: 12),
                    _TrafficAnalyticsCard(),
                    const SizedBox(height: 12),
                    _EnergyAnalyticsCard(),
                    const SizedBox(height: 12),
                    _SafeRoutesAnalyticsCard(),
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
}

class _CrimeAnalyticsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ApiService.getCrimeAlerts(),
      builder: (context, snapshot) {
        int total = 0;
        int stolen = 0;
        if (snapshot.hasData) {
          for (final child in snapshot.data!.snapshot.children) {
            total++;
            final value = child.value;
            if (value is Map &&
                (value['status']?.toString().toUpperCase() == 'STOLEN')) {
              stolen++;
            }
          }
        }
        final safe = total - stolen;
        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Crime Alerts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Total alerts: $total'),
                Text('Stolen vehicles: $stolen'),
                Text('Safe/cleared: $safe'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrafficAnalyticsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ApiService.getTrafficAlerts(),
      builder: (context, snapshot) {
        int total = 0;
        int heavy = 0;
        if (snapshot.hasData) {
          for (final child in snapshot.data!.snapshot.children) {
            total++;
            final value = child.value;
            if (value is Map) {
              final level = value['level']?.toString().toLowerCase() ?? '';
              if (level.contains('heavy')) {
                heavy++;
              }
            }
          }
        }
        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Traffic Alerts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Total alerts: $total'),
                Text('Heavy congestion: $heavy'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EnergyAnalyticsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('energy_predictions');
    return StreamBuilder<DatabaseEvent>(
      stream: ref.onValue,
      builder: (context, snapshot) {
        int total = 0;
        double lastMwh = 0;
        String lastCity = '-';
        if (snapshot.hasData) {
          for (final child in snapshot.data!.snapshot.children) {
            total++;
            final value = child.value;
            if (value is Map) {
              lastCity = value['city']?.toString() ?? lastCity;
              final num mwh = value['mwh'] as num? ?? 0;
              lastMwh = mwh.toDouble();
            }
          }
        }
        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Energy Predictions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Total predictions: $total'),
                Text('Last city: $lastCity'),
                Text('Last predicted load: ${lastMwh.toStringAsFixed(0)} MWh'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SafeRoutesAnalyticsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('safe_routes');
    return StreamBuilder<DatabaseEvent>(
      stream: ref.onValue,
      builder: (context, snapshot) {
        int total = 0;
        int low = 0;
        int medium = 0;
        int high = 0;
        if (snapshot.hasData) {
          for (final child in snapshot.data!.snapshot.children) {
            total++;
            final value = child.value;
            if (value is Map) {
              final risk = value['risk']?.toString().toLowerCase() ?? '';
              if (risk == 'low') low++;
              if (risk == 'medium') medium++;
              if (risk == 'high') high++;
            }
          }
        }
        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Safe Routes Logged',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Total routes: $total'),
                Text('Low risk: $low'),
                Text('Medium risk: $medium'),
                Text('High risk: $high'),
              ],
            ),
          ),
        );
      },
    );
  }
}
