import 'dart:html' as html;

String _findApiKey() {
  const envKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');
  if (envKey.isNotEmpty) return envKey;
  final el = html.document.querySelector('meta[name="google_maps_api_key"]');
  if (el is html.MetaElement) {
    final v = el.content ?? '';
    if (v.isNotEmpty) return v;
  }

  return '';
}

bool _isLoaded() {
  for (final s in html.document.querySelectorAll('script')) {
    final src = (s as html.ScriptElement).src ?? '';
    if (src.contains('maps.googleapis.com/maps/api/js')) return true;
  }
  return false;
}

void ensureGoogleMapsApiLoaded() {
  if (_isLoaded()) return;
  final key = _findApiKey();
  if (key.isEmpty) return;
  final script = html.ScriptElement();
  script.src = 'https://maps.googleapis.com/maps/api/js?key=$key';
  script.defer = true;
  html.document.head?.append(script);
}
