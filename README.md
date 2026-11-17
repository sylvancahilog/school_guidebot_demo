# School Guidebot Demo

A Flutter app that lets students ask questions about school documents. It combines BM25 keyword search over locally bundled Markdown files with an optional on-device LLM (Qwen3 0.6B via LiteRT) that generates natural language answers grounded in the retrieved content.

---

## How It Works

### App States

| State | Behaviour |
|---|---|
| **Loading** | Parses and indexes all Markdown documents on startup. |
| **Awaiting Model Download** | Shown on first launch if the Qwen3 model is absent. The user can download it or skip to retrieval-only mode. |
| **Ready (retrieval only)** | BM25 search returns the top 2 most relevant document sections with source labels and relevance scores. |
| **Ready (with generation)** | Same BM25 search, but the top chunks are passed to Qwen3 as context. The model streams a natural language answer. If no chunks score above the threshold, the model answers conversationally from general knowledge. |

The app starts in the generation state if the Qwen3 model is already present on the device; otherwise it prompts for a download.

### Search: BM25

`SearchService` uses BM25 (k1 = 1.5, b = 0.75) over the tokenized text of every chunk. Each document is split into chunks at every `##` heading boundary by `DocumentService`. The IDF weights are computed once at index-build time. Only results above a score threshold of `0.1` are returned; the top 2 are passed to the LLM.

### Generation: Qwen3 0.6B on-device

`QwenService` wraps the `flutter_edge_ai` / `flutter_edge_ai_litertlm` packages. The model runs entirely on-device via LiteRT (formerly LiteRT / TFLite). No network call is made during inference. The model file (~345 MB) is downloaded once from Hugging Face and stored in the app's documents directory.

---

## Setup

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Run the app

```bash
flutter run
```

Targets Android only. `minSdkVersion` is set to 24 in `android/app/build.gradle.kts`.

> Test on a **physical Android device**. The LiteRT inference engine and the model's memory footprint make emulators unreliable.

### 3. Download the Qwen3 model (optional)

The model is **not bundled** with the app. On first launch, if the model file is absent, the app shows a download prompt. Tap **Download Qwen3 0.6B** to fetch it over the network (~345 MB). You can tap **Skip** to use retrieval-only mode instead; the model can be downloaded later from the banner that appears at the bottom of the main screen.

---

## Adding New Documents

1. Add your Markdown file to `assets/` (e.g. `assets/rules.md`).
2. Register it in `pubspec.yaml`:
   ```yaml
   assets:
     - assets/rules.md
   ```
3. Add one entry to the `sources` map in `lib/services/document_service.dart`:
   ```dart
   static const Map<String, String> sources = {
     'Handbook': 'assets/handbook.md',
     'School Policy': 'assets/policy.md',
     'Rules': 'assets/rules.md', // ← add this
   };
   ```

No other changes are needed. The document will be indexed on next launch and will appear in the **View documents** menu automatically.

### Document format requirements

Documents must use `##` (level-2) headings to delimit sections. Each section between two `##` headings becomes one searchable chunk. Content before the first `##` heading is ignored. Standard Markdown formatting within sections (bold, lists, etc.) is rendered in both the result cards and the full-document viewer.

---

## Project Structure

```
lib/
  main.dart                       # Initialises LiteRT engine, runs the app
  models/
    chunk.dart                    # Immutable data class for a document section
  services/
    document_service.dart         # Loads assets, splits Markdown into chunks at ## headings
    search_service.dart           # BM25 index: buildIndex(), search()
    qwen_service.dart             # Qwen3 wrapper: checkModelPresent(), loadModel(),
                                  #   downloadModel(), generateAnswer()
  screens/
    home_screen.dart              # Root screen; owns all state, drives _AppState transitions
    document_screen.dart          # Full-document Markdown viewer (opened from AppBar menu)
  widgets/
    loading_view.dart             # Spinner shown during startup indexing
    model_download_widget.dart    # Full-screen download prompt shown on first launch
    query_view.dart               # Search bar + results area + optional QwenBanner
    search_results_view.dart      # Switches between placeholder, AnswerCard, and ResultCard list
    answer_card.dart              # Rendered Markdown answer + collapsible sources list
    result_card.dart              # Single chunk card with score badge and expand/collapse
    qwen_banner.dart              # Persistent bottom banner offering model download mid-session

assets/
  handbook.md                     # Sample school handbook (chunked by ## headings)
  policy.md                       # Sample school policy  (chunked by ## headings)
```

### State flow

```
App launch
  └─ _initialize()
       ├─ loadAllChunks()   → DocumentService parses Markdown assets
       ├─ buildIndex()      → SearchService computes IDF weights
       └─ checkModelPresent()
            ├─ present  → loadModel() → _AppState.ready (modelLoaded: true)
            └─ absent   → _AppState.awaitingModelDownload
                              ├─ user downloads → loadModel() → _AppState.ready (modelLoaded: true)
                              └─ user skips    → _AppState.ready (modelLoaded: false)

_submitQuery()
  ├─ search() → top-2 BM25 chunks (may be empty)
  └─ modelLoaded? → generateAnswer(query, chunks) streams tokens into _streamedAnswer
```

---

## Key Dependencies

| Package | Purpose |
|---|---|
| `flutter_edge_ai` | LiteRT inference engine abstraction |
| `flutter_edge_ai_litertlm` | LiteRT LLM backend |
| `flutter_markdown` | Renders Markdown in result cards and the document viewer |
| `path_provider` | Resolves the app documents directory for model storage |
| `http` | Streams the model file download from Hugging Face |
