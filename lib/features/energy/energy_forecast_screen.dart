// lib/features/energy/energy_forecast_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_routes.dart';
import 'package:ai_urban_nexus_mobile/core/services/api_service.dart';
import 'package:ai_urban_nexus_mobile/core/services/cache_service.dart';
import 'package:fl_chart/fl_chart.dart';

class EnergyForecastScreen extends StatefulWidget {
  const EnergyForecastScreen({super.key});

  @override
  State<EnergyForecastScreen> createState() => _EnergyForecastScreenState();
}

class _EnergyForecastScreenState extends State<EnergyForecastScreen> {
  String? selectedCity;
  String result = "Select a city to see tomorrow's energy demand";
  String dateStr = "";
  String confidence = "";
  bool loading = false;
  List<FlSpot> chartData = [];

  final cities = [
    "Lahore",
    "Karachi",
    "Islamabad",
    "Faisalabad",
    "Rawalpindi",
    "Multan",
    "Peshawar",
    "Quetta",
    "Gujranwala",
    "Sialkot",
    "Hyderabad",
    "Sargodha",
  ];

  List<FlSpot> _buildChartData(String source) {
    final cleaned = source.replaceAll(',', '');
    final match = RegExp(r'(\d+\.?\d*)').firstMatch(cleaned);
    final base = double.tryParse(match?.group(1) ?? '') ?? 1000;

    final double h0 = base * 0.75;
    final double h4 = base * 0.85;
    final double h8 = base * 0.95;
    final double h12 = base * 1.1;
    final double h16 = base * 1.0;
    final double h20 = base * 0.9;
    final double h24 = base * 0.8;

    return [
      FlSpot(0, h0),
      FlSpot(4, h4),
      FlSpot(8, h8),
      FlSpot(12, h12),
      FlSpot(16, h16),
      FlSpot(20, h20),
      FlSpot(24, h24),
    ];
  }

  Future<void> fetchEnergy() async {
    if (selectedCity == null) return;
    final online = await ApiService.isOnline();
    if (!online) {
      final cached = CacheService.getEnergy();
      if (cached != null &&
          (cached['city']?.toString().isNotEmpty ?? false)) {
        if (!mounted) return;
        setState(() {
          result = cached['value'] ?? result;
          dateStr = cached['date'] ?? dateStr;
          confidence = result.contains('%') ? 'Model Confidence' : 'High';
          chartData = _buildChartData(result);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Offline: showing last known prediction.')),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet connection.')),
      );
      return;
    }
    setState(() => loading = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final res = await ApiService.predictEnergy(selectedCity!);
    final nextDate = DateTime.now()
        .add(const Duration(days: 1))
        .toIso8601String()
        .split('T')
        .first;
    if (!res.toLowerCase().contains('failed')) {
      await ApiService.saveEnergyForecast(
        city: selectedCity!,
        value: res,
        date: nextDate,
      );
      await CacheService.setEnergy(selectedCity!, res, nextDate);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    setState(() {
      loading = false;
      result = res;
      dateStr = nextDate;
      confidence = res.contains('%') ? 'Model Confidence' : 'High';
      chartData = _buildChartData(res);
    });
    if (res.toLowerCase().contains('failed')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Energy API error. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          title: const Text("Energy Forecasting"),
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
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Card(
                      elevation: 10,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(
                              "Select City",
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 20),
                            DropdownButton<String>(
                              isExpanded: true,
                              value: selectedCity,
                              hint: const Text("Choose City"),
                              items: cities
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => selectedCity = v),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: loading ? null : fetchEnergy,
                              style:
                                  Theme.of(context).elevatedButtonTheme.style,
                              child: loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      "Predict Tomorrow's Energy Demand"),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(25),
                        child: Column(
                          children: [
                            Text(
                              result,
                              style:
                                  Theme.of(context).textTheme.displayLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            if (dateStr.isNotEmpty)
                              Text(
                                "Date: $dateStr",
                                style:
                                    Theme.of(context).textTheme.bodyLarge,
                              ),
                            if (confidence.isNotEmpty)
                              Text(
                                "Confidence: $confidence",
                                style:
                                    Theme.of(context).textTheme.bodyMedium,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (chartData.isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            height: 260,
                            child: LineChart(
                              LineChartData(
                                gridData: FlGridData(show: true),
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 28,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          '${value.toInt()}h',
                                          style: const TextStyle(fontSize: 10),
                                        );
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 40,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          value.toInt().toString(),
                                          style: const TextStyle(fontSize: 10),
                                        );
                                      },
                                    ),
                                  ),
                                  topTitles: AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false),
                                  ),
                                  rightTitles: AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false),
                                  ),
                                ),
                                borderData: FlBorderData(show: true),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: chartData,
                                    isCurved: true,
                                    color: Colors.deepPurple,
                                    barWidth: 3,
                                    dotData: FlDotData(show: false),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Math, Physics & Chemistry Behind This',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '• Math: Simple time-series style curve over 24 hours based on tomorrow\'s forecast.',
                            ),
                            SizedBox(height: 4),
                            Text(
                              '• Physics: Joule\'s Law (E = P × t) links power demand and time to energy in MWh.',
                            ),
                            SizedBox(height: 4),
                            Text(
                              '• Chemistry: Fuel combustion efficiency in power plants affects how much fuel is burned to supply this demand.',
                            ),
                          ],
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
    );
  }
}
