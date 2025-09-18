// ==== API base URL ====
// Diisi dari --dart-define API_BASE_URL saat build.
// Fallback ke https://api.diditserver.my.id agar tetap jalan di dev.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.diditserver.my.id',
);

// ==== Endpoint helper yang dipakai screen lain ====
// Tipe Uri supaya langsung bisa dipakai http.post/get Flutter.
final Uri predictUri = Uri.parse('$apiBaseUrl/predict');
final Uri retrainUri = Uri.parse('$apiBaseUrl/retrain');

// (Untuk upload + SSE, UploadDataScreen membangun URL manual dari apiBaseUrl:)
/// POST $apiBaseUrl/upload_async
/// SSE  $apiBaseUrl/upload/stream?job_id=...
