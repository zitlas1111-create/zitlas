import 'dart:convert';

import 'package:flutter/widgets.dart';

/// Safe image handling for user/coach-supplied image references.
///
/// ROOT CAUSE this guards: a base64 `data:image/...;base64,....` string handed
/// to `NetworkImage` / `CachedNetworkImage` / `Image.network` is parsed as a
/// network URI, finds no host, and throws
/// `Invalid argument(s): No host specified in URI`. Coach/athlete avatars and
/// some inline photos are stored as data: URIs, so any raw use of those widgets
/// on such a value crashes the frame.
///
/// [safeImageProvider] turns a data: URI into a [MemoryImage], an http(s) URL
/// into a [NetworkImage], and anything else into null (caller shows a
/// fallback). [isNetworkImageUrl] is for the widgets that need a URL string
/// (CachedNetworkImage / Image.network) and cannot accept a data: URI at all.
ImageProvider? safeImageProvider(String? raw) {
  if (raw == null) return null;
  final url = raw.trim();
  if (url.isEmpty) return null;

  if (url.startsWith('data:image')) {
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    try {
      return MemoryImage(base64Decode(url.substring(comma + 1)));
    } catch (_) {
      return null; // malformed base64 — show the fallback, never crash
    }
  }

  if (url.startsWith('http://') || url.startsWith('https://')) {
    return NetworkImage(url);
  }

  // Relative paths, asset keys, empty hosts — not a valid network image.
  return null;
}

/// True only when [raw] is a fetchable http(s) URL — i.e. safe to hand to
/// `CachedNetworkImage(imageUrl:)` / `Image.network(...)`, which cannot handle
/// data: URIs. A data: URI must go through [safeImageProvider] + `Image(...)`
/// instead.
bool isNetworkImageUrl(String? raw) {
  if (raw == null) return false;
  final u = raw.trim();
  return u.startsWith('http://') || u.startsWith('https://');
}
