import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as html;
import 'dart:ui_web' as ui;

Widget buildHtmlIFrame(String url, double height) {
  final viewType = 'iframe-${url.hashCode}-${height.toInt()}';
  try {
    ui.platformViewRegistry.registerViewFactory(viewType, (_) {
      final el = html.HTMLIFrameElement()
        ..src = url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true
        ..allow =
            'clipboard-read; clipboard-write; microphone; camera; fullscreen';
      return el;
    });
  } catch (_) {}
  return SizedBox(height: height, child: HtmlElementView(viewType: viewType));
}
