class GoogleMapsConfig {
  // Provide keys at build/run time via Dart defines, for example:
  // flutter run --dart-define=GMAPS_API_KEY=your_key_here
  static const String apiKey = String.fromEnvironment('GMAPS_API_KEY');

  static const String routesApiKey =
      String.fromEnvironment('GMAPS_ROUTES_API_KEY');

  static const String placesApiKey =
      String.fromEnvironment('GMAPS_PLACES_API_KEY');

  static const String geocodingApiKey =
      String.fromEnvironment('GMAPS_GEOCODING_API_KEY');
}
