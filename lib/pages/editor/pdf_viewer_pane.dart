import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class PdfViewerPane extends StatefulWidget {
  const PdfViewerPane({
    super.key,
    required this.file,
  });

  final File file;

  @override
  State<PdfViewerPane> createState() => _PdfViewerPaneState();
}

class _PdfViewerPaneState extends State<PdfViewerPane> {
  final PdfViewerController _controller = PdfViewerController();

  @override
  Widget build(BuildContext context) {
    // For desktop/mobile dart:io is fine.
    // (If you later target web, load from bytes with a picker-driven blob instead.)
    if (kIsWeb) {
      return const Center(
        child: Text('Web PDF viewing from local paths is not yet supported.'),
      );
    }

    return Stack(
      children: [
        SfPdfViewer.file(
          widget.file,
          controller: _controller,
          canShowScrollHead: true,
          canShowPaginationDialog: true,
        ),
        Positioned(
          right: 12,
          top: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
              borderRadius: BorderRadius.circular(10),
              boxShadow: kElevationToShadow[2],
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Zoom out',
                  icon: const Icon(Icons.zoom_out),
                  onPressed: () {
                    _controller.zoomLevel =
                        (_controller.zoomLevel - 0.25).clamp(1.0, 5.0);
                  },
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () {
                    _controller.zoomLevel =
                        (_controller.zoomLevel + 0.25).clamp(1.0, 5.0);
                  },
                ),
                IconButton(
                  tooltip: 'Go to page…',
                  icon: const Icon(Icons.find_in_page),
                  onPressed: () async {
                    final pageStr = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Go to page'),
                        content: const TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(hintText: 'Page number'),
                        ),
                      ),
                    );
                    final page = int.tryParse(pageStr ?? '');
                    if (page != null && page > 0) {
                      _controller.jumpToPage(page);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
