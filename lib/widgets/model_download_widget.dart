import 'package:flutter/material.dart';
import '../services/qwen_service.dart';

/*
 * A full-screen prompt that asks the user to download the AI model, with a
 * progress bar and a skip option.
 * The skip option lets the app work in search-only mode if the user does not
 * want to wait for the download or does not have enough storage.
 */
class ModelDownloadWidget extends StatefulWidget {
  final QwenService qwenService;
  final VoidCallback onSkip;
  final VoidCallback onReady;

  const ModelDownloadWidget({
    super.key,
    required this.qwenService,
    required this.onSkip,
    required this.onReady,
  });

  @override
  State<ModelDownloadWidget> createState() => _ModelDownloadWidgetState();
}

class _ModelDownloadWidgetState extends State<ModelDownloadWidget> {
  double _progress = 0;
  bool _downloading = false;
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
    });

    await widget.qwenService.downloadModel(
      onProgress: (p) => setState(() => _progress = p),
      onComplete: () async {
        await widget.qwenService.loadModel();
        widget.onReady();
      },
      onError: (e) => setState(() {
        _error = 'Download failed: $e';
        _downloading = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.download_for_offline_outlined, size: 64, color: Colors.indigo),
          const SizedBox(height: 16),
          const Text(
            'Qwen3 0.6B Model Required',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'To generate natural language answers, the app needs to download the Qwen3 0.6B model (~345 MB). This requires an internet connection and sufficient storage space.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_downloading) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
            Text(
              _progress > 0
                  ? 'Downloading... ${(_progress * 100).toStringAsFixed(0)}%'
                  : 'Starting download...',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: Text(_error != null ? 'Retry Download' : 'Download Qwen3 0.6B (~345 MB)'),
                onPressed: _startDownload,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onSkip,
                child: const Text('Skip – Use Retrieval Only'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
