// lib/realtime/presence.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class PresenceService {
  final SupabaseClient supabase;
  RealtimeChannel? _ch;

  PresenceService(this.supabase);

  RealtimeChannel join(String room, {required Map<String, dynamic> meta}) {
    _ch?.unsubscribe();
    _ch = supabase.channel(
      room,
      opts: const RealtimeChannelConfig(self: true),
    );

    _ch!
      .onPresenceSync((_) {
        // All presence state (map of key -> metas[])
        final state = _ch!.presenceState();
        // print('presence sync: $state');
      })
      .onPresenceJoin((p) {
        // print('presence join: $p');
      })
      .onPresenceLeave((p) {
        // print('presence leave: $p');
      })
      .subscribe((status, err) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await _ch!.track(meta);
        }
      });

    return _ch!;
  }

  Future<void> updateMeta(Map<String, dynamic> meta) async {
    if (_ch == null) return;
    await _ch!.track(meta);
  }

  Future<void> leave() async {
    if (_ch == null) return;
    await _ch!.untrack();
    await _ch!.unsubscribe();
    _ch = null;
  }
}
