import 'package:flutter/material.dart';
import '../services/qwen_service.dart';
import '../services/search_service.dart';
import '../widgets/search_results_view.dart';
import '../widgets/qwen_banner.dart';

/*
 * The main layout for the ready state: a search bar at the top, results in
 * the middle, and an optional AI download banner at the bottom.
 * Separating this layout into its own widget keeps HomeScreen focused on
 * logic while QueryView handles how things look on screen.
 */
class QueryView extends StatelessWidget {
  final TextEditingController queryController;
  final VoidCallback onSubmit;
  final bool searching;
  final bool generating;
  final bool noResults;
  final bool modelLoaded;
  final List<SearchResult> results;
  final String streamedAnswer;
  final QwenService? qwenService;
  final VoidCallback? onModelReady;

  const QueryView({
    super.key,
    required this.queryController,
    required this.onSubmit,
    required this.searching,
    required this.generating,
    required this.noResults,
    required this.modelLoaded,
    required this.results,
    required this.streamedAnswer,
    this.qwenService,
    this.onModelReady,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: queryController,
                  decoration: const InputDecoration(
                    hintText: 'Ask a question about school policies...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (_) => onSubmit(),
                  textInputAction: TextInputAction.search,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: (searching || generating) ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                child: const Text('Ask'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SearchResultsView(
            searching: searching,
            noResults: noResults,
            modelLoaded: modelLoaded,
            results: results,
            streamedAnswer: streamedAnswer,
            generating: generating,
          ),
        ),
        if (!modelLoaded && qwenService != null && onModelReady != null)
          QwenBanner(qwenService: qwenService!, onReady: onModelReady!),
      ],
    );
  }
}
