// lib/file_system_viewer.dart
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

bool _isJson(FileSystemEntity e) =>
    e is File && e.path.toLowerCase().endsWith('.json');

bool _isPdf(FileSystemEntity e) =>
    e is File && e.path.toLowerCase().endsWith('.pdf');

bool _isOpenable(FileSystemEntity e) => e is File && (_isJson(e) || _isPdf(e));

typedef FileSelected = void Function(File file);
typedef FileRenamed = void Function(File oldFile, File newFile);

class FileSystemViewer extends StatefulWidget {
  const FileSystemViewer({
    super.key,
    required this.onFileSelected,
    this.onFileRenamed,
    this.showHidden = false,
  });

  final FileSelected onFileSelected;
  final FileRenamed? onFileRenamed;
  final bool showHidden;

  @override
  State<FileSystemViewer> createState() => _FileSystemViewerState();
}

class _FileSystemViewerState extends State<FileSystemViewer> {
  String? _rootPath;
  late final Set<String> _expandedDirs = {};
  late final Map<String, List<FileSystemEntity>> _childrenCache = {};
  bool _loadingRoot = true;

  @override
  void initState() {
    super.initState();
    _loadRoot();
  }

  // lib/pages/editor/file_system_viewer.dart
  // (keep your imports)

  Future<void> _loadRoot() async {
    setState(() => _loadingRoot = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = prefs.getString('path_to_files')?.trim();

      if (p == null || p.isEmpty) {
        _rootPath = null; // Shows your "Set a valid root" UI
      } else {
        final dir = Directory(p);
        if (await dir.exists()) {
          _rootPath = dir.path;
          await _ensureChildrenLoaded(_rootPath!);
          _expandedDirs.add(_rootPath!);
        } else {
          _rootPath = null;
        }
      }
    } catch (_) {
      _rootPath = null;
    } finally {
      if (mounted) setState(() => _loadingRoot = false);
    }
  }

  bool _isHidden(String name) => name.startsWith('.');
  bool _isJson(FileSystemEntity e) =>
      e is File && e.path.toLowerCase().endsWith('.json');

  String _nameOf(String path) {
    final parts = path.split(Platform.pathSeparator);
    if (parts.isEmpty) return path;
    final last = parts.last;
    return last.isEmpty ? path : last;
  }

  Future<void> _ensureChildrenLoaded(String dirPath) async {
    if (_childrenCache.containsKey(dirPath)) return;

    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      _childrenCache[dirPath] = const [];
      return;
    }

    if (_rootPath != null && !_isWithinRoot(dirPath)) {
      _childrenCache[dirPath] = const [];
      return;
    }

    try {
      final kids = dir.listSync(followLinks: false).where((e) {
        final base = _nameOf(e.path);
        if (!widget.showHidden && _isHidden(base)) return false;
        return true;
      }).toList();

      kids.sort((a, b) {
        final aIsDir = FileSystemEntity.isDirectorySync(a.path);
        final bIsDir = FileSystemEntity.isDirectorySync(b.path);
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      _childrenCache[dirPath] = kids;
    } catch (_) {
      _childrenCache[dirPath] = const [];
    }
  }

  bool _isWithinRoot(String p) {
    if (_rootPath == null) return false;
    final root = _normalize(_rootPath!);
    final target = _normalize(p);
    return target == root ||
        target.startsWith('$root${Platform.pathSeparator}');
  }

  String _normalize(String p) {
    return File(
      p,
    ).absolute.path.replaceAll(RegExp(r'[\\/]+'), Platform.pathSeparator);
  }

  Future<void> _toggleExpand(String dirPath) async {
    if (_expandedDirs.contains(dirPath)) {
      setState(() => _expandedDirs.remove(dirPath));
    } else {
      await _ensureChildrenLoaded(dirPath);
      setState(() => _expandedDirs.add(dirPath));
    }
  }

  Future<void> _refresh() async {
    _childrenCache.clear();
    _expandedDirs.clear();
    await _loadRoot();
  }

  Future<void> _createBlankJsonAt(String dirPath) async {
    try {
      if (!_isWithinRoot(dirPath)) return;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('$dirPath/new_$ts.json');
      await file.create(recursive: true);

      // Minimal valid Quill delta starter
      final starterDelta = [
        {
          "insert": "Sample\n",
          "attributes": {"header": 1},
        },
      ];

      // Write as proper JSON
      await file.writeAsString(jsonEncode(starterDelta));

      _childrenCache.remove(dirPath);
      await _ensureChildrenLoaded(dirPath);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created ${_nameOf(file.path)}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create file: $e')));
    }
  }

  Future<void> _renameFile(File file) async {
    final dirPath = File(file.path).parent.path;
    if (!_isWithinRoot(dirPath)) return;

    final oldName = _nameOf(file.path);
    final controller = TextEditingController(text: oldName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Rename file'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter new file name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    if (newName == null) return;

    // Validation
    if (newName.isEmpty ||
        newName.contains(Platform.pathSeparator) ||
        newName == oldName) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid or unchanged name')),
      );
      return;
    }

    // Keep .json if original was .json and user omitted extension
    String finalName = newName;
    final wasJson = oldName.toLowerCase().endsWith('.json');
    if (wasJson && !finalName.toLowerCase().endsWith('.json')) {
      finalName = '$finalName.json';
    }

    final newPath = '$dirPath${Platform.pathSeparator}$finalName';
    final newFile = File(newPath);

    if (!_isWithinRoot(newPath)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot move outside the root folder')),
      );
      return;
    }

    if (await newFile.exists()) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('File exists'),
          content: Text('Overwrite $finalName?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Overwrite'),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
      await newFile.delete();
    }

    try {
      final renamed = await file.rename(newPath);

      // Refresh the parent dir listing
      _childrenCache.remove(dirPath);
      await _ensureChildrenLoaded(dirPath);
      setState(() {});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Renamed to ${_nameOf(renamed.path)}')),
      );

      widget.onFileRenamed?.call(file, renamed);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to rename: $e')));
    }
  }

  Widget _buildDirTile(String dirPath, {int depth = 0}) {
    final name = _nameOf(dirPath);
    final expanded = _expandedDirs.contains(dirPath);
    final children = _childrenCache[dirPath] ?? const [];

    return Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(expanded ? Icons.folder_open : Icons.folder),
          title: Text(
            name.isEmpty ? dirPath : name,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: depth == 0
              ? Text(dirPath, overflow: TextOverflow.ellipsis)
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'New JSON here',
                icon: const Icon(Icons.note_add_outlined),
                onPressed: () => _createBlankJsonAt(dirPath),
              ),
              IconButton(
                tooltip: expanded ? 'Collapse' : 'Expand',
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                onPressed: () => _toggleExpand(dirPath),
              ),
            ],
          ),
          onTap: () => _toggleExpand(dirPath),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              children: [
                for (final e in children)
                  FileSystemEntity.isDirectorySync(e.path)
                      ? _buildDirTile(e.path, depth: depth + 1)
                      : _buildFileTile(
                          File(e.path),
                          parentDir: dirPath,
                          depth: depth + 1,
                        ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFileTile(File file, {required String parentDir, int depth = 0}) {
    final isJson = _isJson(file);
    final isPdf = _isPdf(file);
    final openable = isJson || isPdf;
    final name = _nameOf(file.path);

    return ListTile(
      dense: true,
      leading: Icon(
        isJson
            ? Icons.description
            : isPdf
            ? Icons.picture_as_pdf
            : Icons.insert_drive_file,
      ),
      title: Text(name, overflow: TextOverflow.ellipsis),
      subtitle: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: openable ? () => widget.onFileSelected(file) : null,
      enabled: openable,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isJson)
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.drive_file_rename_outline),
              onPressed: () => _renameFile(file),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRoot) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rootPath == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Set a valid root folder in SharedPreferences under key "path_to_files".\n'
            'The tree is rooted there and you cannot navigate above it.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _rootPath!,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => _createBlankJsonAt(_rootPath!),
                child: const Text('New JSON (root)'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(children: [_buildDirTile(_rootPath!, depth: 0)]),
        ),
      ],
    );
  }
}
