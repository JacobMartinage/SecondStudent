// lib/editor.dart
//
// Minimal FlutterQuill editor wired to RealtimeDoc.
// - Sends local deltas & cursor updates
// - Applies remote deltas
// - Shows simple collaborator "cursor chips" from remote cursor events

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextSelection, KeyEvent, KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:secondstudent/pages/editor/custom_blocks/customblocks.dart';
import 'package:secondstudent/pages/editor/custom_blocks/page_link_service.dart';
import 'package:secondstudent/pages/editor/custom_blocks/pdf_block.dart';
import 'package:secondstudent/pages/editor/custom_blocks/iframe_block.dart';

import '../slash_menu/slash_menu.dart';
import '../slash_menu/slash_menu_action.dart';
import '../slash_menu/custom_slash_menu_items.dart';
import '../slash_menu/default_slash_menu_items.dart';
import 'receive_blocks.dart';
import '../template.dart';


class EditorScreen extends StatefulWidget {
  final String docId; // the shared realtime doc id/topic
  const EditorScreen({super.key, required this.docId});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const String _prefsKey = 'editor_doc_delta';
  final _sp = Supabase.instance.client;

  late QuillController _controller;

  // simple collaborator chips
  final Map<String, _CursorInfo> _cursors = {};
  final _rand = Random();
  Timer? _cursorCleanupTimer;

  // minimal UI state you already had
  String? _currentFilePath;
  bool _isSlashMenuOpen = false;
  String _slashQuery = '';
  final ValueNotifier<int> _slashSelectionIndex = ValueNotifier<int>(0);
  final cb = CustomBlocks();

  // Loading state
  bool _isConnecting = true;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _initializeEditor();
  }

  Future<void> _initializeEditor() async {
    try {
      // Initialize controller first
      await _bootstrapDoc();

      // Create realtime connection
      await _initializeRealtimeDoc();

      // Start cursor cleanup timer
      _startCursorCleanup();

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionError = null;
        });
      }
    } catch (e) {
      debugPrint('Error initializing editor: $e');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionError = 'Failed to connect: $e';
        });
      }
    }
  }

  Future<void> _initializeRealtimeDoc() async {
    final clientId = 'client_${DateTime.now().millisecondsSinceEpoch}_${_rand.nextInt(1 << 32)}';
    final user = _sp.auth.currentUser;

   


  }

  void _handleRemoteCursor({
    required String clientId,
    required String name,
    required int color,
    required int index,
    required int length,
  }) {
    if (!mounted) return;

    setState(() {
      _cursors[clientId] = _CursorInfo(
        name: name,
        color: Color(color),
        index: index,
        length: length,
        lastUpdated: DateTime.now(),
      );
    });
  }

  void _startCursorCleanup() {
    _cursorCleanupTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _cleanupOldCursors(),
    );
  }

  void _cleanupOldCursors() {
    if (!mounted) return;

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(seconds: 30));
    
    bool shouldUpdate = false;
    _cursors.removeWhere((key, cursor) {
      if (cursor.lastUpdated.isBefore(cutoff)) {
        shouldUpdate = true;
        return true;
      }
      return false;
    });
    
    if (shouldUpdate) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _cursorCleanupTimer?.cancel();

    _controller.dispose();
    _slashSelectionIndex.dispose();
    super.dispose();
  }

  // ---------- Local storage (improved error handling) ----------
  Future<void> _bootstrapDoc() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      
      if (raw != null && raw.isNotEmpty) {
        try {
          final ops = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
          _controller = QuillController(
            document: Document.fromJson(ops),
            selection: const TextSelection.collapsed(offset: 0),
          );
          return;
        } catch (e) {
          debugPrint('Error loading from prefs: $e');
          // Fall through to default initialization
        }
      }
    } catch (e) {
      debugPrint('Error accessing shared preferences: $e');
    }
    
    // Initialize with default template
    _controller = QuillController(
      document: Document.fromJson(Template.starterDelta),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deltaJson = jsonEncode(_controller.document.toDelta().toJson());
      await prefs.setString(_prefsKey, deltaJson);
    } catch (e) {
      debugPrint('Error saving to preferences: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving locally: $e')),
        );
      }
    }
  }

  void loadFromJsonString(String jsonString, {String? sourcePath}) {
    try {
      final ops = (jsonDecode(jsonString) as List).cast<Map<String, dynamic>>();
      final newDocument = Document.fromJson(ops);
      
      _controller.replaceText(
        0, 
        _controller.document.length - 1, 
        newDocument.toPlainText(),
        const TextSelection.collapsed(offset: 0),
      );
      
      setState(() {
        _currentFilePath = sourcePath;
      });
      
      _saveToPrefs();
    } catch (e) {
      debugPrint('Error loading JSON: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading file: $e')),
        );
      }
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    if (_isConnecting) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to collaborative session...'),
            ],
          ),
        ),
      );
    }

    if (_connectionError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Connection Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(_connectionError!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isConnecting = true;
                    _connectionError = null;
                  });
                  _initializeEditor();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredItems = _filteredSlashItems;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: Column(
        children: [
          // Toolbar with collaborator chips and connection status
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                FilledButton.tonal(
                  onPressed: _newFromStarter,
                  child: const Text('New File'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: saveToCurrentFile,
                  child: const Text('Save'),
                ),
                const SizedBox(width: 12),
                
                // Connection status indicator
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                
                if (_currentFilePath != null)
                  Flexible(
                    child: Text(
                      'Editing: ${_basename(_currentFilePath!)}',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                const Spacer(),
                
                // Collaborator chips
                if (_cursors.isNotEmpty)
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _cursors.entries.map((e) {
                          final c = e.value;
                          return Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: c.color.withOpacity(0.15),
                              border: Border.all(color: c.color),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '${c.name}: @${c.index}${c.length == 0 ? '' : ' (+${c.length})'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Editor
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  Positioned.fill(
                    child: QuillEditor.basic(
                      controller: _controller,
                      config: QuillEditorConfig(
                        showCursor: true,
                        scrollable: true,
                        autoFocus: true,
                        placeholder: 'Type / to open the command menu.',
                        linkActionPickerDelegate: (ctx, link, isReadOnly) async => 
                            LinkMenuAction.launch,
                        onLaunchUrl: (url) => _handleLaunchUrl(url),
                        embedBuilders: [
                          const PdfEmbedBuilder(),
                          const IframeEmbedBuilder(),
                          ...FlutterQuillEmbeds.editorBuilders(),
                        ],
                      ),
                    ),
                  ),

                  if (_isSlashMenuOpen)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: SlashMenu(
                          items: filteredItems,
                          selectionIndexListenable: _slashSelectionIndex,
                          onSelect: _onSlashSelect,
                          onDismiss: _closeSlashMenu,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLaunchUrl(String url) async {
    try {
      final handled = await PageLinkService.handleLaunchUrl(
        url,
        context: context,
        onOpenJson: (absPath) async {
          final json = await File(absPath).readAsString();
          loadFromJsonString(json, sourcePath: absPath);
        },
      );
      
      if (!handled) {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open link: $e')),
        );
      }
    }
  }

  // ---- Helper methods ----
  Future<void> _newFromStarter() async {
    try {
      final newDocument = Document.fromJson(Template.starterDelta);
      _controller.replaceText(
        0,
        _controller.document.length - 1,
        newDocument.toPlainText(),
        const TextSelection.collapsed(offset: 0),
      );
      
      await _saveToPrefs();
      setState(() {
        _currentFilePath = null;
      });
    } catch (e) {
      debugPrint('Error creating new document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating new document: $e')),
        );
      }
    }
  }

  Future<void> saveToCurrentFile() async {
    if (_currentFilePath == null || _currentFilePath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file bound. Open a JSON file from the list first.')),
      );
      return;
    }
    
    try {
      final jsonString = jsonEncode(_controller.document.toDelta().toJson());
      await File(_currentFilePath!).writeAsString(jsonString);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${_basename(_currentFilePath!)}')),
        );
      }
    } catch (e) {
      debugPrint('Error saving file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isEmpty ? path : parts.last;
  }

  // Slash menu functionality
  List<SlashMenuItemData> get _filteredSlashItems {
    final q = _slashQuery.trim().toLowerCase();
    final defaults = DefaultSlashMeuItems().defaultSlashMenuItems;
    final customs = CustomSlashMenuItems().items;

    bool match(SlashMenuItemData it) {
      if (it.isLabel || it.isSeparator) return false;
      if (q.isEmpty) return true;
      return it.title.toLowerCase().contains(q) || 
             it.subtitle.toLowerCase().contains(q);
    }

    final d = defaults.where(match).toList();
    final c = customs.where(match).toList();

    if (q.isEmpty) {
      if (d.isEmpty) return c;
      if (c.isEmpty) return d;
      return [...d, const SlashMenuItemData.separator(), ...c];
    } else {
      if (d.isEmpty && c.isEmpty) return [];
      if (d.isEmpty) return c;
      if (c.isEmpty) return d;
      return [...d, const SlashMenuItemData.separator(), ...c];
    }
  }

  void _openSlashMenu(String query) {
    setState(() {
      _isSlashMenuOpen = true;
      _slashQuery = query;
      _slashSelectionIndex.value = 0;
    });
  }

  void _closeSlashMenu() {
    setState(() {
      _isSlashMenuOpen = false;
      _slashQuery = '';
      _slashSelectionIndex.value = 0;
    });
  }

  Future<void> _onSlashSelect(SlashMenuAction action) async {
    _closeSlashMenu();
    
    try {
      // Handle the slash menu action
      // Implementation depends on your SlashMenuAction structure
      // You can add specific handling here based on action type
    } catch (e) {
      debugPrint('Error handling slash menu action: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent e) {
    if (!_isSlashMenuOpen) return KeyEventResult.ignored;
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    
    final logicalKey = e.logicalKey;
    if (logicalKey == LogicalKeyboardKey.escape) {
      _closeSlashMenu();
      return KeyEventResult.handled;
    }
    
    return KeyEventResult.ignored;
  }
}

// Collaborator cursor info model
class _CursorInfo {
  final String name;
  final Color color;
  final int index;
  final int length;
  final DateTime lastUpdated;

  _CursorInfo({
    required this.name,
    required this.color,
    required this.index,
    required this.length,
    required this.lastUpdated,
  });
}