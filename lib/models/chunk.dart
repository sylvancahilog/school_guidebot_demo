/*
 * A single section of a school document, holding its heading, text content,
 * and where it came from.
 * Documents are split into chunks so the app can search through small, focused
 * pieces of text rather than comparing a question against an entire file.
 */
class Chunk {
  final String heading;
  final String text;
  final String source;
  final String assetPath;

  const Chunk({
    required this.heading,
    required this.text,
    required this.source,
    required this.assetPath,
  });
}
