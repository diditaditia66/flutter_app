// lib/screens/predict_data_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart'; // gunakan base URL: apiBaseUrl
import '../services/auth_service.dart'; // <<-- tambah: untuk auth header & auto-refresh

class PredictDataScreen extends StatefulWidget {
  const PredictDataScreen({super.key});
  @override
  State<PredictDataScreen> createState() => _PredictDataScreenState();
}

class _PredictDataScreenState extends State<PredictDataScreen> {
  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _predDate;
  TimeOfDay? _predTime;

  final _mwController = TextEditingController();
  final _mvarController = TextEditingController();

  String? _prediction;
  String? _error;
  bool _loading = false;

  // ---------- pickers ----------
  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _predDate = picked;
        }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 0, minute: 0),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _predTime = picked;
        }
      });
    }
  }

  String _formatTime(TimeOfDay tod) {
    final h = tod.hour.toString().padLeft(2, '0');
    final m = tod.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: const Color(0xFF1C1C1C),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  // ---------- predict ----------
  Future<void> _predict() async {
    // Validasi input UI
    if (_startDate == null ||
        _startTime == null ||
        _predDate == null ||
        _predTime == null ||
        _mwController.text.isEmpty ||
        _mvarController.text.isEmpty) {
      setState(() => _error = "Semua input wajib diisi.");
      return;
    }

    final mw = double.tryParse(_mwController.text);
    final mvar = double.tryParse(_mvarController.text);
    if (mw == null || mvar == null) {
      setState(() => _error = "MW dan MVAR harus angka.");
      return;
    }

    // Hitung duration (detik) dari Start -> Pred
    final start = DateTime(
      _startDate!.year,
      _startDate!.month,
      _startDate!.day,
      _startTime!.hour,
      _startTime!.minute,
    );
    final pred = DateTime(
      _predDate!.year,
      _predDate!.month,
      _predDate!.day,
      _predTime!.hour,
      _predTime!.minute,
    );
    final durationSec = pred.difference(start).inSeconds.toDouble();

    if (durationSec.isNaN || durationSec.isInfinite) {
      setState(() => _error = "Durasi tidak valid.");
      return;
    }
    if (durationSec < 0) {
      setState(() => _error = "Pred Time tidak boleh lebih awal dari Start Time.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _prediction = null;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/predict');

      // Backend hanya butuh mvar, mw, duration (lihat app.py)
      final body = jsonEncode({
        "mvar": mvar,
        "mw": mw,
        "duration": durationSec,
      });

      // === perubahan utama: gunakan AuthService agar Authorization header otomatis,
      // dan auto-refresh access token jika 401 ===
      final resp = await AuthService.instance.post(
        uri.toString(),
        body: body,
      ).timeout(const Duration(seconds: 30));

      final status = resp.statusCode;
      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        // biarkan kosong, akan ditangani di bawah
      }

      if (status == 200) {
        // Cari nilai prediksi pada dua kemungkinan key
        double? val;
        if (data["prediction"] != null) {
          val = (data["prediction"] as num).toDouble();
        } else if (data["predicted_temperature"] != null) {
          val = (data["predicted_temperature"] as num).toDouble();
        }

        if (val != null) {
          final d = val; // non-null
          setState(() => _prediction = "${d.toStringAsFixed(2)} °C");
        } else {
          final errMsg = data["error"]?.toString();
          setState(() => _error = "Gagal prediksi${errMsg != null ? ": $errMsg" : ""}");
        }
      } else {
        final errMsg = data["error"]?.toString();
        setState(() => _error =
            "Server error: $status${errMsg != null ? " — $errMsg" : " — ${resp.body}"}");
      }
    } catch (e) {
      setState(() => _error = "Error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _mwController.dispose();
    _mvarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat("yyyy-MM-dd");
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/background2.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  // Start Date
                  TextField(
                    readOnly: true,
                    style: const TextStyle(color: Colors.white),
                    onTap: () => _pickDate(true),
                    controller: TextEditingController(
                      text: _startDate == null ? "" : dateFmt.format(_startDate!),
                    ),
                    decoration: _decoration("Start Date"),
                  ),
                  const SizedBox(height: 12),

                  // Start Time
                  TextField(
                    readOnly: true,
                    style: const TextStyle(color: Colors.white),
                    onTap: () => _pickTime(true),
                    controller: TextEditingController(
                      text: _startTime == null ? "" : _formatTime(_startTime!),
                    ),
                    decoration: _decoration("Start Time"),
                  ),
                  const SizedBox(height: 12),

                  // Pred Date
                  TextField(
                    readOnly: true,
                    style: const TextStyle(color: Colors.white),
                    onTap: () => _pickDate(false),
                    controller: TextEditingController(
                      text: _predDate == null ? "" : dateFmt.format(_predDate!),
                    ),
                    decoration: _decoration("Pred Date"),
                  ),
                  const SizedBox(height: 12),

                  // Pred Time
                  TextField(
                    readOnly: true,
                    style: const TextStyle(color: Colors.white),
                    onTap: () => _pickTime(false),
                    controller: TextEditingController(
                      text: _predTime == null ? "" : _formatTime(_predTime!),
                    ),
                    decoration: _decoration("Pred Time"),
                  ),
                  const SizedBox(height: 12),

                  // MW
                  TextField(
                    controller: _mwController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: _decoration("MW"),
                  ),
                  const SizedBox(height: 12),

                  // MVAR
                  TextField(
                    controller: _mvarController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    decoration: _decoration("MVAR"),
                  ),

                  const SizedBox(height: 20),

                  // Predict button
                  ElevatedButton(
                    onPressed: _loading ? null : _predict,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Predict"),
                  ),
                  const SizedBox(height: 20),

                  if (_prediction != null)
                    Text(
                      "Hasil: $_prediction",
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.greenAccent,
                      ),
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.redAccent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
