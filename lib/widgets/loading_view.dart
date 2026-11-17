import 'package:flutter/material.dart';

// A simple centered spinner with a message shown while the app is loading or setting up.
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
