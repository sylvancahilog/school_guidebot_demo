import 'package:flutter/services.dart';
import '../models/chunk.dart';

/*
 * Reads the school's markdown files and splits them into small sections the
 * app can search through.
 * Keeping documents as separate chunks means the search only needs to surface
 * the most relevant section, rather than returning an entire file each time.
 */
class DocumentService {
  static const Map<String, String> sources = {
    'Handbook': 'assets/handbook.md',
    'School Policy': 'assets/policy.md',
  };

  /*
   * Loads every registered document and returns all of their chunks combined
   * into one list for the search index to use.
   */
  Future<List<Chunk>> loadAllChunks() async {
    final chunks = <Chunk>[];
    for (final entry in sources.entries) {
      chunks.addAll(await _loadChunksFromAsset(entry.key, entry.value));
    }
    return chunks;
  }

  Future<List<Chunk>> _loadChunksFromAsset(String source, String assetPath) async {
    final content = await rootBundle.loadString(assetPath);
    return _splitIntoChunks(content, source, assetPath);
  }

  // Walks through the document line by line and starts a new chunk each time
  // it finds a level-2 heading (##). Everything under that heading belongs to
  // that chunk until the next heading appears.
  List<Chunk> _splitIntoChunks(String content, String source, String assetPath) {
    final chunks = <Chunk>[];
    String currentHeading = '';
    final currentLines = <String>[];

    for (final line in content.split('\n')) {
      if (line.startsWith('## ')) {
        if (currentHeading.isNotEmpty && currentLines.isNotEmpty) {
          chunks.add(Chunk(
            heading: currentHeading,
            text: currentLines.join('\n').trim(),
            source: source,
            assetPath: assetPath,
          ));
          currentLines.clear();
        }
        currentHeading = line.substring(3).trim();
      } else if (currentHeading.isNotEmpty) {
        currentLines.add(line);
      }
    }

    if (currentHeading.isNotEmpty && currentLines.isNotEmpty) {
      chunks.add(Chunk(
        heading: currentHeading,
        text: currentLines.join('\n').trim(),
        source: source,
        assetPath: assetPath,
      ));
    }

    return chunks;
  }
}
