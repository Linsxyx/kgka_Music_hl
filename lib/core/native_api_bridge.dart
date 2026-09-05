import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _RequestStartNative = Int64 Function(Pointer<Utf8> requestJson);
typedef _RequestStartDart = int Function(Pointer<Utf8> requestJson);
typedef _RequestPollNative = Pointer<Utf8> Function(Int64 requestId);
typedef _RequestPollDart = Pointer<Utf8> Function(int requestId);
typedef _RequestCancelNative = Int32 Function(Int64 requestId);
typedef _RequestCancelDart = int Function(int requestId);
typedef _FreeMemoryNative = Void Function(Pointer<Void> pointer);
typedef _FreeMemoryDart = void Function(Pointer<Void> pointer);

class NativeBridgeException implements Exception {
  const NativeBridgeException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'NativeBridgeException($statusCode): $message';
}

/// Thin Dart wrapper around the NativeAOT C ABI.
///
/// Network I/O never runs inside an FFI call. [request] only starts the managed
/// async operation, then uses short non-blocking polls to await its result.
class NativeApiBridge {
  NativeApiBridge._(DynamicLibrary library)
    : _start = library.lookupFunction<_RequestStartNative, _RequestStartDart>(
        'KgRequestStart',
      ),
      _poll = library.lookupFunction<_RequestPollNative, _RequestPollDart>(
        'KgRequestPoll',
      ),
      _cancel = library
          .lookupFunction<_RequestCancelNative, _RequestCancelDart>(
            'KgRequestCancel',
          ),
      _free = library.lookupFunction<_FreeMemoryNative, _FreeMemoryDart>(
        'KgFreeMemory',
      );

  static NativeApiBridge? tryLoad() {
    try {
      return NativeApiBridge._(_openLibrary());
    } on Object {
      // The native artifacts aren't present in ordinary desktop/dev builds yet.
      // ApiClient deliberately falls back to the existing Web API in that case.
      return null;
    }
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libKuGou.Net.Native.so');
    }
    if (Platform.isIOS) {
      // iOS links the NativeAOT framework into the application process.
      return DynamicLibrary.process();
    }
    if (Platform.isWindows) {
      return DynamicLibrary.open('KuGou.Net.Native.dll');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open('libKuGou.Net.Native.dylib');
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open('libKuGou.Net.Native.so');
    }
    throw UnsupportedError('Native KuGou SDK is unavailable on this platform.');
  }

  final _RequestStartDart _start;
  final _RequestPollDart _poll;
  final _RequestCancelDart _cancel;
  final _FreeMemoryDart _free;

  Future<dynamic> request({
    required String method,
    required String path,
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
    Map<String, Object?>? session,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final requestPointer = jsonEncode({
      'method': method,
      'path': path,
      'query': query,
      'body': body,
      'session': session,
    }).toNativeUtf8();

    late final int requestId;
    try {
      requestId = _start(requestPointer);
    } finally {
      malloc.free(requestPointer);
    }

    if (requestId <= 0) {
      throw const NativeBridgeException(
        'Native SDK failed to start the request.',
      );
    }

    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        _cancel(requestId);
        throw const NativeBridgeException(
          'Native SDK request timed out.',
          statusCode: 408,
        );
      }

      final responsePointer = _poll(requestId);
      if (responsePointer == nullptr) {
        _cancel(requestId);
        throw const NativeBridgeException(
          'Native SDK returned a null response.',
        );
      }

      late final String responseText;
      try {
        responseText = responsePointer.toDartString();
      } finally {
        _free(responsePointer.cast<Void>());
      }
      final response = jsonDecode(responseText);
      if (response is! Map<String, dynamic>) {
        throw const NativeBridgeException(
          'Native SDK returned malformed JSON.',
        );
      }

      final state = response['state'];
      if (state == 'pending') {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        continue;
      }
      if (state == 'completed') {
        return response['data'];
      }
      if (state == 'failed') {
        throw NativeBridgeException(
          response['error']?.toString() ?? 'Native SDK request failed.',
          statusCode: _asInt(response['statusCode']),
        );
      }
      throw const NativeBridgeException(
        'Native SDK returned an unknown request state.',
      );
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
