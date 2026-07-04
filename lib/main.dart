// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/web/maps_loader.dart' if (dart.library.html) 'core/web/maps_loader_web.dart';

import 'package:ai_urban_nexus_mobile/core/services/notification_service.dart';
import 'package:ai_urban_nexus_mobile/core/services/cache_service.dart';
import 'package:ai_urban_nexus_mobile/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // This works on ALL platforms (Android, iOS, Web, Windows)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await CacheService.init();

  await NotificationService().init();

  ensureGoogleMapsApiLoaded();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    return true;
  };
  ErrorWidget.builder = (errorDetails) => const Material(
        color: Colors.white,
        child: Center(child: Text('An error occurred')),
      );

  runApp(
    const ProviderScope(
      child: AiUrbanNexusApp(),
    ),
  );
}
