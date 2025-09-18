#!/bin/bash
set -euo pipefail

cd ~/temperature-prediction-app/flutter_app/lib/screens

echo ">> Menulis ulang upload_data_screen.dart (progress bar klasik)..."
cat > upload_data_screen.dart <<'DART'
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart'; // <- path yang benar (lib/api_config.dart)

class UploadDataScreen extends StatefulWidget {
  const UploadDataScreen({Key? key}) : super(key: key);

  @override
  State<UploadDataScreen> createState() => _UploadDataScreenState();
}

class _UploadDataScreenState extends State<UploadDataScreen> {
  bool _isUploading = false;
  double? _progress; // null = indeterminate bar
  String _message = "";
  String? _pickedName;

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true, // web butuh bytes
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    setState(() {
      _pickedName = file.name;
    });
    await _uploadFile(file);
  }

  Future<void> _uploadFile(PlatformFile file) async {
    final uri = Uri.parse("$apiBaseUrl/upload_async");

    setState(() {
      _isUploading = true;
      _progress = null; // indeterminate selama upload (http MultipartRequest tidak support progress)
      _message = "Mengunggah ${_pickedName ?? 'file'}...";
    });

    try {
      final request = http.MultipartRequest('POST', uri);

      if (file.bytes != null) {
        // Web / bytes
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
          ),
        );
      } else if (file.path != null) {
        // Mobile/desktop
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            file.path!,
          ),
        );
      } else {
        throw Exception("File tidak memiliki bytes maupun path.");
      }

      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200) {
        // Optional: baca job_id dari response, tapi progress bar dibuat simple.
        setState(() {
          _progress = 1.0;
          _message = "✅ Upload selesai.";
        });
      } else {
        setState(() {
          _message = "❌ Upload gagal (status ${resp.statusCode}): ${resp.body}";
        });
      }
    } catch (e) {
      setState(() {
        _message = "❌ Error: $e";
      });
    } finally {
      setState(() {
        // matikan indikator upload; progress bar tetap nampak full sebentar (kalau 1.0)
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileText = _pickedName == null ? 'Belum ada file dipilih' : _pickedName!;
    return Scaffold(
      appBar: AppBar(title: const Text("Upload Data (Progress Bar)")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Picker + Upload
            Row(
              children: [
                Expanded(child: Text(fileText, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _pickAndUpload,
                  child: const Text("Pilih & Upload CSV"),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (_isUploading || _progress != null) ...[
              LinearProgressIndicator(value: _progress), // null => indeterminate
              const SizedBox(height: 8),
              Text(_message),
            ] else if (_message.isNotEmpty) ...[
              Text(_message),
            ],
          ],
        ),
      ),
    );
  }
}
DART

echo ">> Menulis ulang retrain_screen.dart (SSE yang stabil)..."
cat > retrain_screen.dart <<'DART'
import 'dart:html' as html; // SSE untuk Web
import 'package:flutter/material.dart';
import '../api_config.dart'; // <- path yang benar

class RetrainScreen extends StatefulWidget {
  const RetrainScreen({Key? key}) : super(key: key);

  @override
  State<RetrainScreen> createState() => _RetrainScreenState();
}

class _RetrainScreenState extends State<RetrainScreen> {
  html.EventSource? _es;
  final ScrollController _scrollController = ScrollController();
  String _logText = "";
  bool _sseError = false;
  bool _running = false;

  void _startRetrain() {
    // tombol memulai POST retrain (non-blocking), lalu buka SSE
    _kickoffRetrainAndStream();
  }

  Future<void> _kickoffRetrainAndStream() async {
    setState(() {
      _logText = "";
      _sseError = false;
      _running = true;
    });

    // 1) panggil POST /retrain (biar backend mulai proses)
    try {
      // pakai fetch dari browser supaya simple; response tidak dipakai
      html.HttpRequest.request(
        "$apiBaseUrl/retrain",
        method: "POST",
      );
    } catch (_) {
      // abaikan; SSE di step 2 tetap dicoba
    }

    // 2) buka SSE /retrain/stream
    final url = "$apiBaseUrl/retrain/stream";
    _connectSseWeb(url);
  }

  void _connectSseWeb(String url) {
    try { _es?.close(); } catch (_) {}
    setState(() {
      _es = null;
      _sseError = false;
    });

    final es = html.EventSource(url);
    _es = es;

    es.onMessage.listen((event) {
      final line = event.data?.toString() ?? '';
      setState(() {
        _logText += (line.isEmpty ? '' : '$line\n');
      });
      // auto scroll ke bawah
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });

    es.onError.listen((_) {
      setState(() {
        _sseError = true;
        _running = false;
        _logText += "❌ SSE error / connection closed\n";
      });
    });
  }

  @override
  void dispose() {
    try { _es?.close(); } catch (_) {}
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = _running; // saat jalan, tombol dimatikan
    return Scaffold(
      appBar: AppBar(title: const Text("Retrain Model (SSE)")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton(
                  onPressed: isDisabled ? null : _startRetrain,
                  child: const Text("Mulai Retrain (Stream)"),
                ),
                const SizedBox(width: 12),
                if (_sseError) const Text("❌ Koneksi SSE error", style: TextStyle(color: Colors.red)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Text(
                    _logText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
DART

echo "✅ Selesai. File sudah dipulihkan."
