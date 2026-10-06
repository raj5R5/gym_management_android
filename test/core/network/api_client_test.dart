import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/core/config/app_config.dart';
import 'package:gym_management_app/core/network/api_client.dart';

class RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"status":"ok"}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) => closed = true;
}

void main() {
  test(
    'unconfigured client rejects requests before reaching transport',
    () async {
      final client = createApiClient(AppConfig.fromValues());
      addTearDown(() => client.close(force: true));
      final adapter = RecordingAdapter();
      client.httpClientAdapter = adapter;

      await expectLater(
        client.get<Object?>('health'),
        throwsA(
          isA<DioException>().having(
            (error) => error.error,
            'configuration error',
            isA<StateError>(),
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test('client preserves base path and decodes a JSON response', () async {
    final client = createApiClient(
      AppConfig.fromValues(apiBaseUrl: 'https://api.example.test/api/v1'),
    );
    addTearDown(() => client.close(force: true));
    final adapter = RecordingAdapter();
    client.httpClientAdapter = adapter;

    final response = await client.get<Map<String, dynamic>>('health');
    expect(response.data, {'status': 'ok'});
    expect(
      adapter.requests.single.uri.toString(),
      'https://api.example.test/api/v1/health',
    );
    expect(adapter.requests.single.headers['Authorization'], isNull);
  });

  test('disposing the provider closes its transport', () {
    final container = ProviderContainer(
      overrides: [appConfigProvider.overrideWithValue(AppConfig.fromValues())],
    );
    final adapter = RecordingAdapter();
    container.read(apiClientProvider).httpClientAdapter = adapter;
    container.dispose();
    expect(adapter.closed, isTrue);
  });
}
