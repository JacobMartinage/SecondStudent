// lib/realtime/realtime_doc.dart
//
// Minimal realtime wiring for a Quill editor:
// - Presence (track who is online in this doc)
// - Broadcast UPDATE (text deltas) and DELETE (cursor positions)
// - No DB snapshots; peers converge by applying deltas in order
//
// Requires:
//   supabase_flutter: ^2
//   quill_delta: ^2
//
// Events we send/listen:
//   UPDATE -> { clientId, ops[] }           // text changes (quill_delta format)
//   DELETE -> { clientId, name, color, ...} // cursor signal

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:quill_delta/quill_delta.dart' as qd;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef CursorListener =
    void Function({
      required String clientId,
      required String name,
      required int color,
      required int index,
      required int length,
    });

class RealtimeDoc {
  final SupabaseClient supabase;
  final String docId; // e.g. the file/session id
  final String clientId; // random per device/session
  final String userId; // auth id or email
  final String userName; // display in presence
  final quill.QuillController controller;

  RealtimeChannel? _ch;
  bool _applyingRemote = false;
  StreamSubscription? _docSub;
  VoidCallback? _selectionListener;
  TextSelection _lastSel = const TextSelection.collapsed(offset: 0);

  // callback to surface remote cursors to the UI
  final CursorListener? onRemoteCursor;

  RealtimeDoc({
    required this.supabase,
    required this.docId,
    required this.clientId,
    required this.userId,
    required this.userName,
    required this.controller,
    this.onRemoteCursor,
  });

  Future<void> attach() async {
    // 1) listen locally (doc + selection)
    _listenLocal();

    // 2) join channel + presence
    _ch = supabase.channel(
      'topic:$docId',
      opts: const RealtimeChannelConfig(self: true),
    );

    _ch!
        // Presence (optional console logs)
        .onPresenceSync((_) {
          // final state = _ch!.presenceState();
          // print('presence sync: $state');
        })
        .onPresenceJoin((p) {
          // print('presence join: $p');
        })
        .onPresenceLeave((p) {
          // print('presence leave: $p');
        })
        .subscribe((status, err) async {
          if (status != RealtimeSubscribeStatus.subscribed) return;
          await _ch!.track({
            'key': clientId,
            'userId': userId,
            'name': userName,
            'online_at': DateTime.now().toIso8601String(),
          });
        });
  }

  void _listenLocal() {
    // text change -> broadcast UPDATE
    _docSub?.cancel();
    _docSub = controller.document.changes.listen((change) {
      if (_applyingRemote) return;
      if (change.source == quill.ChangeSource.local) {
        final d = change.change as qd.Delta;
        if (d.isEmpty) return;
        _broadcast('UPDATE', {'clientId': clientId, 'ops': d.toJson()});
      }
    });

    // selection change -> broadcast DELETE (cursor signal)
    _selectionListener?.call(); // remove old if any
    _selectionListener = () {
      final sel = controller.selection;
      if (sel.baseOffset == _lastSel.baseOffset &&
          sel.extentOffset == _lastSel.extentOffset)
        return;
      _lastSel = sel;

      final user = supabase.auth.currentUser;
      final name = user?.userMetadata?['name'] ?? (user?.email ?? userName);
      final color = _stableColorFor(clientId).value;

      _broadcast('DELETE', {
        'clientId': clientId,
        'name': name,
        'color': color,
        'index': sel.baseOffset,
        'length': sel.extentOffset - sel.baseOffset,
      });
    };
    controller.addListener(_selectionListener!);
  }

  Future<void> _broadcast(String event, Map<String, dynamic> payload) async {
    // If called before subscribe(): HTTP; after subscribe(): WebSocket
    await _ch?.sendBroadcastMessage(event: event, payload: payload);
  }

  Future<void> detach() async {
    try {
      await _ch?.untrack();
    } catch (_) {}
    try {
      await _ch?.unsubscribe();
    } catch (_) {}

    _docSub?.cancel();
    if (_selectionListener != null) {
      controller.removeListener(_selectionListener!);
      _selectionListener = null;
    }
  }

  // Stable per-client color
  Color _stableColorFor(String key) {
    final h = key.hashCode;
    final r = 100 + (h & 0x5F);
    final g = 100 + ((h >> 3) & 0x5F);
    final b = 100 + ((h >> 6) & 0x5F);
    return Color.fromARGB(255, r, g, b);
  }
}
