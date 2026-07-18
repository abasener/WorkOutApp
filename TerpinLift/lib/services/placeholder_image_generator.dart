import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Renders a simple black-background, white-icon square PNG entirely in
/// code (no bundled image asset) — used only for synthetic demo progress
/// photos, since a real photo obviously can't be faked. Draws the icon via
/// `TextPainter` against its own icon font, the same trick Flutter's `Icon`
/// widget uses internally, so any `Icons.*` glyph works without needing an
/// actual image file on disk.
abstract class PlaceholderImageGenerator {
  static Future<Uint8List> generate(IconData icon, {int size = 600}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final side = size.toDouble();

    canvas.drawRect(Rect.fromLTWH(0, 0, side, side), Paint()..color = Colors.black);

    final textPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: side * 0.5,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      Offset((side - textPainter.width) / 2, (side - textPainter.height) / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
