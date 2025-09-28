// lib/editor.dart — Quill-backed editor with JSON load/save + starter + download
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/flutter_quill.dart' show EmbedBuilder, Embed, EmbedContext;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:secondstudent/pages/editor/customblocks.dart';
import 'package:secondstudent/pages/editor/customBlocks/iframe_block.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'slash_menu/slash_menu.dart';
import 'slash_menu/slash_menu_action.dart';
import 'slash_menu/custom_slash_menu_items.dart';
import 'slash_menu/default_slash_menu_items.dart';
import 'package:secondstudent/pages/editor/customBlocks/iframe_block.dart';



class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const String _prefsKey = 'editor_doc_delta';

  /// A simple starter Quill Delta (JSON) for new docs
  static const List<Map<String, dynamic>> _starterDelta = [
    {
      "insert": "SecondStudent\n",
      "attributes": {"header": 1},
    },
    {"insert": "Type / to open the command menu.\n"},
    {"insert": "\n"},
    {"insert": "• Try a bullet list\n"},
    {"insert": "1. Or a numbered list\n"},
    {"insert": "\n"},
    {
      "insert": "``` Code block ```\n",
      "attributes": {"code-block": true},
    },
    {"insert": "\n"},
  ];

  /// Add note block helper
  Future<void> _addEditNote(
    BuildContext context, {
    quill.Document? document,
    int? existingOffset,
  }) async {
    final isEditing = document != null;
    final dialogController = quill.QuillController(
      document: document ?? quill.Document(),
      selection: const TextSelection.collapsed(offset: 0),
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.only(left: 16, top: 8),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(isEditing ? 'Edit note' : 'Add note'),
            IconButton(
              onPressed: () => Navigator.of(ctx).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        content: quill.QuillEditor.basic(
          controller: dialogController,
          config: const quill.QuillEditorConfig(),
        ),
      ),
    );

    if (dialogController.document.isEmpty()) return;

    // Serialize inner doc and create the embed
    final notesEmbed = NotesBlockEmbed.fromDocument(dialogController.document);

    if (isEditing && existingOffset != null) {
      // Replace the existing embed at its node offset
      // In v10+ each embed occupies a single character length.
      _controller.replaceText(
        existingOffset,
        1,
        quill.BlockEmbed.custom(notesEmbed),
        TextSelection.collapsed(offset: existingOffset + 1),
      );
      return;
    }

    // Insert a new embed at the current caret, plus a newline
    final insertAt = _controller.selection.isValid
        ? _controller.selection.start
        : _controller.document.length;
    _controller.replaceText(
      insertAt,
      0,
      quill.BlockEmbed.custom(notesEmbed),
      TextSelection.collapsed(offset: insertAt + 1),
    );
    // Add a newline after the block so the caret ends below it
    _controller.replaceText(
      insertAt + 1,
      0,
      '\n',
      TextSelection.collapsed(offset: insertAt + 2),
    );
  }

  //excalidraw and google doc helpers
  String _normalizeExcalidraw(String url) {
    // Accepts app.excalidraw.com links. If user pasted plain excalidraw.com, fix host.
    final u = Uri.tryParse(url);
    if (u == null) return url;
    if (u.host == 'excalidraw.com') {
      return u.replace(host: 'app.excalidraw.com').toString();
    }
    return url;
  }

  /// Returns a preview/published URL, or null if we can’t make it embeddable.
  String? _normalizeGoogle(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return null;

    // Case 1: already a Drive file preview link → keep
    if (u.host.endsWith('drive.google.com') && u.path.contains('/preview')) {
      return url;
    }

    // Case 2: Drive file /view?usp=...  -> swap to /preview
    if (u.host.endsWith('drive.google.com') && u.path.contains('/file/')) {
      final newPath = u.path.replaceAll('/view', '/preview');
      return u.replace(path: newPath, queryParameters: {}).toString();
    }

    // Case 3: Google Docs “publish to web” gives an embeddable /pub or /embed URL → keep
    if (u.host.endsWith('docs.google.com') &&
        (u.path.contains('/pub') || u.path.contains('/embed'))) {
      return url;
    }

    // Regular Docs /document/d/<id>/edit is usually blocked by X-Frame-Options.
    // Ask the user to use File → Share → Publish to web, then paste that link.
    return null;
  }

  late quill.QuillController _controller;
  StreamSubscription? _docSub;

  // Slash menu state
  bool _isSlashMenuOpen = false;
  String _slashQuery = '';
  final ValueNotifier<int> _slashSelectionIndex = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController.basic();
    _attachDocListener();
    _bootstrapDoc(); // load saved or start with template
  }

  void _attachDocListener() {
    _docSub?.cancel();
    _docSub = _controller.document.changes.listen((_) {
      _saveToPrefs();
      _maybeUpdateSlashMenu();
    });
  }

  /// Load from prefs; if nothing valid, fall back to starter template.
  Future<void> _bootstrapDoc() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final ops = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final doc = quill.Document.fromJson(ops);
        _controller = quill.QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0),
        );
        _attachDocListener();
        if (mounted) setState(() {});
        return;
      } catch (_) {
        // ignore malformed stored data and fall through to starter
      }
    }
    _newFromStarter();
  }

  /// Replace the current document with the starter template.
  void _newFromStarter() {
    final doc = quill.Document.fromJson(_starterDelta);
    _controller = quill.QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _attachDocListener();
    if (mounted) setState(() {});
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final ops = _controller.document.toDelta().toJson();
    await prefs.setString(_prefsKey, jsonEncode(ops));
  }

  /// Export current doc’s Delta JSON (as bytes).
  Uint8List _exportDeltaBytes() {
    final ops = _controller.document.toDelta().toJson();
    final jsonStr = jsonEncode(ops);
    return Uint8List.fromList(utf8.encode(jsonStr));
  }

  /// Download/save the current Delta JSON using file_saver (works on web/desktop/mobile).
  Future<void> _downloadDeltaJson() async {
    final bytes = _exportDeltaBytes();
    await FileSaver.instance.saveFile(
      name: 'secondstudent',
      bytes: bytes,
      ext: 'quill.json',
      mimeType: MimeType.json,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exported editor Delta as JSON')),
      );
    }
  }

  @override
  void dispose() {
    _docSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // --- Slash menu helpers ---
  List<SlashMenuItemData> get _allSlashItemsMerged {
  final defaults = DefaultSlashMeuItems().defaultSlashMenuItems;
  final customs  = CustomSlashMenuItems().items;
  return [...defaults, const SlashMenuItemData.separator(), ...customs];
}

List<SlashMenuItemData> get _filteredSlashItems {
  final q = _slashQuery.trim().toLowerCase();
  final defaults = DefaultSlashMeuItems().defaultSlashMenuItems;
  final customs  = CustomSlashMenuItems().items;

  bool match(SlashMenuItemData it) {
    if (it.isLabel || it.isSeparator) return false;
    if (q.isEmpty) return true;
    return it.title.toLowerCase().contains(q) ||
           it.subtitle.toLowerCase().contains(q);
  }

  final d = defaults.where(match).toList();
  final c = customs.where(match).toList();

  if (q.isEmpty) {
    // Show both sections with a divider
    if (d.isEmpty) return c;
    if (c.isEmpty) return d;
    return [...d, const SlashMenuItemData.separator(), ...c];
  } else {
    // Only show divider if both sections have matches
    if (d.isEmpty && c.isEmpty) return [];
    if (d.isEmpty) return c;
    if (c.isEmpty) return d;
    return [...d, const SlashMenuItemData.separator(), ...c];
  }
}


  void _openSlashMenu(String query) {
    if (!_isSlashMenuOpen) {
      setState(() {
        _isSlashMenuOpen = true;
        _slashQuery = query;
        _slashSelectionIndex.value = 0;
      });
    } else {
      setState(() {
        _slashQuery = query;
        _slashSelectionIndex.value = 0;
      });
    }
  }

  void _closeSlashMenu() {
    if (_isSlashMenuOpen) {
      setState(() {
        _isSlashMenuOpen = false;
        _slashQuery = '';
        _slashSelectionIndex.value = 0;
      });
    }
  }

  void _maybeUpdateSlashMenu() {
    final selection = _controller.selection;
    if (!selection.isValid) {
      _closeSlashMenu();
      return;
    }
    final caret = selection.baseOffset;
    if (caret < 0) {
      _closeSlashMenu();
      return;
    }
    final text = _controller.document.toPlainText();
    if (caret > text.length) {
      _closeSlashMenu();
      return;
    }
    final int lineStart =
        text.lastIndexOf('\n', (caret - 1).clamp(0, text.length - 1)) + 1;
    final String lineBeforeCaret = text.substring(lineStart, caret);

    if (lineBeforeCaret.startsWith('/')) {
      final query = lineBeforeCaret.substring(1);
      _openSlashMenu(query);
      if (_filteredSlashItems.isEmpty) {
        _slashSelectionIndex.value = 0;
      } else {
        _slashSelectionIndex.value = _slashSelectionIndex.value.clamp(
          0,
          _filteredSlashItems.length - 1,
        );
      }
    } else {
      _closeSlashMenu();
    }
  }

  void _onSlashSelect(SlashMenuAction action) {
    final selection = _controller.selection;
    if (!selection.isValid) {
      _closeSlashMenu();
      return;
    }
    final text = _controller.document.toPlainText();
    final caret = selection.baseOffset;
    final int lineStart =
        text.lastIndexOf('\n', (caret - 1).clamp(0, text.length - 1)) + 1;
    final String lineBeforeCaret = text.substring(lineStart, caret);

    // Delete the "/..." trigger text
    if (lineBeforeCaret.startsWith('/')) {
      final int deleteLength = lineBeforeCaret.length;
      _controller.replaceText(
        lineStart,
        deleteLength,
        '',
        TextSelection.collapsed(offset: lineStart),
      );
    }

    switch (action) {
      case SlashMenuAction.paragraph:
        _controller.formatSelection(quill.Attribute.header);
        _controller.formatSelection(quill.Attribute.list);
        break;
      case SlashMenuAction.heading1:
        _controller.formatSelection(quill.Attribute.h1);
        break;
      case SlashMenuAction.heading2:
        _controller.formatSelection(quill.Attribute.h2);
        break;
      case SlashMenuAction.heading3:
        _controller.formatSelection(quill.Attribute.h3);
        break;
      case SlashMenuAction.bulletList:
        _controller.formatSelection(quill.Attribute.ul);
        break;
      case SlashMenuAction.numberedList:
        _controller.formatSelection(quill.Attribute.ol);
        break;
      case SlashMenuAction.toDoList:
        _controller.formatSelection(quill.Attribute.unchecked);
        break;
      case SlashMenuAction.divider:
        final int index = _controller.selection.baseOffset;
        _controller.replaceText(
          index,
          0,
          '\n---\n',
          const TextSelection.collapsed(offset: 0),
        );
        break;
      case SlashMenuAction.codeBlock:
        _controller.formatSelection(quill.Attribute.codeBlock);
        break;
      case SlashMenuAction.addEditNote:
        _addEditNote(context);
        break;
      case SlashMenuAction.image:
        _promptForUrl(context, label: 'Image URL').then((url) {
          if (url == null || url.isEmpty) return;
          final idx = _controller.selection.baseOffset;
          // Prefer embed if your flutter_quill version supports it
          _controller.replaceText(
            idx,
            0,
            quill.BlockEmbed.image(url),
            const TextSelection.collapsed(offset: 0),
          );
        });
        break;
      case SlashMenuAction.video:
        _promptForUrl(context, label: 'Video URL').then((url) {
          if (url == null || url.isEmpty) return;
          final idx = _controller.selection.baseOffset;
          _controller.replaceText(
            idx,
            0,
            quill.BlockEmbed.video(url),
            const TextSelection.collapsed(offset: 0),
          );
        });
        break;
      case SlashMenuAction.iframeExcalidraw:
        _promptForUrl(context, label: 'Excalidraw room/share URL').then((url) {
          if (url == null || url.isEmpty) return;
          final insertAt = _controller.selection.isValid
              ? _controller.selection.start
              : _controller.document.length;
          final block = quill.BlockEmbed.custom(
            IframeBlockEmbed(url: _normalizeExcalidraw(url)),
          );
          _controller.replaceText(
            insertAt,
            0,
            block,
            TextSelection.collapsed(offset: insertAt + 1),
          );
          _controller.replaceText(
            insertAt + 1,
            0,
            '\n',
            TextSelection.collapsed(offset: insertAt + 2),
          );
        });
        break;

      case SlashMenuAction.iframeGoogleDoc:
        _promptForUrl(
          context,
          label: 'Google Doc (published) or Drive preview URL',
        ).then((url) {
          if (url == null || url.isEmpty) return;
          final normalized = _normalizeGoogle(url);
          if (normalized == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Use a published link (File → Share → Publish to web) or Drive “/preview” link.',
                ),
              ),
            );
            return;
          }
          final insertAt = _controller.selection.isValid
              ? _controller.selection.start
              : _controller.document.length;
          final block = quill.BlockEmbed.custom(
            IframeBlockEmbed(url: normalized, height: 560),
          );
          _controller.replaceText(
            insertAt,
            0,
            block,
            TextSelection.collapsed(offset: insertAt + 1),
          );
          _controller.replaceText(
            insertAt + 1,
            0,
            '\n',
            TextSelection.collapsed(offset: insertAt + 2),
          );
        });
        break;
    }

    _closeSlashMenu();
  }

  Future<String?> _promptForUrl(
    BuildContext context, {
    required String label,
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(label),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'https://...'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Insert'),
            ),
          ],
        );
      },
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent e) {
    if (!_isSlashMenuOpen) {
      return KeyEventResult.ignored;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final filtered = _filteredSlashItems;
    if (filtered.isEmpty) return KeyEventResult.handled;
    final logicalKey = e.logicalKey;
    if (logicalKey == LogicalKeyboardKey.arrowDown) {
      final next = (_slashSelectionIndex.value + 1) % filtered.length;
      _slashSelectionIndex.value = next;
      return KeyEventResult.handled;
    } else if (logicalKey == LogicalKeyboardKey.arrowUp) {
      final next =
          (_slashSelectionIndex.value - 1 + filtered.length) % filtered.length;
      _slashSelectionIndex.value = next;
      return KeyEventResult.handled;
    } else if (logicalKey == LogicalKeyboardKey.enter ||
        logicalKey == LogicalKeyboardKey.numpadEnter) {
      _onSlashSelect(filtered[_slashSelectionIndex.value].action);
      return KeyEventResult.handled;
    } else if (logicalKey == LogicalKeyboardKey.escape) {
      _closeSlashMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = _filteredSlashItems;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: Column(
        children: [
          // Tiny toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                FilledButton.tonal(
                  onPressed: _newFromStarter,
                  child: const Text('New from starter'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _downloadDeltaJson,
                  child: const Text('Download JSON'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  Positioned.fill(
                    child: quill.QuillEditor.basic(
                      controller: _controller,
                      config: quill.QuillEditorConfig(
                        showCursor: true,
                        scrollable: true,
                        autoFocus: true,
                        placeholder: 'Type / to open the command menu.',
                        embedBuilders: [
                          IframeEmbedBuilder(),
                          NotesEmbedBuilder(
                            onTapEdit: (ctx, {document, existingOffset}) =>
                                _addEditNote(
                                  ctx,
                                  document: document,
                                  existingOffset: existingOffset,
                                ),
                          ),
                          // Table embed builder to handle table elements
                          _TableEmbedBuilder(),
                          ...FlutterQuillEmbeds.editorBuilders(
                            imageEmbedConfig: QuillEditorImageEmbedConfig(
                              imageProviderBuilder: (context, imageUrl) {
                                // https://pub.dev/packages/flutter_quill_extensions#-image-assets
                                if (imageUrl.startsWith('assets/')) {
                                  return AssetImage(imageUrl);
                                }
                                return null;
                              },
                            ),
                            videoEmbedConfig: QuillEditorVideoEmbedConfig(
                              customVideoBuilder: (videoUrl, readOnly) {
                                // To load YouTube videos https://github.com/singerdmx/flutter-quill/releases/tag/v10.8.0
                                return null;
                              },
                            ),
                          ),
                        ],
                        textInputAction: TextInputAction.newline,
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
}

class _TableEmbedBuilder implements EmbedBuilder {
  @override
  String get key => 'table';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_chart, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            'Table',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool get expanded => true;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(child: widget);

  @override
  String toPlainText(dynamic node) => '[Table]';
}
