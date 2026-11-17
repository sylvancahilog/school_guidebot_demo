# Building the School Guidebot App

This guide walks you through building a Flutter app that lets students ask questions about school documents. The app searches those documents using a keyword algorithm called BM25, and optionally generates a natural language answer using a small AI model that runs entirely on the device.

You will build everything step by step, starting from a blank project and ending with a working app. Each section introduces a small piece of code, explains what it does, then moves on to the next piece.

---

## What the App Does

When a student types a question, the app:

1. Searches the bundled school documents for the most relevant sections.
2. Shows those sections as cards, each with a relevance score.
3. If the AI model is loaded, generates a plain-English answer using those sections as context.

There is no server. The search and the AI both run on the phone.

---

## Prerequisites

- Flutter installed and working (`flutter doctor` reports no errors)
- An Android device connected via USB (the AI model is too heavy for most emulators)
- Basic familiarity with Dart and Flutter widgets

---

## Step 1: Create the Project

```bash
flutter create school_guidebot_demo
cd school_guidebot_demo
```

Open `pubspec.yaml` and replace its `dependencies` and `flutter` sections with the following:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_edge_ai: ^2.6.0
  flutter_edge_ai_litertlm: ^1.20.0
  flutter_markdown: ^0.7.0
  path_provider: ^2.1.0
  http: ^1.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true

  assets:
    - assets/handbook.md
    - assets/policy.md
```

Here is what each dependency does:

- `flutter_edge_ai` and `flutter_edge_ai_litertlm` provide the on-device AI inference engine.
- `flutter_markdown` renders formatted text from Markdown strings inside the app.
- `path_provider` locates the device's documents directory, where the model file is stored.
- `http` streams the model file download from the internet.

Create the `assets/` folder and add two Markdown files: `handbook.md` and `policy.md`. Each file must use `##` (level-2) headings to separate sections. Content before the first `##` heading is ignored by the app.

Example structure for `handbook.md`:

```markdown
## Attendance Policy

Students must attend at least 80% of scheduled classes to be eligible for final exams.

## Grading Scale

A: 90-100, B: 80-89, C: 70-79, D: 60-69, F: below 60.
```

Then run:

```bash
flutter pub get
```

---

## Step 2: Set the Android Minimum SDK

Open `android/app/build.gradle.kts` and set `minSdk` to `24`:

```kotlin
android {
    defaultConfig {
        minSdk = 24
    }
}
```

This is required because the LiteRT inference library targets Android 7 and above.

---

## Step 3: The Data Model

Create `lib/models/chunk.dart`.

The app needs a way to represent one section of a document. Rather than passing around raw strings, we create a small class that bundles all the relevant information together.

Start with the class declaration and its four fields:

```dart
class Chunk {
  final String heading;
  final String text;
  final String source;
  final String assetPath;
```

- `heading` is the text of the `##` line that introduced this section, such as `"Attendance Policy"`.
- `text` is everything that followed that heading until the next one.
- `source` is the human-readable document name, such as `"Handbook"`. This is shown in the UI.
- `assetPath` is the file path, such as `"assets/handbook.md"`. This is used to open the full document viewer.

Add the constructor:

```dart
  const Chunk({
    required this.heading,
    required this.text,
    required this.source,
    required this.assetPath,
  });
}
```

The constructor is `const` because all four fields are `final`, which means a `Chunk` can never change after it is created. This is called an immutable data class.

**Why chunks?** Searching a whole document at once makes it hard to point to the exact relevant part. By splitting each document into small sections at every `##` heading, the search can return a focused excerpt instead of an entire file.

---

## Step 4: Document Service

Create `lib/services/document_service.dart`. This service loads the Markdown files from the app bundle and splits them into `Chunk` objects.

Add the imports at the top:

```dart
import 'package:flutter/services.dart';
import '../models/chunk.dart';
```

`rootBundle` from `flutter/services.dart` is Flutter's way to read files that are bundled with the app.

### 4.1. The sources map

The class starts with a static map that lists every document the app knows about:

```dart
class DocumentService {
  static const Map<String, String> sources = {
    'Handbook': 'assets/handbook.md',
    'School Policy': 'assets/policy.md',
  };
```

`static const` means this map belongs to the class itself, not to any particular instance. Any part of the app can read `DocumentService.sources` without needing to create a `DocumentService` object first. The map is the single place you need to edit when adding a new document.

### 4.2. Loading all chunks

Add the public method that iterates over every entry in `sources` and collects the results:

```dart
  Future<List<Chunk>> loadAllChunks() async {
    final chunks = <Chunk>[];
    for (final entry in sources.entries) {
      chunks.addAll(await _loadChunksFromAsset(entry.key, entry.value));
    }
    return chunks;
  }
```

This is the only method the rest of the app ever calls. It delegates the actual work to a private helper so the loop itself stays readable.

### 4.3. Reading one file

The private helper loads one file by its asset path and passes the raw text to the splitter:

```dart
  Future<List<Chunk>> _loadChunksFromAsset(String source, String assetPath) async {
    final content = await rootBundle.loadString(assetPath);
    return _splitIntoChunks(content, source, assetPath);
  }
```

`rootBundle.loadString` reads the file from the app bundle and returns its full text as a `String`. This is an asynchronous operation because reading files can take a moment on slow devices, so it returns a `Future`.

### 4.4. Splitting the text into chunks

This is the most important method in the service. It walks through the document line by line and starts a new chunk each time it finds a `##` heading:

```dart
  List<Chunk> _splitIntoChunks(String content, String source, String assetPath) {
    final chunks = <Chunk>[];
    String currentHeading = '';
    final currentLines = <String>[];
```

Two variables track the state as we scan through the file: `currentHeading` holds the heading we are currently underneath, and `currentLines` accumulates the lines of text that belong to it.

Now the main loop:

```dart
    for (final line in content.split('\n')) {
      if (line.startsWith('## ')) {
```

We split the whole document into lines and check each one. If a line starts with `## `, we have found the start of a new section.

When a new heading is found, we first save whatever we have been accumulating:

```dart
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
```

`line.substring(3)` strips the `## ` prefix (3 characters) to get the heading text. We clear `currentLines` so it is ready to collect lines for the new section.

If a line is not a heading, and we are inside a section, we add it to the current section's lines:

```dart
      } else if (currentHeading.isNotEmpty) {
        currentLines.add(line);
      }
    }
```

The `currentHeading.isNotEmpty` guard skips anything that appears before the first `##` heading in the file.

After the loop, there is one more chunk to save: the final section in the file has no following heading to trigger the save, so we handle it manually:

```dart
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
```

---

## Step 5: Search Service (BM25)

Create `lib/services/search_service.dart`. This is the core of the search feature.

Add the imports:

```dart
import 'dart:math';
import '../models/chunk.dart';
```

`dart:math` is needed for the `log` function used in the BM25 formula.

### 5.1. The SearchResult class

Before the main service class, define a small data class to pair a chunk with its relevance score:

```dart
class SearchResult {
  final Chunk chunk;
  final double score;

  const SearchResult({required this.chunk, required this.score});
}
```

This keeps results self-contained. Any widget that receives a `SearchResult` has both the content to display and the score to show.

### 5.2. The service class and its constants

```dart
class SearchService {
  static const double _scoreThreshold = 0.1;
  static const int _maxResults = 2;
  static const double _bm25K1 = 1.5;
  static const double _bm25B = 0.75;
```

These four constants control how search works:

- `_scoreThreshold`: any chunk scoring below `0.1` is considered not relevant and is filtered out.
- `_maxResults`: at most 2 chunks are returned, keeping the results focused.
- `_bm25K1 = 1.5`: controls how much repeating a word boosts the score. At 1.5, a word appearing 10 times is not 10 times better than one appearance; the benefit flattens out.
- `_bm25B = 0.75`: controls length normalization. A long chunk that happens to mention the search word many times is penalized slightly, so a short and focused chunk can still win.

Add the three instance fields that hold the search index:

```dart
  List<Chunk> _chunks = [];
  Map<String, double> _idfByTerm = {};
  double _avgDocLength = 0;
```

`_idfByTerm` maps each word to its IDF weight. IDF stands for Inverse Document Frequency: a word that appears in almost every chunk (like "the") gets a low weight, and a word that appears in only one chunk gets a high weight. `_avgDocLength` holds the mean token count across all chunks, pre-computed at index time so every scoring call can read it in O(1) rather than recomputing it.

### 5.3. Tokenizing text

Before we can build the index or score a query, we need a way to turn raw text into a list of words. Add this private method:

```dart
  List<String> _tokenize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.length > 2)
      .toList();
```

Reading it left to right:
1. `.toLowerCase()` makes search case-insensitive.
2. `.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')` replaces every punctuation mark with a space, so `"policy."` and `"policy"` become the same token.
3. `.split(RegExp(r'\s+'))` splits on any run of whitespace.
4. `.where((word) => word.length > 2)` drops very short words like `"a"`, `"is"`, and `"of"` that carry no meaning.

### 5.4. Computing IDF weights

This method is called once when building the index. It scans every chunk to count how many chunks each word appears in:

```dart
  Map<String, double> _computeIdf(List<Chunk> chunks) {
    final documentFrequency = <String, int>{};
    for (final chunk in chunks) {
      for (final term in _tokenize(chunk.text).toSet()) {
        documentFrequency[term] = (documentFrequency[term] ?? 0) + 1;
      }
    }
```

`.toSet()` deduplicates the tokens for each chunk. Without it, a chunk that mentions "attendance" ten times would add 10 to its document frequency count instead of 1. We want to count how many *chunks* a word appears in, not how many *times* it appears total.

Then convert the counts into IDF scores using the standard formula:

```dart
    final totalDocs = chunks.length.toDouble();
    return documentFrequency.map((term, freq) =>
        MapEntry(term, log((totalDocs - freq + 0.5) / (freq + 0.5) + 1)));
  }
```

The formula `log((N - df + 0.5) / (df + 0.5) + 1)` produces a high value when `freq` is small (the word is rare) and a low value when `freq` is close to `N` (the word appears in nearly every chunk). The `+ 1` before the `log` ensures the score is always positive.

### 5.5. Building the index

```dart
  Future<void> buildIndex(List<Chunk> chunks) async {
    _chunks = chunks;
    _idfByTerm = _computeIdf(chunks);
    _avgDocLength = chunks
            .map((chunk) => _tokenize(chunk.text).length)
            .reduce((sum, length) => sum + length) /
        chunks.length;
  }
```

This stores all the chunks and pre-computes two values that every scoring call needs: the IDF weights and the average document length. Both are computed once at startup so `_scoreBm25` can read them directly without repeating work for every chunk it scores.

### 5.6. Scoring one chunk with BM25

```dart
  double _scoreBm25(List<String> queryTerms, String documentText) {
    final avgDocLength = _avgDocLength;
```

`_avgDocLength` was pre-computed in `buildIndex`, so reading it here is a simple field access. This keeps each scoring call proportional to the chunk's own length rather than re-scanning all chunks every time. The value normalizes scores: a long chunk that mentions the search word three times is not necessarily more relevant than a short chunk that mentions it once.

```dart
    final docTokens = _tokenize(documentText);
    final docLength = docTokens.length.toDouble();
    final termFrequency = <String, int>{};
    for (final term in docTokens) {
      termFrequency[term] = (termFrequency[term] ?? 0) + 1;
    }
```

We tokenize the chunk and count how many times each word appears in it. This is the term frequency (TF) for this particular document.

```dart
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
```

For each unique word in the query:
- If the word does not appear in this chunk at all (`tf == 0`), skip it.
- Otherwise, combine its TF and IDF using the BM25 formula. The denominator contains the length normalization term: `_bm25B * docLength / avgDocLength` grows when the chunk is longer than average, which slightly reduces its score.

### 5.7. Running a search

```dart
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
}
```

This maps every chunk to a `SearchResult` with its BM25 score, filters out weak matches, sorts by score descending, and returns only the top two. The `..sort(...)` syntax is a Dart cascade: it sorts the list in place and returns the same list, allowing the whole chain to be one expression.

---

## Step 6: AI Service (On-Device Inference)

Create `lib/services/gemma_service.dart`. This service handles downloading, loading, and running the Qwen3 0.6B language model.

Add the imports:

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'search_service.dart';
```

### 6.1. Constants and fields

```dart
class GemmaService {
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
```

- `_modelFilename` is the name used to save and load the file on the device.
- `_modelDownloadUrl` points to the exact model file version on Hugging Face. Pinning to a specific commit hash in the URL ensures the app always downloads the same file.
- `_systemPrompt` tells the model what role it is playing. This message is sent before every conversation.
- `_model` holds the loaded model, or `null` if the model has not been loaded yet. The `?` after `InferenceModel` is Dart's null-safety syntax.

**Why not bundle the model?** At roughly 345 MB, including the model file in the app would make it too large to install over a mobile data connection. Downloading it once to the device's documents directory keeps the app small.

### 6.2. Checking if the model is already present

```dart
  Future<bool> checkModelPresent() async {
    final dir = await getApplicationDocumentsDirectory();
    _isAvailable = File('${dir.path}/$_modelFilename').existsSync();
    return _isAvailable;
  }
```

`getApplicationDocumentsDirectory()` returns a directory that persists across app restarts and is private to this app. If the file already exists there, the model was downloaded in a previous session and can be loaded immediately.

### 6.3. Loading the model into memory

```dart
  Future<void> loadModel() async {
    if (!_isAvailable) return;
    final dir = await getApplicationDocumentsDirectory();
    await FlutterEdgeAi.installModel(
      modelType: ModelType.qwen3,
      fileType: ModelFileType.litertlm,
    ).fromFile('${dir.path}/$_modelFilename').install();
    _model = await FlutterEdgeAi.getActiveModel(maxTokens: 1024);
  }
```

`FlutterEdgeAi.installModel` registers the file with the LiteRT engine. `getActiveModel` then returns a handle to the loaded model, which is stored in `_model` for use in `generateAnswer`. `maxTokens: 1024` sets the total token budget for a single conversation turn.

### 6.4. Downloading the model with progress updates

This method needs to report progress to the UI while it is running, so instead of returning a value directly, it accepts three callback functions:

```dart
  Future<void> downloadModel({
    required void Function(double progress) onProgress,
    required void Function() onComplete,
    required void Function(String error) onError,
  }) async {
```

- `onProgress` is called repeatedly during the download with a value from 0.0 to 1.0.
- `onComplete` is called when the file is fully saved.
- `onError` is called if anything goes wrong.

Inside the method, we use a streaming HTTP request so we can track the number of bytes received:

```dart
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelFile = File('${dir.path}/$_modelFilename');
      final request = http.Request('GET', Uri.parse(_modelDownloadUrl));
      final response = await http.Client().send(request);
      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = modelFile.openWrite();
```

`http.Client().send(request)` sends the request and returns a streaming response, meaning the bytes arrive in chunks rather than all at once. `modelFile.openWrite()` opens a write stream to the destination file.

```dart
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
```

Each incoming byte chunk is written to the file and counted. Dividing `receivedBytes` by `totalBytes` gives the fraction of the download that is complete. `.asFuture()` converts the stream subscription into a `Future` so we can `await` the full download finishing.

### 6.5. Generating an answer

This method uses a Dart generator function, indicated by `async*`. Instead of returning a single value, it uses `yield` to emit one token at a time:

```dart
  Stream<String> generateAnswer(String question, List<SearchResult> results) async* {
    if (_model == null) return;
```

First, the retrieved chunks are assembled into a context block:

```dart
    final contextText = results
        .map((result) => '[${result.chunk.source}] ${result.chunk.heading}:\n${result.chunk.text}')
        .join('\n\n');
```

Each chunk is formatted as `[Handbook] Attendance Policy:\n...text...`. Labeling each section with its source name helps the model cite where it got the information.

Then the prompt is assembled:

```dart
    final userMessage = contextText.isNotEmpty
        ? 'Document Context:\n$contextText\n\nStudent Question: $question'
        : question;
```

If there were matching chunks, the user's question is prefixed with the retrieved content. If no chunks matched, the question is sent on its own. This technique is called Retrieval-Augmented Generation (RAG): the model is given specific text to draw from instead of relying only on what it learned during training.

A chat session is opened and the message is sent:

```dart
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
```

`generateChatResponseAsync()` returns a stream of response objects. Each `TextResponse` carries one token (a word fragment). We `yield` it immediately, which sends it to whoever is listening to our `Stream<String>`. The `finally` block ensures the chat session is always closed, even if an error occurs.

### 6.6. Cleanup

```dart
  void dispose() {
    _model?.close();
    _model = null;
  }
}
```

`dispose` releases the model from memory when the screen is removed. The `?.` is Dart's null-safe call: it only calls `.close()` if `_model` is not null.

---

## Step 7: Widgets

Create the following widget files in `lib/widgets/`.

### `loading_view.dart`

This widget shows a spinner and a status message during startup. It is a `StatelessWidget` because it has no state of its own; it just renders whatever `message` it receives.

```dart
import 'package:flutter/material.dart';

class LoadingView extends StatelessWidget {
  final String message;

  const LoadingView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}
```

`mainAxisAlignment: MainAxisAlignment.center` vertically centers the column's contents on screen.

---

### `result_card.dart`

This card displays one matched document section. It needs local state to track whether the card is expanded, so it is a `StatefulWidget`.

Start with the widget class and its single field:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/search_service.dart';

class ResultCard extends StatefulWidget {
  final SearchResult result;

  const ResultCard({super.key, required this.result});

  @override
  State<ResultCard> createState() => _ResultCardState();
}
```

The state class holds two values:

```dart
class _ResultCardState extends State<ResultCard> {
  static const int _previewLength = 300;
  bool _isExpanded = false;
```

`_previewLength` caps how many characters are shown before the "Show more" link appears. `_isExpanded` tracks whether the full text is visible.

In `build`, the first thing to prepare is the display values:

```dart
  @override
  Widget build(BuildContext context) {
    final chunk = widget.result.chunk;
    final scoreLabel = '${(widget.result.score.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%';
    final isLong = chunk.text.length > _previewLength;
    final displayText = (isLong && !_isExpanded)
        ? '${chunk.text.substring(0, _previewLength)}...'
        : chunk.text;
```

`.clamp(0.0, 1.0)` ensures the score stays within range before multiplying by 100. BM25 scores can exceed 1.0 for very strong matches, so we clamp to avoid showing `"150%"`. `displayText` is either the full text or the first 300 characters, depending on `_isExpanded`.

The card is a `Column` with two rows: a header row with the source label and score badge, and the body text below:

```dart
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
```

`Expanded` on the source label pushes the score badge to the right edge of the row.

Then the body text and the expand toggle:

```dart
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
```

`if (isLong) ...[...]` only shows the toggle link when the text was truncated. `setState(() => _isExpanded = !_isExpanded)` flips the boolean and triggers a rebuild, which causes `displayText` to recalculate and show the full text.

---

### `answer_card.dart`

This card shows the AI-generated answer and the source chunks below it. It is a `StatelessWidget` because it only displays data it receives; it has no state of its own.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/search_service.dart';
import 'result_card.dart';

class AnswerCard extends StatelessWidget {
  final String answer;
  final List<SearchResult> sources;

  const AnswerCard({super.key, required this.answer, required this.sources});
```

The `build` method has two parts: the answer card at the top, and the sources list below it.

The answer card uses a light indigo background to visually separate it from the white screen, and renders the answer text as Markdown so the model can use formatting like bold or lists:

```dart
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
```

Below the answer, the sources list is only shown when there are matching chunks:

```dart
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
```

`...sources.map(...)` spreads the list of `ResultCard` widgets directly into the `Column`'s children list.

---

### `model_download_widget.dart`

This full-screen widget is shown on first launch. It manages its own download state, so it is a `StatefulWidget`.

The state class tracks three things:

```dart
import 'package:flutter/material.dart';
import '../services/gemma_service.dart';

class ModelDownloadWidget extends StatefulWidget {
  final GemmaService gemmaService;
  final VoidCallback onSkip;
  final VoidCallback onReady;

  const ModelDownloadWidget({
    super.key,
    required this.gemmaService,
    required this.onSkip,
    required this.onReady,
  });

  @override
  State<ModelDownloadWidget> createState() => _ModelDownloadWidgetState();
}

class _ModelDownloadWidgetState extends State<ModelDownloadWidget> {
  double _progress = 0;
  bool _downloading = false;
  String? _error;
```

- `_progress` is a value from 0.0 to 1.0 updated as bytes arrive.
- `_downloading` is true while the download is in progress.
- `_error` holds an error message if the download fails, or `null` otherwise.

The `_startDownload` method wires up the three callbacks from `GemmaService.downloadModel`:

```dart
  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
    });

    await widget.gemmaService.downloadModel(
      onProgress: (p) => setState(() => _progress = p),
      onComplete: () async {
        await widget.gemmaService.loadModel();
        widget.onReady();
      },
      onError: (e) => setState(() {
        _error = 'Download failed: $e';
        _downloading = false;
      }),
    );
  }
```

Each callback calls `setState` to trigger a rebuild with the latest status. When `onComplete` fires, `loadModel()` is awaited before calling `onReady()` so the model is fully in memory when the parent screen transitions to the ready state.

The `build` method shows different UI depending on the state. When `_downloading` is true, it shows a progress bar. Otherwise it shows the action buttons:

```dart
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.download_for_offline_outlined, size: 64, color: Colors.indigo),
          const SizedBox(height: 16),
          const Text(
            'Qwen3 0.6B Model Required',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'To generate natural language answers, the app needs to download the Qwen3 0.6B model (~345 MB). This requires an internet connection and sufficient storage space.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_downloading) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
            Text(
              _progress > 0
                  ? 'Downloading... ${(_progress * 100).toStringAsFixed(0)}%'
                  : 'Starting download...',
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.download),
                label: Text(_error != null ? 'Retry Download' : 'Download Qwen3 0.6B (~345 MB)'),
                onPressed: _startDownload,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onSkip,
                child: const Text('Skip -- Use Retrieval Only'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

`LinearProgressIndicator(value: _progress > 0 ? _progress : null)` shows a determinate bar (a filled portion) once bytes start arriving, and an indeterminate animation (a bouncing bar) while waiting for the connection to open.

---

### `gemma_banner.dart`

This is a compact version of the download widget that lives at the bottom of the main screen. It appears only when the user chose to skip the initial download prompt. Because it has three distinct visual states (idle, downloading, loading the model), we represent them with an enum:

```dart
import 'package:flutter/material.dart';
import '../services/gemma_service.dart';

enum DownloadState { idle, downloading, loadingModel }
```

The widget and its state class:

```dart
class GemmaBanner extends StatefulWidget {
  final GemmaService gemmaService;
  final VoidCallback onReady;

  const GemmaBanner({
    super.key,
    required this.gemmaService,
    required this.onReady,
  });

  @override
  State<GemmaBanner> createState() => _GemmaBannerState();
}

class _GemmaBannerState extends State<GemmaBanner> {
  DownloadState _downloadState = DownloadState.idle;
  double _downloadProgress = 0;
  String? _downloadError;
```

The download logic is the same as in `ModelDownloadWidget`, but it also transitions through the `loadingModel` state to show a spinner while the model is being loaded into memory after the download finishes:

```dart
  Future<void> _startDownload() async {
    setState(() {
      _downloadState = DownloadState.downloading;
      _downloadProgress = 0;
      _downloadError = null;
    });

    await widget.gemmaService.downloadModel(
      onProgress: (p) => setState(() => _downloadProgress = p),
      onComplete: () async {
        setState(() => _downloadState = DownloadState.loadingModel);
        await widget.gemmaService.loadModel();
        widget.onReady();
      },
      onError: (e) => setState(() {
        _downloadError = 'Download failed: $e';
        _downloadState = DownloadState.idle;
      }),
    );
  }
```

The `build` method uses a `switch` expression directly inside the widget tree to choose which banner content to render:

```dart
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
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AI answers not available',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.indigo.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _downloadError ?? 'Download Qwen3 0.6B to enable natural language answers.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _downloadError != null ? Colors.red.shade700 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download, size: 16),
                    label: Text(
                      _downloadError != null
                          ? 'Retry Download (~345 MB)'
                          : 'Download Qwen3 0.6B (~345 MB)',
                    ),
                    onPressed: _startDownload,
                  ),
                ),
              ],
            ),
          DownloadState.downloading => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _downloadProgress > 0
                      ? 'Downloading... ${(_downloadProgress * 100).toStringAsFixed(0)}%'
                      : 'Starting download...',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                ),
              ],
            ),
          DownloadState.loadingModel => Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading model into memory...',
                  style: TextStyle(fontSize: 13, color: Colors.indigo.shade700),
                ),
              ],
            ),
        },
      ),
    );
  }
}
```

`SafeArea(top: false)` prevents the banner from overlapping system UI at the bottom of the screen (like the home indicator bar on some phones) without adding extra space at the top.

---

### `search_results_view.dart`

This widget decides what to render based on the current state of the search. It is a `StatelessWidget` because it only reads from the values it receives; it never modifies them.

```dart
import 'package:flutter/material.dart';
import '../services/search_service.dart';
import 'result_card.dart';
import 'answer_card.dart';

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
```

The `build` method handles three situations in order:

```dart
  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const Center(child: CircularProgressIndicator());
    }
```

First, if a search is in progress, show a spinner.

```dart
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
```

Second, if there is nothing to show yet, display a placeholder. The two messages are distinct: one for when the user has not searched yet, and one for when a search returned nothing.

```dart
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
```

Third, if there are results (or generation is in progress), show the content. When the model is loaded, show the `AnswerCard` with an italic placeholder while tokens are still streaming in. When the model is not loaded, show the raw result cards directly.

---

### `query_view.dart`

This widget is the main layout of the ready state: a text field and button at the top, results in the middle, and an optional download banner at the bottom.

```dart
import 'package:flutter/material.dart';
import '../services/gemma_service.dart';
import '../services/search_service.dart';
import 'search_results_view.dart';
import 'gemma_banner.dart';

class QueryView extends StatelessWidget {
  final TextEditingController queryController;
  final VoidCallback onSubmit;
  final bool searching;
  final bool generating;
  final bool noResults;
  final bool modelLoaded;
  final List<SearchResult> results;
  final String streamedAnswer;
  final GemmaService? gemmaService;
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
    this.gemmaService,
    this.onModelReady,
  });
```

`gemmaService` and `onModelReady` are optional (`this.` without `required`) because the banner that uses them is only shown in one scenario.

The `build` method returns a `Column` with three layers:

```dart
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. The search bar and Ask button
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
        // 2. The results area, which fills all remaining space
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
        // 3. The optional download banner at the bottom
        if (!modelLoaded && gemmaService != null && onModelReady != null)
          GemmaBanner(gemmaService: gemmaService!, onReady: onModelReady!),
      ],
    );
  }
}
```

`onPressed: (searching || generating) ? null : onSubmit` disables the button while work is in progress. In Flutter, setting `onPressed` to `null` automatically renders the button in a disabled visual state.

`textInputAction: TextInputAction.search` changes the keyboard's return key to show a search icon, and `onSubmitted: (_) => onSubmit()` fires the same action when the user taps it.

---

## Step 8: Screens

### `lib/screens/document_screen.dart`

This screen loads a Markdown file and renders it as formatted text. It uses a `FutureBuilder` to handle the asynchronous file load.

Start with the widget declaration:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class DocumentScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const DocumentScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}
```

In the state class, `initState` starts loading the file immediately when the screen appears:

```dart
class _DocumentScreenState extends State<DocumentScreen> {
  late Future<String> _content;

  @override
  void initState() {
    super.initState();
    _content = rootBundle.loadString(widget.assetPath);
  }
```

`late` tells Dart that `_content` will be assigned before it is ever read, even though it cannot be assigned in the declaration. Calling `loadString` here (not inside `build`) means the load starts once and the same future is reused on every rebuild.

The `FutureBuilder` in `build` watches that future and renders different UI depending on whether it is pending, completed, or failed:

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _content,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error loading document: ${snapshot.error}'));
            }
            return Markdown(
              data: snapshot.data!,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            );
          },
        ),
      ),
    );
  }
}
```

---

### `lib/screens/home_screen.dart`

This is the root screen. It owns all the app state and coordinates the three services.

#### The state enum

Before the class, define an enum for the three phases the app can be in:

```dart
import 'package:flutter/material.dart';
import '../services/document_service.dart';
import '../services/search_service.dart';
import '../services/gemma_service.dart';
import '../widgets/model_download_widget.dart';
import '../widgets/loading_view.dart';
import '../widgets/query_view.dart';
import 'document_screen.dart';

enum _AppState { loading, awaitingModelDownload, ready }
```

Using an enum instead of a boolean or string makes the transitions explicit. You cannot accidentally be in an invalid state like `loading = false, awaitingDownload = false, ready = false` all at once.

#### The widget and its fields

```dart
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _queryController = TextEditingController();
  final _documentService = DocumentService();
  final _searchService = SearchService();
  final _gemmaService = GemmaService();

  _AppState _appState = _AppState.loading;
  String _loadingMessage = 'Indexing documents...';
  bool _modelLoaded = false;

  List<SearchResult> _results = [];
  String _streamedAnswer = '';
  bool _searching = false;
  bool _generating = false;
  bool _noResults = false;
```

The three services are created as fields so they persist across rebuilds. `_streamedAnswer` accumulates tokens as they arrive from the model; each new token triggers a `setState`, which causes the `AnswerCard` to re-render with the growing text.

#### Initialization

```dart
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

    final hasModel = await _gemmaService.checkModelPresent();
    if (hasModel) {
      setState(() => _loadingMessage = 'Loading model...');
      await _gemmaService.loadModel();
      setState(() {
        _modelLoaded = true;
        _appState = _AppState.ready;
      });
    } else {
      setState(() => _appState = _AppState.awaitingModelDownload);
    }
  }
```

Each `setState` call before an `await` updates the loading message so the user sees progress. After the index is built, the app checks whether the model file exists. If it does, the model is loaded immediately and the app moves straight to ready. If not, the app asks the user to download it.

#### Handling a query

```dart
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
      await for (final token in _gemmaService.generateAnswer(query, results)) {
        setState(() => _streamedAnswer += token);
      }
      setState(() => _generating = false);
    }
  }
```

The search and generation are sequential, not parallel. The search runs first so its results can be shown immediately while the model is still generating. Each token from `generateAnswer` is appended to `_streamedAnswer` and triggers a rebuild, making the answer appear word by word.

#### Navigation helpers

```dart
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
```

`_onModelReady` is passed down to child widgets so they can notify this screen when a download completes. `Navigator.push` slides the `DocumentScreen` on top of the current screen; the back button in the app bar will slide it back off.

#### The build method

```dart
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
          gemmaService: _gemmaService,
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
          gemmaService: _gemmaService,
          onModelReady: _onModelReady,
        );
    }
  }
```

`_buildBody` uses a switch on `_appState` to return exactly one widget for each state. The `PopupMenuButton` in the app bar builds its menu items directly from `DocumentService.sources.keys`, so it will automatically include any new documents you add to that map.

#### Cleanup

```dart
  @override
  void dispose() {
    _queryController.dispose();
    _gemmaService.dispose();
    super.dispose();
  }
}
```

Always dispose of controllers and services that hold resources. `TextEditingController` holds a text listener, and `GemmaService` holds the loaded model in memory.

---

## Step 9: Entry Point

Replace `lib/main.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterEdgeAi.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
  );
  runApp(const SchoolGuidebotApp());
}

class SchoolGuidebotApp extends StatelessWidget {
  const SchoolGuidebotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'School Guide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
```

Two things to notice here:

- `WidgetsFlutterBinding.ensureInitialized()` must be called before any `async` work in `main`. Flutter needs to set up its internal bindings before plugins and native platform channels can be used.
- The LiteRT engine is registered here once, before any screen loads, so the rest of the app can use it without repeating the setup call.

---

## Step 10: Run the App

Connect a physical Android device and run:

```bash
flutter run
```

On first launch:
- The loading screen appears while documents are indexed.
- The model download prompt appears. Tap **Download Qwen3 0.6B** or **Skip** to continue in retrieval-only mode.
- Once in the ready state, type a question in the search bar and tap **Ask**.

---

## Final Project Structure

```
lib/
  main.dart
  models/
    chunk.dart
  services/
    document_service.dart
    search_service.dart
    gemma_service.dart
  screens/
    home_screen.dart
    document_screen.dart
  widgets/
    loading_view.dart
    model_download_widget.dart
    query_view.dart
    search_results_view.dart
    answer_card.dart
    result_card.dart
    gemma_banner.dart

assets/
  handbook.md
  policy.md
```

---

## Adding Your Own Documents

1. Add a Markdown file to `assets/` and register it in `pubspec.yaml` under `assets:`.
2. Add an entry to the `sources` map in `lib/services/document_service.dart`:

```dart
static const Map<String, String> sources = {
  'Handbook': 'assets/handbook.md',
  'School Policy': 'assets/policy.md',
  'Rules': 'assets/rules.md', // new
};
```

The document will be indexed automatically on the next launch and will appear in the app bar menu.

Documents must use `##` level-2 headings to separate sections. Each section between two `##` headings becomes one searchable chunk. Content before the first `##` is ignored.

---

## Concepts Recap

| Concept | Where it appears |
|---|---|
| Chunking | `DocumentService._splitIntoChunks` splits files at `##` headings |
| BM25 | `SearchService` ranks chunks by keyword relevance |
| Index pre-computation | `SearchService.buildIndex` runs once at startup, caching IDF weights and average document length |
| On-device inference | `GemmaService` runs Qwen3 entirely on the device via LiteRT |
| RAG | `GemmaService.generateAnswer` injects retrieved chunks into the prompt |
| Streaming generation | `generateAnswer` is an `async*` generator, yielding one token at a time |
| App state machine | `_AppState` in `HomeScreen` controls which screen is shown |
