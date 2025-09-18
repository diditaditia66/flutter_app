import 'dart:convert';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';
import 'predict_data_screen.dart';
import 'upload_data_screen.dart';
import 'retrain_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await AuthService.instance.logout();
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _confirmAndClearDataset(BuildContext context) async {
    // Ganti currentUsername -> username
    final username = AuthService.instance.username;
    if (username == null || username.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi login tidak valid. Silakan login ulang.')),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    final passwordCtrl = TextEditingController();
    bool confirming = false;

    Future<void> doClear() async {
      try {
        // 1) Re-auth dengan username tersimpan + password input
        await AuthService.instance.login(username, passwordCtrl.text);

        // 2) Clear dataset
        final headers = await AuthService.instance.authHeaders();
        final resp = await AuthService.instance.post(
          '/dataset/clear',
          body: {'truncate': true},
          headers: headers,
        );

        final body = jsonDecode(resp.body);
        if (resp.statusCode == 200 && body['ok'] == true) {
          if (context.mounted) {
            Navigator.of(context).pop(); // tutup dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dataset berhasil dikosongkan')),
            );
          }
        } else {
          throw Exception(body['error'] ?? 'Gagal clear dataset');
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: !confirming,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text(
                'Konfirmasi Hapus Dataset',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Akun: $username',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tindakan ini akan MENGHAPUS seluruh data pada tabel dataset. '
                    'Langkah ini tidak bisa dibatalkan.\n\n'
                    'Masukkan password akun Anda untuk konfirmasi.',
                    style: TextStyle(color: Colors.white70, height: 1.3),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: confirming ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: confirming
                      ? null
                      : () async {
                          if (passwordCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Password wajib diisi')),
                            );
                            return;
                          }
                          setState(() => confirming = true);
                          try {
                            await doClear();
                          } finally {
                            setState(() => confirming = false);
                          }
                        },
                  child: confirming
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Saya paham, Hapus'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // === Tambahan: Ambil info model untuk ditampilkan metriknya ===
  Future<Map<String, dynamic>> _fetchModelInfo() async {
    final resp = await AuthService.instance.get('/model_info');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Background lama
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),

                // Predict
                _menuButton(
                  context,
                  label: 'Predict Data',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PredictDataScreen()),
                  ),
                ),
                const SizedBox(height: 16),

                // Upload
                _menuButton(
                  context,
                  label: 'Upload Dataset',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UploadDataScreen()),
                  ),
                ),
                const SizedBox(height: 16),

                // Retrain
                _menuButton(
                  context,
                  label: 'Retrain Model',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RetrainScreen()),
                  ),
                ),
                const SizedBox(height: 16),

                // Logout
                _menuButton(
                  context,
                  label: 'Logout',
                  onPressed: () => _logout(context),
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),

                // Clear Dataset (konfirmasi password + re-auth)
                _menuButton(
                  context,
                  label: 'Clear Dataset',
                  onPressed: () => _confirmAndClearDataset(context),
                  color: Colors.deepOrange,
                ),

                const SizedBox(height: 28),

                // === Seksi METRIK MODEL ===
                FutureBuilder<Map<String, dynamic>>(
                  future: _fetchModelInfo(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const _MetricsCard.loading();
                    }
                    if (snap.hasError) {
                      return _MetricsCard.error('Gagal memuat model info: ${snap.error}');
                    }
                    final data = snap.data ?? {};
                    final ok = data['ok'] == true;

                    // trained_at (epoch detik) -> DateTime
                    DateTime? trainedAt;
                    final ta = data['trained_at'];
                    if (ta is int) {
                      trainedAt = DateTime.fromMillisecondsSinceEpoch(ta * 1000, isUtc: true).toLocal();
                    }

                    final metrics = (data['metrics'] is Map<String, dynamic>)
                        ? (data['metrics'] as Map<String, dynamic>)
                        : <String, dynamic>{};

                    double? r2 = _asDouble(metrics['r2']);
                    double? mae = _asDouble(metrics['mae']);
                    double? rmse = _asDouble(metrics['rmse']);
                    double? mape = _asDouble(metrics['mape']);

                    return _MetricsCard(
                      ok: ok,
                      trainedAt: trainedAt,
                      r2: r2,
                      mae: mae,
                      rmse: rmse,
                      mape: mape,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Widget _menuButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
    Color color = Colors.black,
  }) {
    return SizedBox(
      width: 240,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

// ====== Widget kecil untuk kartu metrik ======
class _MetricsCard extends StatelessWidget {
  final bool ok;
  final DateTime? trainedAt;
  final double? r2;
  final double? mae;
  final double? rmse;
  final double? mape;

  const _MetricsCard({
    super.key,
    this.ok = false,
    this.trainedAt,
    this.r2,
    this.mae,
    this.rmse,
    this.mape,
  });

  const _MetricsCard.loading({super.key})
      : ok = false,
        trainedAt = null,
        r2 = null,
        mae = null,
        rmse = null,
        mape = null;

  const _MetricsCard.error(String _,
      {super.key})
      : ok = false,
        trainedAt = null,
        r2 = null,
        mae = null,
        rmse = null,
        mape = null;

  @override
  Widget build(BuildContext context) {
    final styleLabel = const TextStyle(color: Colors.white70, fontSize: 12);
    final styleValue = const TextStyle(color: Colors.white, fontWeight: FontWeight.w600);

    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.info_outline,
                  color: ok ? Colors.greenAccent : Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                'Model Info',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (trainedAt != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Trained At', style: styleLabel),
                Text('${trainedAt!.toLocal()}', style: styleValue),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Trained At', style: styleLabel),
                Text('-', style: styleValue),
              ],
            ),
          const Divider(color: Colors.white12, height: 16),

          _metricRow('R² (test)', r2, suffix: ''),
          const SizedBox(height: 4),
          _metricRow('MAE', mae, suffix: ''),
          const SizedBox(height: 4),
          _metricRow('RMSE', rmse, suffix: ''),
          const SizedBox(height: 4),
          _metricRow('MAPE', mape, suffix: '%'),
        ],
      ),
    );
  }

  Widget _metricRow(String label, double? value, {String suffix = ''}) {
    final styleLabel = const TextStyle(color: Colors.white70, fontSize: 12);
    final styleValue = const TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
    final text = (value == null) ? '-' : '${value.toStringAsFixed(2)}$suffix';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: styleLabel),
        Text(text, style: styleValue),
      ],
    );
  }
}
