// lib/pages/startup/file_storage.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

// pages 
import 'package:secondstudent/pages/startup/home_page.dart';
import 'package:secondstudent/pages/editor/sync.dart';

// TODO : create base file system
/*

/
  .secondstudent
    plugins/
      plugin-name/
        custom-block.dart -> text
        manifest.json -> jsonb
    styles/
    startup/
  sampleFolder/
    sample.txt
    sample.rtf

*/

class FileStorage extends StatelessWidget {
  const FileStorage({super.key});

  @override
  Widget build(BuildContext context) => _FolderSelectorWidget();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers (no duplicates)
// ─────────────────────────────────────────────────────────────────────────────

String _prettyPath(String path) {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null && home.isNotEmpty) {
    final normHome = Directory(home).absolute.path;
    final normPath = Directory(path).absolute.path;
    if (normPath.startsWith(normHome)) {
      return normPath.replaceFirst(normHome, '~');
    }
  }
  return path;
}

/// Best guess for a user's Documents folder on desktop.
Future<Directory> _desktopDocumentsDir() async {
  if (Platform.isWindows) {
    final user = Platform.environment['USERPROFILE'];
    if (user != null && user.isNotEmpty) {
      final docs = Directory(p.join(user, 'Documents'));
      if (await docs.exists()) return docs;
      return Directory(user);
    }
    return Directory('C:\\');
  }
  // macOS / Linux
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    final docs = Directory(p.join(home, 'Documents'));
    if (await docs.exists()) return docs;
    return Directory(home);
  }

  // fallback
  return Directory.current;
}

class _FolderSelectorWidget extends StatefulWidget {
  @override
  State<_FolderSelectorWidget> createState() => _FolderSelectorWidgetState();
}

class _FolderSelectorWidgetState extends State<_FolderSelectorWidget> {
  Future<String?> _getSavedPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('path_to_files');
  }

  String currentL = "";

  Future<void> _saveAndRestart(BuildContext context, String path) async {
    final prefs = await SharedPreferences.getInstance();
    // Normalize to an absolute, clean path
    final normalized = Directory(path).absolute.path;
    await prefs.setString('path_to_files', normalized);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Folder path saved: $normalized')));

    // Return to HomePage so your workspace re-reads prefs
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomePage()),
      (route) => false,
    );
  }

  /// Root for the picker (what the UI is allowed to browse).
  /// Must exist on the current platform.
  Future<Directory> _pickerRoot() async {
    if (kIsWeb) {
      // The package doesn't work on web. You'll need a web storage UI later.
      // For now, pretend a virtual root.
      return Directory.systemTemp;
    }

    if (Platform.isMacOS || Platform.isLinux) {
      // User's home is a good, familiar starting root
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final dir = Directory(home);
        if (await dir.exists()) return dir;
      }
      // Fallback to Documents if HOME missing
      final docs = await getApplicationDocumentsDirectory();
      return Directory(p.dirname(docs.path));
    }

    if (Platform.isWindows) {
      // Typical Windows user profile root
      final user = Platform.environment['USERPROFILE'] ?? 'C:\\';
      final dir = Directory(user);
      if (await dir.exists()) return dir;
      return Directory('C:\\');
    }

    if (Platform.isAndroid || Platform.isIOS) {
      // On mobile, keep it scoped to app documents
      return await getApplicationDocumentsDirectory();
    }

    // Fallback
    return Directory.current;
  }

  // add this helper
  String _prettyPath(String path) {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      final normHome = Directory(home).absolute.path;
      final normPath = Directory(path).absolute.path;
      if (normPath.startsWith(normHome)) {
        return normPath.replaceFirst(normHome, '~');
      }
    }
    return path;
  }

  // Helper: best guess for a user's "Documents" on desktop
  Future<Directory> _desktopDocumentsDir() async {
    if (Platform.isWindows) {
      final user = Platform.environment['USERPROFILE'];
      if (user != null && user.isNotEmpty) {
        final docs = Directory(p.join(user, 'Documents'));
        if (await docs.exists()) return docs;
        return Directory(user);
      }
      return Directory('C:\\');
    }

    // macOS / Linux
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final docs = Directory(p.join(home, 'Documents'));
      if (await docs.exists()) return docs;
      return Directory(home);
    }

    // fallback
    return Directory.current;
  }

  // REPLACE your existing _recommendedWorkspace() with this:
  Future<Directory> _recommendedWorkspace() async {
    if (kIsWeb) {
      // Stubbed; replace with IndexedDB later
      return Directory.systemTemp.createTemp('secondstudent_web_workspace_');
    }

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // Prefer ~/Documents/SecondStudent/workspace
      final docs = await _desktopDocumentsDir();
      var ws = Directory(p.join(docs.path, 'SecondStudent', 'workspace'));
      try {
        if (!await ws.exists()) await ws.create(recursive: true);
        return ws;
      } catch (_) {
        // fallback to app-docs if creating under Documents failed
        final appDocs = await getApplicationDocumentsDirectory();
        ws = Directory(p.join(appDocs.path, 'SecondStudent', 'workspace'));
        if (!await ws.exists()) await ws.create(recursive: true);
        return ws;
      }
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      final ws = Directory(p.join(docs.path, 'workspace'));
      if (!await ws.exists()) await ws.create(recursive: true);
      return ws;
    }

    final tmp = await getTemporaryDirectory();
    final ws = Directory(p.join(tmp.path, 'workspace'));
    if (!await ws.exists()) await ws.create(recursive: true);
    return ws;
  }

  Future<void> _pickFolder(BuildContext context) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder picker is not supported on Web.')),
      );
      return;
    }

    final root = await _pickerRoot();
    if (!await root.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error loading file list: The "${root.path}" path does not exist.',
          ),
        ),
      );
      return;
    }

    final selectedPath = await FilesystemPicker.open(
      context: context,
      title: 'Select a Folder',
      fsType: FilesystemType.folder,
      rootDirectory: root, // ✅ platform-correct root
      directory: root, // start here
      showGoUp: true,
      pickText: 'Use this folder',
      requestPermission: () async =>
          true, // desktop: no runtime permission dialog
    );

    if (selectedPath == null) return; // user cancelled
    await _saveAndRestart(context, selectedPath);
  }

  /// Create/reuse ~/Documents/SecondStudent/workspace, then ask the user
  /// to confirm THAT folder (grants access on macOS). No persistent bookmarks.
  Future<void> _useRecommended(BuildContext context) async {
    final ws = await _recommendedWorkspace();

    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      final docs = await _desktopDocumentsDir();
      final selectedPath = await FilesystemPicker.open(
        context: context,
        title: 'Use Recommended Folder',
        fsType: FilesystemType.folder,
        rootDirectory: docs, // root = ~/Documents (or HOME fallback)
        directory: ws, // start in ~/Documents/SecondStudent/workspace
        showGoUp: true,
        pickText: 'Use this folder',
        requestPermission: () async => true,
      );

      if (selectedPath == null) return; // user cancelled
      await _saveAndRestart(context, selectedPath);
      return;
    }

    // Mobile/web fallback: just save the created path (no security-scope needed).
    await _saveAndRestart(context, ws.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Folder Selector')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FutureBuilder<String?>(
                future: _getSavedPath(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }
                  
                      if (snap.data != null) {
                        currentL = snap.data!;
                      }
                    
                  final current = snap.data;
                  final text = (current == null || current.isEmpty)
                      ? 'No folder selected'
                      : 'Current File Location:\n${_prettyPath(current)}';
                  return Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  );
                },
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  final sync = Sync();
                  sync.syncAllFiles(currentL);
                },
                child: const Text(
                  'You can sync through our own services!!',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  launch('https://onedrive.live.com/?view=1');
                  print('Link clicked');
                },
                child: const Text(
                  'Feel free to sync your files on your own via OneDrive!',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _pickFolder(context),
                child: const Text(
                  'Choose a Folder…',
                  style: TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 24),

              TextButton(
                onPressed: () => _useRecommended(context),
                child: const Text('Use Recommended Default'),
              ),
              if (kIsWeb) ...[
                const SizedBox(height: 24),
                const Text(
                  'Web is not using a native file system.\nAdd an IndexedDB-backed storage later.',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
