import 'dart:async';
import 'dart:io';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../services/search_service.dart';

/*
 * Manages downloading, loading, and running the on-device AI model that
 * writes answers to student questions.
 * Running the model on the device (instead of a remote server) means the app
 * works offline and no student data ever leaves the phone.
 */
class QwenService {
  static const String _modelFilename = 'Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm';
  static const String _modelDownloadUrl =
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/e6687177e00897731e7716267eebd4eba0dde7c2/Qwen3-0.6B_dynamic_wi4b32_afp32.litertlm';
  static const String _systemPrompt =
      'You are a helpful school assistant. When document context is provided, '
      'use it to answer and cite which document the information comes from. '
      'When no context is provided, answer conversationally from general knowledge.';

  InferenceModel? _model;
  bool _isAvailable = false;

  bool get isAvailable => _isAvailable;

  Future<bool> checkModelPresent() async {
    final dir = await getApplicationDocumentsDirectory();
    _isAvailable = File('${dir.path}/$_modelFilename').existsSync();
    return _isAvailable;
  }

  Future<void> loadModel() async {
    if (!_isAvailable) return;
    final dir = await getApplicationDocumentsDirectory();
    await FlutterEdgeAi.installModel(
      modelType: ModelType.qwen3,
      fileType: ModelFileType.litertlm,
    ).fromFile('${dir.path}/$_modelFilename').install();
    _model = await FlutterEdgeAi.getActiveModel(maxTokens: 1024);
  }

  /*
   * Downloads the model file in a streaming fashion so progress can be
   * reported in real time. Calls onProgress repeatedly, then onComplete
   * when finished, or onError if something goes wrong.
   */
  Future<void> downloadModel({
    required void Function(double progress) onProgress,
    required void Function() onComplete,
    required void Function(String error) onError,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelFile = File('${dir.path}/$_modelFilename');
      final request = http.Request('GET', Uri.parse(_modelDownloadUrl));
      final response = await http.Client().send(request);
      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = modelFile.openWrite();
      await response.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) onProgress(receivedBytes / totalBytes);
      }).asFuture();
      await sink.close();
      _isAvailable = true;
      onComplete();
    } catch (error) {
      onError(error.toString());
    }
  }

  /*
   * Builds a prompt by combining the matched document sections (as context)
   * with the student's question, then streams the model's reply back one token
   * at a time so the UI can display words as they are generated.
   */
  Stream<String> generateAnswer(String question, List<SearchResult> results) async* {
    if (_model == null) return;

    final contextText = results
        .map((result) => '[${result.chunk.source}] ${result.chunk.heading}:\n${result.chunk.text}')
        .join('\n\n');

    final userMessage = contextText.isNotEmpty
        ? 'Document Context:\n$contextText\n\nStudent Question: $question'
        : question;

    final chat = await _model!.openChat(
      modelType: ModelType.qwen3,
      systemInstruction: _systemPrompt,
      enableThinking: false,
      maxOutputTokens: 512,
      temperature: 0.7,
      topK: 40,
      randomSeed: 42,
    );

    try {
      await chat.addQueryChunk(Message.text(text: userMessage, isUser: true));
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) yield response.token;
      }
    } finally {
      await chat.close();
    }
  }

  void dispose() {
    _model?.close();
    _model = null;
  }
}
