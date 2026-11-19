import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens public HTTPS policy pages in the system browser, never an auth WebView.
class PublicLinks {
  const PublicLinks();
  static const _channel = MethodChannel('gym_management/public_links');

  Future<void> open(Uri uri) async {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Only public HTTPS links can be opened.');
    }
    await _channel.invokeMethod<void>('openHttps', uri.toString());
  }
}

final publicLinksProvider = Provider<PublicLinks>((_) => const PublicLinks());
