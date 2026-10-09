import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

Future<Uint8List?> pickImageBytes() async {
  final f = await FilePicker.pickFile(type: FileType.image);
  return f?.readAsBytes();
}

/// Key icons never need more than ~160 px; storing them small keeps the
/// project file and the render fast. Transparency is kept (PNG).
Future<Uint8List?> prepareIcon(Uint8List bytes, {int max = 160}) => Isolate.run(() {
      final im = img.decodeImage(bytes);
      if (im == null) return null;
      final scaled = (im.width > max || im.height > max)
          ? img.copyResize(im, width: im.width >= im.height ? max : null, height: im.height > im.width ? max : null,
              interpolation: img.Interpolation.average)
          : im;
      return img.encodePng(scaled, level: 6);
    });

/// Backgrounds are cropped to the deck's screen size and stored as JPEG.
Future<Uint8List?> prepareBackground(Uint8List bytes, int w, int h) => Isolate.run(() {
      final cover = img.decodeImage(bytes);
      if (cover == null) return null;
      final scale = (w / cover.width) > (h / cover.height) ? w / cover.width : h / cover.height;
      final rw = (cover.width * scale).ceil(), rh = (cover.height * scale).ceil();
      final resized = img.copyResize(cover, width: rw, height: rh, interpolation: img.Interpolation.average);
      final cropped = img.copyCrop(resized, x: (rw - w) ~/ 2, y: (rh - h) ~/ 2, width: w, height: h);
      return img.encodeJpg(cropped, quality: 90);
    });
