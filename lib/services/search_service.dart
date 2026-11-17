import 'dart:math';
import '../models/chunk.dart';

/*
 * A single match from the search, pairing a document section with a relevance
 * score so results can be ranked and the best ones shown first.
 */
class SearchResult {
  final Chunk chunk;
  final double score;

  const SearchResult({required this.chunk, required this.score});
}

/*
 * Finds the most relevant document sections for a student's question using
 * BM25, a keyword-based ranking algorithm used in real search engines.
 * BM25 scores each section by how often the question's words appear in it,
 * adjusted so that common words and very long sections are not unfairly favored.
 */
class SearchService {
  static const double _scoreThreshold = 0.1;
  static const int _maxResults = 2;
  /*
   * Controls how much a word's frequency boosts the score. Higher values
   * reward sections that repeat the search term many times.
   */
  static const double _bm25K1 = 1.5;
  /*
   * Controls length normalization. 0.75 means longer sections are penalized
   * slightly so a short, focused answer can beat a long one that just happens
   * to mention the word more often.
   */
  static const double _bm25B = 0.75;

  List<Chunk> _chunks = [];
  Map<String, double> _idfByTerm = {};

  /*
   * Stores all the chunks and pre-computes word rarity scores (IDF) so that
   * searches later do not have to recalculate them from scratch each time.
   */
  Future<void> buildIndex(List<Chunk> chunks) async {
    _chunks = chunks;
    _idfByTerm = _computeIdf(chunks);
  }

  /*
   * Scores every chunk against the query, filters out weak matches, sorts
   * by score, and returns the top few results.
   */
  Future<List<SearchResult>> search(String query) async {
    if (_chunks.isEmpty) return [];
    final queryTerms = _tokenize(query);
    if (queryTerms.isEmpty) return [];

    final results = _chunks
        .map((chunk) => SearchResult(chunk: chunk, score: _scoreBm25(queryTerms, chunk.text)))
        .where((result) => result.score >= _scoreThreshold)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return results.take(_maxResults).toList();
  }

  /*
   * Calculates how rare each word is across all chunks. A word that appears
   * in almost every chunk (like "the") gets a low score; a word that appears
   * in only one chunk gets a high score and is treated as more meaningful.
   */
  Map<String, double> _computeIdf(List<Chunk> chunks) {
    final documentFrequency = <String, int>{};
    for (final chunk in chunks) {
      for (final term in _tokenize(chunk.text).toSet()) {
        documentFrequency[term] = (documentFrequency[term] ?? 0) + 1;
      }
    }
    final totalDocs = chunks.length.toDouble();
    return documentFrequency.map((term, freq) =>
        MapEntry(term, log((totalDocs - freq + 0.5) / (freq + 0.5) + 1)));
  }

  /*
   * Computes the BM25 relevance score for one chunk. For each query word,
   * it combines how often the word appears in the chunk (term frequency) with
   * how rare the word is across all chunks (IDF), then adjusts for chunk length.
   */
  double _scoreBm25(List<String> queryTerms, String documentText) {
    final avgDocLength = _chunks
            .map((chunk) => _tokenize(chunk.text).length)
            .reduce((sum, length) => sum + length) /
        _chunks.length;

    final docTokens = _tokenize(documentText);
    final docLength = docTokens.length.toDouble();
    final termFrequency = <String, int>{};
    for (final term in docTokens) {
      termFrequency[term] = (termFrequency[term] ?? 0) + 1;
    }

    double score = 0;
    for (final term in queryTerms.toSet()) {
      final tf = termFrequency[term] ?? 0;
      if (tf == 0) continue;
      final idf = _idfByTerm[term] ?? 0;
      score += idf * (tf * (_bm25K1 + 1)) /
          (tf + _bm25K1 * (1 - _bm25B + _bm25B * docLength / avgDocLength));
    }
    return score;
  }

  List<String> _tokenize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.length > 2)
      .toList();
}
