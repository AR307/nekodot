import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../ui/symbols.dart';

import 'package:http/http.dart' as http;

/// Catalog logos can be SVGs at extensionless URLs. Cache by actual resource URL.
class ConnectorIcon extends StatelessWidget {
  final String? url;
  final double size;
  const ConnectorIcon({super.key, this.url, this.size = 28});
  static final _images = <String, Future<({Uint8List bytes, bool svg})>>{};
  static Future<({Uint8List bytes, bool svg})> _load(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw StateError('Logo unavailable');
    return (
      bytes: response.bodyBytes,
      svg: response.headers['content-type']?.contains('svg') == true,
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: url == null
        ? const Icon(Symbols.link, size: 24)
        : FutureBuilder<({Uint8List bytes, bool svg})>(
            future: _images.putIfAbsent(url!, () => _load(url!)),
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data == null) {
                return snapshot.hasError
                    ? const Icon(Symbols.link, size: 24)
                    : const SizedBox.shrink();
              }
              final logo = data.svg
                  ? SvgPicture.memory(data.bytes, width: size, height: size)
                  : Image.memory(data.bytes, width: size, height: size);
              if (Theme.of(context).brightness == Brightness.light) return logo;
              return DecoratedBox(
                decoration: ShapeDecoration(
                  color: const Color(0xfff4f4f4),
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(size / 5),
                  ),
                ),
                child: Padding(padding: const EdgeInsets.all(2), child: logo),
              );
            },
          ),
  );
}
