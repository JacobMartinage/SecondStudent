// lib/pages/editor/workspace.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'editor/editor.dart';
import 'editor/pdf_viewer_pane.dart';
import 'file_system/file_system_viewer.dart';

class EditorWorkspace extends StatefulWidget {
  const EditorWorkspace({super.key});

  @override
  State<EditorWorkspace> createState() => _EditorWorkspaceState();
}

class _EditorWorkspaceState extends State<EditorWorkspace> {
  final GlobalKey _editorKey = GlobalKey();

  double _leftWidth = 300;
  bool _showSidebar = true;

  File? _currentFile;
  bool get _showingPdf =>
      _currentFile != null && _currentFile!.path.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    _ensureWorkspacePath();
    _restoreLayoutPrefs();
  }

  Future<void> _ensureWorkspacePath() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('path_to_files');
    if (existing != null && existing.trim().isNotEmpty) return;

    String path;
    if (kIsWeb) {
      path = 'web://workspace';
    } else if (Platform.isMacOS) {
      final support = await getApplicationSupportDirectory();
      final ws = Directory(p.join(support.path, 'SecondStudent', 'workspace'));
      if (!await ws.exists()) await ws.create(recursive: true);
      path = ws.path;
    } else if (Platform.isWindows || Platform.isLinux) {
      final docs = await getApplicationDocumentsDirectory();
      final ws = Directory(p.join(docs.path, 'SecondStudent', 'workspace'));
      if (!await ws.exists()) await ws.create(recursive: true);
      path = ws.path;
    } else if (Platform.isIOS || Platform.isAndroid) {
      final docs = await getApplicationDocumentsDirectory();
      final ws = Directory(p.join(docs.path, 'workspace'));
      if (!await ws.exists()) await ws.create(recursive: true);
      path = ws.path;
    } else {
      final tmp = await getTemporaryDirectory();
      final ws = Directory(p.join(tmp.path, 'workspace'));
      if (!await ws.exists()) await ws.create(recursive: true);
      path = ws.path;
    }

    await prefs.setString('path_to_files', path);
  }

  Future<void> _restoreLayoutPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _leftWidth = (prefs.getDouble('workspace_left_width') ?? 300).clamp(
        220,
        600,
      );
      _showSidebar = prefs.getBool('workspace_show_sidebar') ?? true;
    });
  }

  Future<void> _persistLayoutPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('workspace_left_width', _leftWidth);
    await prefs.setBool('workspace_show_sidebar', _showSidebar);
  }

  // --- Key change: editor stays mounted; we safely feed it JSON even after a PDF ---
  Future<void> _onFileSelected(File file) async {
    final lower = file.path.toLowerCase();
    _currentFile = file;

    if (lower.endsWith('.pdf')) {
      // Just flip the overlay; do not touch the editor.
      if (mounted) setState(() {});
      return;
    }

    if (lower.endsWith('.json')) {
      try {
        final json = await file.readAsString();

        // If the editor state isn't ready *this frame*, schedule it for next.
        void load() {
          final state = _editorKey.currentState;
          if (state != null) {
            (state as dynamic).loadFromJsonString(json, sourcePath: file.path);
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) => load());
          }
        }

        load();
        if (mounted) setState(() {}); // updates app bar title, etc.
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to open file: $e')));
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Unsupported file type')));
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentFile == null
              ? 'SecondStudent — Workspace'
              : 'SecondStudent — ${p.basename(_currentFile!.path)}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: _showSidebar ? 'Hide sidebar' : 'Show sidebar',
            icon: Icon(
              _showSidebar ? Icons.view_sidebar : Icons.view_sidebar_outlined,
            ),
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
                    if (_currentFile?.path == oldFile.path) {
                      setState(() => _currentFile = newFile);
                    }
                    final state = _editorKey.currentState;
                    if (state != null && !_showingPdf) {
                      try {
                        (state as dynamic).updateCurrentFilePath(newFile.path);
                      } catch (_) {}
                    }
                  },
                ),
              ),
            ),
          if (_showSidebar) divider,

          // --- Key change: keep the editor ALWAYS mounted; overlay the PDF when needed ---
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Editor stays alive even while a PDF is shown
                EditorScreen(key: _editorKey, docId: 'your_doc_id_here'), // Replace 'your_doc_id_here' with the actual document ID

                // Initial hint overlay if nothing selected (optional)
                if (_currentFile == null)
                  IgnorePointer(
                    child: Center(
                      child: Text('Select a JSON or PDF from the left.'),
                    ),
                  ),

                // PDF overlay on top of the editor
                if (_showingPdf)
                  kIsWeb
                      ? const Center(
                          child: Text(
                            'Web PDF viewing from local paths is not supported yet.',
                          ),
                        )
                      : PdfViewerPane(file: _currentFile!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
