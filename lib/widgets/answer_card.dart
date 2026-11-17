import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/search_service.dart';
import 'result_card.dart';

/*
 * Shows the AI-generated answer alongside the document sections it was based on.
 * Displaying the sources beneath the answer helps students verify where the
 * information came from and read more if they need to.
 */
class AnswerCard extends StatelessWidget {
  final String answer;
  final List<SearchResult> sources;

  const AnswerCard({super.key, required this.answer, required this.sources});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Colors.indigo.shade50,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: Colors.indigo.shade600),
                    const SizedBox(width: 6),
                    Text(
                      'Answer',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.indigo.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                MarkdownBody(data: answer),
              ],
            ),
          ),
        ),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Sources',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          ...sources.map((result) => ResultCard(result: result)),
        ],
      ],
    );
  }
}
