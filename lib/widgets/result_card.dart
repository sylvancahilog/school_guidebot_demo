import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/search_service.dart';

/*
 * Displays one matching document section as a card, with a relevance score
 * badge and a show more/less toggle for long text.
 * The score badge helps students understand how confident the search is that
 * this section answers their question.
 */
class ResultCard extends StatefulWidget {
  final SearchResult result;

  const ResultCard({super.key, required this.result});

  @override
  State<ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<ResultCard> {
  static const int _previewLength = 300;
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final chunk = widget.result.chunk;
    final scoreLabel = '${(widget.result.score.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%';
    final isLong = chunk.text.length > _previewLength;
    final displayText = (isLong && !_isExpanded)
        ? '${chunk.text.substring(0, _previewLength)}...'
        : chunk.text;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${chunk.source} · ${chunk.heading}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.indigo,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Text(
                    scoreLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.indigo.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownBody(
              data: displayText,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
            if (isLong) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                child: Text(
                  _isExpanded ? 'Show less' : 'Show more',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.indigo.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
