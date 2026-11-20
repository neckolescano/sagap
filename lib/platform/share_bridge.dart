import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hands a file to Android's share sheet. Nothing is uploaded by Sagap;
/// the user picks where it goes. Tests replace it with a fake.
abstract interface class ShareBridge {
  /// Shares a PNG image named [fileName]. Throws [PlatformException] when
  /// the file can't be written or no app can receive it.
  Future<void> shareImage(Uint8List png, String fileName);
}

class PlatformShareBridge implements ShareBridge {
  static const _channel = MethodChannel('sagap/share');

  @override
  Future<void> shareImage(Uint8List png, String fileName) =>
      _channel.invokeMethod<void>('shareImage', {'bytes': png, 'fileName': fileName});
}

final shareBridgeProvider = Provider<ShareBridge>((ref) => PlatformShareBridge());
