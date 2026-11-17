import 'package:flutter/material.dart';
import '../services/qwen_service.dart';

enum DownloadState { idle, downloading, loadingModel }

/*
 * A compact banner at the bottom of the screen that lets the user download
 * the AI model while still using the app.
 * Shown only after the user skips the full download screen, so they can still
 * get AI answers later without restarting.
 */
class QwenBanner extends StatefulWidget {
  final QwenService qwenService;
  final VoidCallback onReady;

  const QwenBanner({
    super.key,
    required this.qwenService,
    required this.onReady,
  });

  @override
  State<QwenBanner> createState() => _QwenBannerState();
}

class _QwenBannerState extends State<QwenBanner> {
  DownloadState _downloadState = DownloadState.idle;
  double _downloadProgress = 0;
  String? _downloadError;

  Future<void> _startDownload() async {
    setState(() {
      _downloadState = DownloadState.downloading;
      _downloadProgress = 0;
      _downloadError = null;
    });

    await widget.qwenService.downloadModel(
      onProgress: (p) => setState(() => _downloadProgress = p),
      onComplete: () async {
        setState(() => _downloadState = DownloadState.loadingModel);
        await widget.qwenService.loadModel();
        widget.onReady();
      },
      onError: (e) => setState(() {
        _downloadError = 'Download failed: $e';
        _downloadState = DownloadState.idle;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          border: Border(top: BorderSide(color: Colors.indigo.shade100)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: switch (_downloadState) {
          DownloadState.idle => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 18, color: Colors.indigo),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Enable AI answers with Qwen3 0.6B (~345 MB)',
                      style: TextStyle(fontSize: 13, color: Colors.indigo),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _startDownload,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: Text(_downloadError != null ? 'Retry' : 'Download'),
                  ),
                ],
              ),
              if (_downloadError != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 14, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _downloadError!,
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          DownloadState.downloading => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.download, size: 16, color: Colors.indigo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _downloadProgress > 0
                          ? 'Downloading Qwen3... ${(_downloadProgress * 100).toStringAsFixed(0)}%'
                          : 'Starting download...',
                      style: const TextStyle(fontSize: 13, color: Colors.indigo),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                backgroundColor: Colors.indigo.shade100,
                color: Colors.indigo,
              ),
            ],
          ),
          DownloadState.loadingModel => const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo),
              ),
              SizedBox(width: 10),
              Text('Loading Qwen3 model...', style: TextStyle(fontSize: 13, color: Colors.indigo)),
            ],
          ),
        },
      ),
    );
  }
}
