import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// ==== Custom "notes" block embed ===========================================
class NotesBlockEmbed extends CustomBlockEmbed {
  const NotesBlockEmbed(String value) : super(noteType, value);

  static const String noteType = 'notes';

  static NotesBlockEmbed fromDocument(Document document) {
    // Store the inner document as a JSON string (delta ops).
    final ops = document.toDelta().toJson();
    return NotesBlockEmbed(jsonEncode(ops));
  }

  Document get document {
    try {
      final ops = jsonDecode(data);
      if (ops is List) {
        return Document.fromJson(ops.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    return Document();
  }
}

/// ==== Builder to render the "notes" embed ==================================
class NotesEmbedBuilder implements EmbedBuilder {
  NotesEmbedBuilder({required this.onTapEdit});
  final Future<void> Function(BuildContext context, {Document? document, int? existingOffset}) onTapEdit;

  @override
  String get key => NotesBlockEmbed.noteType;

  // Satisfy older/newer EmbedBuilder contracts explicitly
  @override
  bool get expanded => true;

  @override
  WidgetSpan buildWidgetSpan(Widget widget) => WidgetSpan(child: widget);

  @override
  String toPlainText(dynamic node) => '\uFFFC';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    try {
      final doc = NotesBlockEmbed(embedContext.node.value.data).document;
      final preview = doc.toPlainText().replaceAll('\n', ' ');
      // Use the offset of this node to support "Edit"
      final nodeOffset = embedContext.node.documentOffset;

      return Material(
        color: Colors.transparent,
        child: ListTile(
          leading: const Icon(Icons.notes),
          title: Text(
            preview.isEmpty ? 'Note' : preview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Colors.grey),
          ),
          onTap: () => onTapEdit(context, document: doc, existingOffset: nodeOffset),
        ),
      );
    } catch (e) {
      // Fallback if the payload is malformed
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('Invalid note block'),
      );
    }
  }
}
