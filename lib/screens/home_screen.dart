import 'package:flutter/material.dart';
import '../services/document_service.dart';
import '../services/search_service.dart';
import '../services/qwen_service.dart';
import '../widgets/model_download_widget.dart';
import '../widgets/loading_view.dart';
import '../widgets/query_view.dart';
import 'document_screen.dart';

enum _AppState { loading, awaitingModelDownload, ready }

/*
 * The main screen that coordinates startup, document loading, and the
 * question-and-answer flow.
 *
 * Data flow: DocumentService loads and splits the files into chunks, then
 * SearchService builds a search index from those chunks. When a student asks
 * a question, SearchService finds the most relevant chunks, and QwenService
 * uses those chunks as context to write a natural language answer.
 */
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _queryController = TextEditingController();
  final _documentService = DocumentService();
  final _searchService = SearchService();
  final _qwenService = QwenService();

  _AppState _appState = _AppState.loading;
  String _loadingMessage = 'Indexing documents...';
  bool _modelLoaded = false;

  List<SearchResult> _results = [];
  String _streamedAnswer = '';
  bool _searching = false;
  bool _generating = false;
  bool _noResults = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _loadingMessage = 'Indexing documents...');
    final chunks = await _documentService.loadAllChunks();

    setState(() => _loadingMessage = 'Building search index...');
    await _searchService.buildIndex(chunks);

    final hasModel = await _qwenService.checkModelPresent();
    if (hasModel) {
      setState(() => _loadingMessage = 'Loading model...');
      await _qwenService.loadModel();
      setState(() {
        _modelLoaded = true;
        _appState = _AppState.ready;
      });
    } else {
      setState(() => _appState = _AppState.awaitingModelDownload);
    }
  }

  Future<void> _submitQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _results = [];
      _streamedAnswer = '';
      _noResults = false;
      _generating = false;
    });

    final results = await _searchService.search(query);
    setState(() {
      _searching = false;
      _results = results;
      _noResults = results.isEmpty;
    });

    if (_modelLoaded) {
      setState(() => _generating = true);
      await for (final token in _qwenService.generateAnswer(query, results)) {
        setState(() => _streamedAnswer += token);
      }
      setState(() => _generating = false);
    }
  }

  void _onModelReady() {
    setState(() => _modelLoaded = true);
  }

  void _openDocument(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentScreen(
          title: name,
          assetPath: DocumentService.sources[name]!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('School Guide'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'View documents',
            onSelected: _openDocument,
            itemBuilder: (_) => DocumentService.sources.keys
                .map((name) => PopupMenuItem(value: name, child: Text(name)))
                .toList(),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_appState) {
      case _AppState.loading:
        return LoadingView(message: _loadingMessage);
      case _AppState.awaitingModelDownload:
        return ModelDownloadWidget(
          qwenService: _qwenService,
          onSkip: () => setState(() => _appState = _AppState.ready),
          onReady: () => setState(() {
            _modelLoaded = true;
            _appState = _AppState.ready;
          }),
        );
      case _AppState.ready:
        return QueryView(
          queryController: _queryController,
          onSubmit: _submitQuery,
          searching: _searching,
          generating: _generating,
          noResults: _noResults,
          modelLoaded: _modelLoaded,
          results: _results,
          streamedAnswer: _streamedAnswer,
          qwenService: _qwenService,
          onModelReady: _onModelReady,
        );
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _qwenService.dispose();
    super.dispose();
  }
}
