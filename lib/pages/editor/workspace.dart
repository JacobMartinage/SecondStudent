// lib/pages/editor/workspace.dart
import 'package:flutter/material.dart';
import 'editor.dart';

class EditorWorkspace extends StatelessWidget {
  const EditorWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SecondStudent — Iframe Test'),
      ),
      body: const EditorScreen(),
    );
  }
}