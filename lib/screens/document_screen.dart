import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/*
 * A full-screen reader that loads and displays a school document file as formatted text.
 * Students can open this from the menu to read the full handbook or policy
 * without leaving the app.
 */
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

class _DocumentScreenState extends State<DocumentScreen> {
  late Future<String> _content;

  @override
  void initState() {
    super.initState();
    _content = rootBundle.loadString(widget.assetPath);
  }

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
