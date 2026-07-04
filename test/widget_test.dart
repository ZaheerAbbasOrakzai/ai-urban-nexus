// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Import your actual root widget from app.dart
import 'package:ai_urban_nexus_mobile/app.dart';

void main() {
  testWidgets('AI Urban Nexus launches successfully', (WidgetTester tester) async {
    // Use the real root widget
    await tester.pumpWidget(
      const ProviderScope(
        child: AiUrbanNexusApp(), // Now it's visible!
      ),
    );

    await tester.pumpAndSettle();

    // Verify app launched
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(AiUrbanNexusApp), findsOneWidget);

    // Optional: check for your app name
    expect(find.textContaining('AI Urban Nexus'), findsWidgets);
  });
}