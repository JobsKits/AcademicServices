import 'dart:convert';

import 'package:flutter/material.dart';

class ShopMedia extends StatelessWidget {
  const ShopMedia({
    super.key,
    this.path = '',
    required this.baseUrl,
    this.packaged = false,
    this.fit = BoxFit.contain,
    this.brandSize = 88,
  });
  final String path, baseUrl;
  final bool packaged;
  final BoxFit fit;
  final double brandSize;
  Widget _brand() => Center(
    child: Image.asset(
      'Assets/shop-brand.png',
      package: packaged ? 'zhixu' : null,
      width: brandSize,
      height: brandSize,
      fit: BoxFit.contain,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final fallback = _brand();
    Uri? uri = Uri.tryParse(path);
    if (path.startsWith('/') && !path.startsWith('//')) {
      uri = Uri.parse(baseUrl).resolve(path);
    }
    if (path.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(path.split(',').last),
          fit: fit,
          errorBuilder: (_, _, _) => fallback,
        );
      } catch (_) {
        return fallback;
      }
    }
    if (uri != null &&
        path.isNotEmpty &&
        (uri.scheme == 'https' ||
            (uri.hasAuthority &&
                uri.origin == Uri.parse(baseUrl).origin &&
                uri.scheme == 'http'))) {
      return Image.network(
        uri.toString(),
        fit: fit,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, image, progress) =>
            progress == null ? image : fallback,
      );
    }
    if (path.isNotEmpty &&
        uri != null &&
        !uri.hasScheme &&
        !path.startsWith('/')) {
      return Image.asset(
        path,
        package: packaged ? 'zhixu' : null,
        fit: fit,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
  }
}
