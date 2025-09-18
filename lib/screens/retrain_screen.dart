// lib/screens/retrain_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';

import '../config/api_config.dart'; // apiBaseUrl
import '../services/auth_service.dart'; // <-- tambahkan untuk Authorization header

class RetrainScreen extends StatefulWidget {
  const RetrainScreen({super.key});
  @override
  State<RetrainScreen> createState() => _RetrainScreenState();
}

class _RetrainScreenState extends State<RetrainScreen> {
  bool _busy = false;         // status backend busy
  bool _sending = false;      // status tombol kirim POST
  bool _sseConnected = false; // indikator SSE tersambung

  final List<String> _logs = [];
  final _logCtrl = ScrollController();
  StreamSubscription<SSEModel>? _sseSub;

  void _appendLog(String line) {
    setState(() => _logs.add(line.trimRight()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logCtrl.hasClients) {
        _logCtrl.animateTo(
          _logCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startRetrain() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _busy = false;
      _sseConnected = false;
      _logs.clear();
    });

    try {
      // sisipkan Authorization: Bearer <token>
      final authHeaders = await AuthService.instance.authHeaders();
      final resp = await http.post(
        Uri.parse('$apiBaseUrl/retrain'),
        headers: {
          ...authHeaders,
          'Content-Type': 'application/json',
        },
      );

      // Backend: 200 {"status":"started"} atau 409 {"status":"busy"}
      if (resp.statusCode == 200 || resp.statusCode == 409) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final status = (body['status'] ?? '').toString();
        if (status == 'started') {
          _appendLog('Perintah retrain diterima server.');
          await _connectSse();
        } else if (status == 'busy') {
          _appendLog('⚠️ Server sedang retrain (busy). Coba lagi nanti.');
          setState(() => _busy = true);
        } else {
          _appendLog('❌ Respons tidak dikenal: ${resp.body}');
        }
      } else {
        _appendLog('❌ Gagal kirim perintah retrain. HTTP ${resp.statusCode}');
      }
    } catch (e) {
      _appendLog('❌ Gagal kirim perintah retrain: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _closeSse() async {
    try {
      await _sseSub?.cancel();
    } catch (_) {}
    if (mounted) setState(() => _sseConnected = false);
  }

  Future<void> _connectSse() async {
    await _closeSse();
    setState(() => _sseConnected = false);

    final url = '$apiBaseUrl/retrain/stream';
    _appendLog('🔗 Hubungkan SSE: $url');

    try {
      final authHeaders = await AuthService.instance.authHeaders();

      _sseSub = SSEClient.subscribeToSSE(
        method: SSERequestType.GET,
        url: url,
        header: {
          'Accept': 'text/event-stream',
          ...authHeaders, // <-- Authorization: Bearer <token>
        },
      ).listen((evt) async {
        final payload = (evt.data ?? '').toString().trim();
        if (payload.isEmpty) return;

        // Aman jika backend mengirim beberapa baris
        for (final raw in payload.split('\n')) {
          final line = raw.trim();
          if (line.isEmpty) continue;

          _appendLog(line);
          final low = line.toLowerCase();

          // Deteksi selesai sesuai log backend
          if (low.contains('retrain sukses') ||
              low.contains('proses selesai') ||
              low == 'selesai.' ||
              low.startsWith('✅')) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await _closeSse();
          }
        }
      }, onDone: () {
        setState(() => _sseConnected = false);
      }, onError: (_) async {
        _appendLog('⚠️ SSE error/terputus.');
        await _closeSse();
      });

      if (mounted) {
        setState(() => _sseConnected = true);
        _appendLog('🔌 SSE connected');
      }
    } catch (e) {
      _appendLog('❌ Tidak bisa membuka SSE: $e');
      await _closeSse();
    }
  }

  @override
  void dispose() {
    _closeSse();
    _logCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Retrain Model',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _sending ? null : _startRetrain,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_busy ? 'Server Busy — Coba Lagi' : 'Retrain Model'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        _sseConnected ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: _sseConnected ? Colors.greenAccent : Colors.white38,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _sseConnected ? 'SSE tersambung' : 'SSE belum tersambung',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Log',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(minHeight: 200, maxHeight: 360),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF333333)),
                    ),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _logCtrl,
                        itemCount: _logs.length,
                        itemBuilder: (_, i) => Text(
                          _logs[i],
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'monospace',
                            height: 1.25,
                          ),
                        ),
                      ),
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
