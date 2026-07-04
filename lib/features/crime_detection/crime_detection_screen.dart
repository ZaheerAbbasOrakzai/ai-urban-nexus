// lib/features/crime_detection/crime_detection_screen.dart
// Uint8List is re-exported via flutter/foundation
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_urban_nexus_mobile/core/config/app_routes.dart';
import 'package:ai_urban_nexus_mobile/core/config/api_endpoints.dart';
import 'package:ai_urban_nexus_mobile/core/services/api_service.dart';
import 'package:ai_urban_nexus_mobile/core/services/notification_service.dart';
import 'package:ai_urban_nexus_mobile/core/services/cache_service.dart';
import 'package:ai_urban_nexus_mobile/core/widgets/gradient_button.dart';
import 'package:ai_urban_nexus_mobile/core/utils/helpers.dart';
import 'package:ai_urban_nexus_mobile/models/alert_model.dart';
import 'package:ai_urban_nexus_mobile/features/notifications/alerts_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CrimeDetectionScreen extends StatefulWidget {
  const CrimeDetectionScreen({super.key});

  @override
  State<CrimeDetectionScreen> createState() => _CrimeDetectionScreenState();
}

class _CrimeDetectionScreenState extends State<CrimeDetectionScreen> {
  Uint8List? _imageBytes;
  String? _imagePath;
  bool _isLoading = false;
  String _result = "No detection yet";

  Future<void> _loadDemoImage() async {
    try {
      final resp = await Dio().get(
        'https://via.placeholder.com/800x500.png?text=Vehicle+Image',
        options: Options(responseType: ResponseType.bytes),
      );
      setState(() {
        _imageBytes = Uint8List.fromList(resp.data as List<int>);
        _result = "Demo image loaded. Tap Detect to scan.";
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load demo image')),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    if (kIsWeb && source == ImageSource.camera) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text("Camera capture is not supported on Web. Use Gallery.")),
        );
      }
      return;
    }
    final pickedFile = await picker.pickImage(source: source, imageQuality: 85);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imagePath = kIsWeb ? null : pickedFile.path;
        _result = "Image selected. Tap Detect to scan.";
      });
    }
  }

  Future<void> _detectStolenVehicle() async {
    if (_imageBytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select or load an image before detecting.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _result = "Detecting...";
    });

    try {
      Map<String, dynamic> data;
      if (!kIsWeb && _imagePath != null) {
        data = await ApiService.detectCrimeByPath(_imagePath!);
      } else {
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(_imageBytes!, filename: 'upload.jpg'),
        });
        data = await _postDetect(formData);
      }

      bool isStolen = false;
      String plate = 'Unknown';

      // Legacy format: { "is_stolen": ..., "license_plate": ... }
      if (data.containsKey('is_stolen')) {
        final dynamic stolenFlag = data['is_stolen'];
        isStolen = stolenFlag == true ||
            stolenFlag == 'true' ||
            stolenFlag == '1' ||
            stolenFlag == 1;
        if (data['license_plate'] is String &&
            (data['license_plate'] as String).isNotEmpty) {
          plate = data['license_plate'] as String;
        }
      }
      // Direct crime API sample: { "detected": true, ... }
      else if (data.containsKey('detected')) {
        final dynamic detectedFlag = data['detected'];
        isStolen = detectedFlag == true ||
            detectedFlag == 'true' ||
            detectedFlag == '1' ||
            detectedFlag == 1;
      }
      // Orchestrator format: { "crime_detection": { "detected": true, ... }, ... }
      else if (data['crime_detection'] is Map) {
        final cd = data['crime_detection'] as Map;
        final dynamic detectedFlag = cd['detected'];
        isStolen = detectedFlag == true ||
            detectedFlag == 'true' ||
            detectedFlag == '1' ||
            detectedFlag == 1;
      }

      setState(() {
        _result = isStolen
            ? "STOLEN VEHICLE DETECTED\nLicense Plate: $plate"
            : "Vehicle is NOT stolen\nLicense Plate: $plate";
      });

      // IF CRIME DETECTED → TRIGGER TRAFFIC CONGESTION AND UPDATE DASHBOARD STATUS
      if (isStolen) {
        try {
          await ApiService.predictTraffic("Lahore", 10, 2500, 10);
        } catch (_) {}
        await NotificationService.show(
          "CRIME ALERT",
          "Stolen vehicle detected! Route blocked.",
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('crime_status', 'Alert');
        await CacheService.setCrimeStatus('Alert');

        double? lat;
        double? lng;
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          lat = pos.latitude;
          lng = pos.longitude;
        } catch (_) {}

        // Also persist alert to Firebase Realtime Database
        await ApiService.saveCrimeAlert(
          plate: plate,
          city: 'Lahore',
          location: 'Unknown',
          latitude: lat,
          longitude: lng,
          imagePath: _imagePath,
        );

        // Log a traffic alert entry linked to this crime detection
        await ApiService.saveTrafficAlert(
          city: 'Lahore',
          junction: 10,
          level: 'Heavy Traffic',
          vehicles: 2500,
          triggeredBy: 'crime_detection',
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('crime_status', 'Safe');
        await CacheService.setCrimeStatus('Safe');
      }

      if (isStolen && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("ALERT: Stolen vehicle $plate reported!"),
            backgroundColor: Colors.red,
          ),
        );

        // Push a crime alert into the Alerts screen
        AlertsScreen.addAlert(
          AlertModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            type: AlertType.crime,
            title: "Stolen Vehicle Detected",
            message: "Vehicle $plate flagged as stolen by AI Crime Detector.",
            timestamp: DateTime.now(),
          ),
        );

        // If orchestrator also returned traffic_simulation information,
        // generate a traffic alert so control rooms can react.
        final dynamic sim = data['traffic_simulation'];
        if (sim is Map) {
          final msg = sim['message']?.toString() ??
              'Traffic reroute triggered successfully.';
          String fullMessage = msg;
          if (sim['affected_routes'] is List) {
            final routes = (sim['affected_routes'] as List)
                .map((e) => e.toString())
                .join(', ');
            if (routes.isNotEmpty) {
              fullMessage = '$msg Routes: $routes';
            }
          }

          AlertsScreen.addAlert(
            AlertModel(
              id: '${DateTime.now().millisecondsSinceEpoch}_t',
              type: AlertType.traffic,
              title: "Traffic Simulation Triggered",
              message: fullMessage,
              timestamp: DateTime.now(),
            ),
          );
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _result = "Detection failed. Try again.");

        final int? statusCode = e.response?.statusCode;
        String msg;
        if (statusCode != null) {
          msg = "Server error: $statusCode";
        } else if (e.message != null && e.message!.isNotEmpty) {
          msg = "Network error: ${e.message}";
        } else {
          msg =
              "Network error: Unable to reach the detection server. Please ensure the backend API is running and reachable from this device.";
        }

        Helpers.showErrorDialog(context, "Error", msg);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _result = "Unexpected error occurred.");
        Helpers.showErrorDialog(context, "Error", e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<Map<String, dynamic>> _postDetect(FormData formData) async {
    final dio = Dio();
    try {
      final response = await dio.post(
        ApiEndpoints.detectStolenVehicle,
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          sendTimeout: ApiEndpoints.connectTimeout,
          receiveTimeout: ApiEndpoints.receiveTimeout,
        ),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException {
      // Fallback to orchestrator endpoint
      final response = await dio.post(
        ApiEndpoints.orchestrateCrimeResponse,
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          sendTimeout: ApiEndpoints.connectTimeout,
          receiveTimeout: ApiEndpoints.receiveTimeout,
        ),
      );
      return Map<String, dynamic>.from(response.data as Map);
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
          title: const Text(
            "Pakistani Number Plate Detection",
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
                  children: [
                    const Text(
                      "Upload a Pakistani number plate image and tap Detect",
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 300,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: (_imageBytes == null)
                          ? const Center(
                              child: Text(
                                "No image selected",
                                style: TextStyle(fontSize: 18),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                _imageBytes!,
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text("Use Camera"),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo),
                            label: const Text("Pick from Gallery"),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _loadDemoImage,
                            icon: const Icon(Icons.image_search),
                            label: const Text("Load Demo Image"),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    GradientButton(
                      text: "Detect Stolen Vehicle",
                      onPressed: _detectStolenVehicle,
                      isLoading: _isLoading,
                    ),
                    const SizedBox(height: 30),
                    Card(
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _result,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _result.contains("STOLEN")
                                ? Colors.red
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
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
