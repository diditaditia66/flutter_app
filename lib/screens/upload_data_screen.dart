// lib/screens/upload_data_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_client_sse/flutter_client_sse.dart';
import 'package:flutter_client_sse/constants/sse_request_type_enum.dart';

import '../config/api_config.dart'; // apiBaseUrl
import '../services/auth_service.dart'; // <-- tambah: untuk Authorization header

class UploadDataScreen extends StatefulWidget {
  const UploadDataScreen({super.key});
  @override
  State<UploadDataScreen> createState() => _UploadDataScreenState();
}

class _UploadDataScreenState extends State<UploadDataScreen> {
  PlatformFile? _picked;
  bool _uploading = false;
  double _progress = 0.0;
  String? _jobId;

  /// Tandai apakah SSE sudah benar-benar selesai (ada pesan selesai).
  bool _sseDone = false;

  final List<String> _logs = [];
  final ScrollController _logCtrl = ScrollController();
  StreamSubscription<SSEModel>? _sseSub;

  // ---------- helpers ----------
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

  bool _isDoneLine(String line) {
    final l = line.toLowerCase();
    return l.contains('selesai proses') ||
        l.contains('proses selesai') ||
        l.contains('retrain sukses') ||
        l.contains('✅  selesai proses') ||
        l.contains('✅ selesai proses') ||
        l.startsWith('✅') ||
        l == 'selesai.' ||
        l == 'selesai.'; // backend kamu kirim "Selesai." di finally (di-lowercase)
  }

  @override
  void dispose() {
    _closeSse();
    _logCtrl.dispose();
    super.dispose();
  }

  Future<void> _closeSse() async {
    try {
      await _sseSub?.cancel();
    } catch (_) {}
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: kIsWeb, // Web: perlu bytes; Mobile: gunakan path
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _picked = result.files.single;
        _progress = 0;
        _jobId = null;
        _sseDone = false;
        _logs.clear();
      });
    }
  }

  Future<void> _startUpload() async {
    if (_picked == null) {
      _appendLog('❌  Tidak ada file yang dipilih.');
      return;
    }
    setState(() {
      _uploading = true;
      _progress = 0.0;
      _logs.clear();
      _jobId = null;
      _sseDone = false;
    });

    try {
      // Ambil Authorization header dari AuthService
      final authHeaders = await AuthService.instance.authHeaders();

      // Gunakan base URL VPS
      final dio = Dio(
        BaseOptions(
          baseUrl: apiBaseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 300),
          sendTimeout: const Duration(minutes: 5),
          // Jangan set contentType di BaseOptions untuk multipart; set via Options/auto
        ),
      );

      MultipartFile mf;
      if (kIsWeb) {
        if (_picked!.bytes == null) {
          _appendLog('❌  File tidak memiliki bytes.');
          setState(() => _uploading = false);
          return;
        }
        mf = MultipartFile.fromBytes(_picked!.bytes!, filename: _picked!.name);
      } else {
        if (_picked!.path == null) {
          _appendLog('❌  Path file tidak tersedia.');
          setState(() => _uploading = false);
          return;
        }
        mf = await MultipartFile.fromFile(
          _picked!.path!,
          filename: _picked!.name,
        );
      }

      final form = FormData.fromMap({'file': mf});
      _appendLog('📤 Mengunggah ${_picked!.name} ...');

      final resp = await dio.post(
        '/upload_async',
        data: form,
        options: Options(
          headers: {
            ...authHeaders, // <-- Authorization: Bearer <token>
          },
        ),
        onSendProgress: (sent, total) {
          if (total > 0) {
            setState(() => _progress = (sent / total).clamp(0, 1).toDouble());
          }
        },
      );

      if (resp.statusCode == 200 && resp.data != null) {
        final body = (resp.data is Map)
            ? (resp.data as Map)
            : jsonDecode(resp.data.toString()) as Map<String, dynamic>;
        final job = body['job_id'];
        if (job is String && job.isNotEmpty) {
          setState(() {
            _jobId = job;
            _progress = 1.0; // upload selesai
            _uploading = false;
          });
          _appendLog('✅  Upload selesai. job_id: $job');
          _connectSse(job);
        } else {
          _appendLog('❌  Respons tidak berisi job_id yang valid.');
          setState(() => _uploading = false);
        }
      } else {
        _appendLog('❌  Gagal upload. Status: ${resp.statusCode}');
        setState(() => _uploading = false);
      }
    } catch (e) {
      _appendLog('❌  Error upload: $e');
      setState(() => _uploading = false);
    }
  }

  Future<void> _connectSse(String jobId) async {
    await _closeSse();

    final url = '$apiBaseUrl/upload/stream?job_id=${Uri.encodeComponent(jobId)}';
    _appendLog('🔗 Hubungkan SSE: $url');

    try {
      // Sisipkan Authorization header untuk SSE juga
      final authHeaders = await AuthService.instance.authHeaders();

      _sseSub = SSEClient.subscribeToSSE(
        method: SSERequestType.GET,
        url: url,
        header: {
          'Accept': 'text/event-stream',
          ...authHeaders, // <-- Authorization: Bearer <token>
          // 'Cache-Control': 'no-cache', // opsional
        },
      ).listen((evt) {
        final payload = (evt.data ?? '').toString();
        if (payload.isEmpty) return;

        // EventSource kadang menggabungkan beberapa baris
        final lines = payload.split('\n');
        for (final raw in lines) {
          final line = raw.trim();
          if (line.isEmpty) continue;

          _appendLog(line);

          if (_isDoneLine(line)) {
            if (mounted) setState(() => _sseDone = true);
            Future.delayed(const Duration(milliseconds: 400), () {
              _closeSse();
            });
          }
        }
      }, onError: (_) {
        if (mounted && !_sseDone) {
          _appendLog('⚠️ SSE error/terputus.');
        }
        _closeSse();
      });
    } catch (e) {
      _appendLog('❌  Tidak bisa membuka SSE: $e');
      await _closeSse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpload = _picked != null && !_uploading;
    final showProgress = _uploading;

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
                    'Upload Dataset (CSV)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _uploading ? null : _pickFile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Choose File'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1C),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _picked?.name ?? 'Belum ada file dipilih',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: canUpload ? _startUpload : null,
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
                    child: _uploading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Upload'),
                  ),
                  const SizedBox(height: 12),
                  if (showProgress) ...[
                    LinearProgressIndicator(
                      value: _progress.clamp(0, 1),
                      backgroundColor: const Color(0xFF2A2A2A),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Progress: ${(100 * _progress).toStringAsFixed(0)}%',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                      textAlign: TextAlign.right,
                    ),
                  ],
                  if (!showProgress && _jobId != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1C),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        'job_id: $_jobId',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
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
                    constraints:
                        const BoxConstraints(minHeight: 180, maxHeight: 320),
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
