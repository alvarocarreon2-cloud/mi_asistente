import 'dart:collection';
import 'dart:io';

import 'package:image/image.dart' as img;

bool _looksLikeCheckerBackground(int r, int g, int b) {
  final maxC = [r, g, b].reduce((a, c) => a > c ? a : c);
  final minC = [r, g, b].reduce((a, c) => a < c ? a : c);
  final chroma = maxC - minC;
  final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b);

  // Checkerboard is near-neutral gray and bright.
  return chroma <= 24 && luma >= 170;
}

void main() {
  final input = File('assets/logo/kaia_character.png');
  final output = File('assets/logo/kaia_character_clean.png');

  if (!input.existsSync()) {
    stderr.writeln('Input not found: ${input.path}');
    exitCode = 1;
    return;
  }

  final bytes = input.readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    stderr.writeln('Could not decode PNG: ${input.path}');
    exitCode = 1;
    return;
  }

  final image = decoded.convert(numChannels: 4);
  final w = image.width;
  final h = image.height;
  final visited = List<bool>.filled(w * h, false);

  int idx(int x, int y) => y * w + x;
  bool inside(int x, int y) => x >= 0 && x < w && y >= 0 && y < h;

  final q = Queue<(int, int)>();

  void tryPush(int x, int y) {
    if (!inside(x, y)) return;
    final i = idx(x, y);
    if (visited[i]) return;
    final p = image.getPixel(x, y);
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    if (_looksLikeCheckerBackground(r, g, b)) {
      visited[i] = true;
      q.add((x, y));
    }
  }

  for (int x = 0; x < w; x++) {
    tryPush(x, 0);
    tryPush(x, h - 1);
  }
  for (int y = 0; y < h; y++) {
    tryPush(0, y);
    tryPush(w - 1, y);
  }

  const dirs = <(int, int)>[(1, 0), (-1, 0), (0, 1), (0, -1)];

  while (q.isNotEmpty) {
    final (x, y) = q.removeFirst();
    image.setPixelRgba(x, y, 0, 0, 0, 0);
    for (final (dx, dy) in dirs) {
      tryPush(x + dx, y + dy);
    }
  }

  output.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('Generated: ${output.path} (${output.lengthSync()} bytes)');
}