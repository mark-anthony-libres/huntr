import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _viewType = 'huntr-blurred-picture';
bool _registered = false;

/// [url]'s picture, heavily blurred, filling its box (for the
/// sensitive-content cover). In a browser the bucket's pictures are page
/// elements (no CORS), which Flutter can't blur: the browser blurs this one
/// itself (CSS), slightly enlarged so the edges stay solid.
Widget blurredPicture(String url) {
  if (!_registered) {
    _registered = true;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId,
        {Object? params}) {
      final box = web.document.createElement('div') as web.HTMLDivElement
        ..style.cssText =
            'width:100%;height:100%;overflow:hidden;pointer-events:none;';
      final img = web.document.createElement('img') as web.HTMLImageElement
        ..src = params as String
        ..alt = ''
        ..style.cssText = 'width:100%;height:100%;object-fit:cover;'
            'filter:blur(28px);transform:scale(1.2);pointer-events:none;';
      box.append(img);
      return box;
    });
  }
  return IgnorePointer(
    child: HtmlElementView(
        key: ValueKey(url), viewType: _viewType, creationParams: url),
  );
}
