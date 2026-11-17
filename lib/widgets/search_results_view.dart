import 'package:flutter/material.dart';
import '../services/search_service.dart';
import '../widgets/result_card.dart';
import '../widgets/answer_card.dart';

/*
 * Shows the state of search results: a spinner while searching, a prompt
 * before any search, or the list of matched sections and the AI answer.
 * Centralizing these states here means the parent widget does not need to
 * know the details of how each state looks on screen.
 */
class SearchResultsView extends StatelessWidget {
  final bool searching;
  final bool noResults;
  final bool modelLoaded;
  final List<SearchResult> results;
  final String streamedAnswer;
  final bool generating;

  const SearchResultsView({
    super.key,
    required this.searching,
    required this.noResults,
    required this.modelLoaded,
    required this.results,
    required this.streamedAnswer,
    required this.generating,
  });

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (results.isEmpty && !generating && streamedAnswer.isEmpty) {
      return Center(
        child: Text(
          noResults
              ? 'No relevant section found in any document.'
              : 'Ask a question to search the school documents.',
          style: TextStyle(color: noResults ? Colors.black54 : Colors.black38),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        if (modelLoaded)
          AnswerCard(
            answer: streamedAnswer.isEmpty && generating
                ? '_Generating answer..._'
                : streamedAnswer,
            sources: results,
          )
        else
          ...results.map((result) => ResultCard(result: result)),
      ],
    );
  }
}
