// lib/pages/editor/workspace.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'pdf_viewer_pane.dart';

import 'editor.dart';
import 'file_system_viewer.dart';
class EditorWorkspace extends StatefulWidget {
  const EditorWorkspace({Key? key}) : super(key: key);

  @override
  State<EditorWorkspace> createState() => _EditorWorkspaceState();
}
class _EditorWorkspaceState extends State<EditorWorkspace> {
  final GlobalKey _editorKey = GlobalKey();
  double _leftWidth = 300;
  bool _showSidebar = true;

  File? _currentFile;           // <- track the selected file
  String? _currentFilePath;     // for rename updates

  bool get _isPdfSelected =>
      _currentFilePath != null &&
      _currentFilePath!.toLowerCase().endsWith('.pdf');

  bool get _isJsonSelected =>
      _currentFilePath != null &&
      _currentFilePath!.toLowerCase().endsWith('.json');

  @override
  void initState() {
    super.initState();
    _ensureWorkspacePath();
    _restoreLayoutPrefs();
  }

  Future<void> _ensureWorkspacePath() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString('path_to_files')?.trim();
      if (existing == null || existing.isEmpty) {
        final docs = await getApplicationDocumentsDirectory();
        final candidate = p.join(docs.path, 'SecondStudent');
        await Directory(candidate).create(recursive: true);
        await prefs.setString('path_to_files', candidate);
      }
    } catch (_) {
      // best-effort; ignore failures
    }
  }

  Future<void> _restoreLayoutPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedWidth = prefs.getDouble('workspace_left_width');
      final savedSidebar = prefs.getBool('workspace_show_sidebar');
      if (!mounted) return;
      setState(() {
        if (savedWidth != null) {
          _leftWidth = savedWidth.clamp(220.0, 600.0);
        }
        if (savedSidebar != null) {
          _showSidebar = savedSidebar;
        }
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _persistLayoutPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('workspace_left_width', _leftWidth);
      await prefs.setBool('workspace_show_sidebar', _showSidebar);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _onFileSelected(File file) async {
    _currentFile = file;
    _currentFilePath = file.path;

    if (_isJsonSelected) {
      try {
        final json = await file.readAsString();
        final state = _editorKey.currentState;
        if (state == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Editor not ready yet.')),
          );
          return;
        }
        (state as dynamic).loadFromJsonString(json, sourcePath: file.path);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open file: $e')),
        );
      }
    } else {
      // For PDFs we just rebuild; PdfViewerPane reads from _currentFile
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final divider = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        setState(() {
          _leftWidth = (_leftWidth + d.delta.dx).clamp(220, 600);
        });
        _persistLayoutPrefs();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: SizedBox(
          width: 8,
          child: Center(
            child: Container(
              width: 2,
              height: 36,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );

    Widget rightPane;
    if (_isPdfSelected && _currentFile != null) {
      rightPane = PdfViewerPane(file: _currentFile!);
    } else {
      // default to editor (works when nothing selected, too)
      rightPane = EditorScreen(key: _editorKey);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SecondStudent — Workspace'),
        actions: [
          IconButton(
            tooltip: _showSidebar ? 'Hide sidebar' : 'Show sidebar',
            icon: Icon(_showSidebar ? Icons.view_sidebar : Icons.view_sidebar_outlined),
            onPressed: () {
              setState(() => _showSidebar = !_showSidebar);
              _persistLayoutPrefs();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (_showSidebar)
            SizedBox(
              width: _leftWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    right: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 1,
                    ),
                  ),
                ),
                child: FileSystemViewer(
                  onFileSelected: _onFileSelected,
                  onFileRenamed: (oldFile, newFile) {
                    // Keep path in sync when user renames a file from the sidebar
                    if (_currentFilePath == oldFile.path) {
                      _currentFilePath = newFile.path;
                      _currentFile = File(newFile.path);
                      // if editor has a method to update the path, call it
                      final state = _editorKey.currentState;
                      if (state != null && _isJsonSelected) {
                        try {
                          (state as dynamic).updateCurrentFilePath(newFile.path);
                        } catch (_) {}
                      } else {
                        setState(() {});
                      }
                    }
                  },
                ),
              ),
            ),
          if (_showSidebar) divider,
          Expanded(child: rightPane),
        ],
      ),
    );
  }
}