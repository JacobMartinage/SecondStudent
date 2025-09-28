// IFRAME embed that works on web (real <iframe>) and desktop/mobile (WebView).

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/src/editor/widgets/proxy.dart' show EmbedProxy;
import 'package:webview_flutter/webview_flutter.dart';

// Conditional import to avoid web-only libs on macOS/Windows/iOS/Android
import 'iframe_html_view_stub.dart'
  if (dart.library.html) 'iframe_html_view_web.dart';

/// ---------- DATA MODEL ----------
class IframeBlockEmbed extends CustomBlockEmbed {
  static const String kType = 'iframe';

  IframeBlockEmbed._(String value) : super(kType, value);

  factory IframeBlockEmbed({required String url, double? height}) {
    final payload = <String, dynamic>{'url': url};
    if (height != null) payload['height'] = height;
    return IframeBlockEmbed._(jsonEncode(payload));
  }

  factory IframeBlockEmbed.fromRaw(String raw) => IframeBlockEmbed._(raw);

  Map<String, dynamic> get dataMap {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return const {};
  }
}

/// ---------- BUILDER ----------
class IframeEmbedBuilder implements EmbedBuilder {
  const IframeEmbedBuilder();

  @override
  String get key => IframeBlockEmbed.kType;

  @override
  bool get expanded => true;

  @override
  WidgetSpan buildWidgetSpan(Widget child) => WidgetSpan(child: EmbedProxy(child));

  @override
  String toPlainText(Embed node) {
    final m = IframeBlockEmbed.fromRaw(node.value.data).dataMap;
    return '[iframe ${m['url'] ?? ''}]';
    // If your flutter_quill has a different Embed signature, keep this line
  }

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final m = IframeBlockEmbed.fromRaw(embedContext.node.value.data).dataMap;
    final url = (m['url'] ?? '').toString();
    final height =
        (m['height'] is num) ? (m['height'] as num).toDouble() : 560.0;

    if (url.isEmpty) return _errorBox(context, 'Empty iframe URL');

    if (kIsWeb) {
      // Real <iframe> on web
      return _chrome(
        context,
        height: height,
        url: url,
        body: buildHtmlIFrame(url, height),
      );
    }

    // WebView on desktop/mobile
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));

    return _chrome(
      context,
      height: height,
      url: url,
      body: WebViewWidget(controller: controller),
    );
  }

  Widget _chrome(BuildContext context,
      {required double height, required String url, required Widget body}) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => FocusScope.of(context).unfocus(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border(
                    bottom:
                        BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.web_asset, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBox(BuildContext context, String msg) => Container(
        height: 140,
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.error),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(msg, textAlign: TextAlign.center),
      );
}
