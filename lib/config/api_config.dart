const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  // Untuk Android emulator: pakai 10.0.2.2
  // Untuk device nyata: override lewat --dart-define saat run/build
  defaultValue: 'http://10.0.2.2:5000',
);
