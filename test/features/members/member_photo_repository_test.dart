import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/members/photos/member_photo_models.dart';
import 'package:gym_management_app/features/members/photos/member_photo_repository.dart';
import '../auth/auth_fakes.dart';
import 'photo_test_support.dart' show photoTarget, photoBytes;

void main() {
  late Dio client;
  late DioMemberPhotoRepository repo;
  final pending = PendingMemberPhoto(
    target: photoTarget,
    operationKey: newPhotoOperationKey(),
    remove: false,
    fileName: '${newPhotoOperationKey()}.photo',
  );
  final path =
      'gyms/${photoTarget.scope.gymId}/members/${photoTarget.memberId}/photo';
  Map<String, dynamic> receipt({String? url}) => {
    'success': true,
    'data': {
      'memberId': photoTarget.memberId,
      'photoRevision': 2,
      'photoUrl': url ?? '$path?v=2',
    },
  };
  setUp(() {
    client = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1/'));
    repo = DioMemberPhotoRepository(client);
  });
  tearDown(() => client.close(force: true));
  test(
    'multipart uses the scoped endpoint, one photo and durable idempotency key',
    () async {
      client.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.method, 'PUT');
            expect(options.path, path);
            expect(options.headers['Idempotency-Key'], pending.operationKey);
            final data = options.data as FormData;
            expect(data.fields, isEmpty);
            expect(data.files.length, 1);
            expect(data.files.single.key, 'photo');
            expect(data.files.single.value.contentType.toString(), 'image/png');
            handler.next(options);
          },
        ),
      );
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse(receipt()),
      );
      expect(
        (await repo.upload(
          photoTarget,
          pending,
          photoBytes,
          (_) {},
          CancelToken(),
        )).revision,
        2,
      );
    },
  );
  test(
    'replacement/removal and status reuse existing target without member or payment writes',
    () async {
      final calls = <String>[];
      client.httpClientAdapter = CallbackAdapter((options) {
        calls.add('${options.method}:${options.path}');
        if (options.method == 'DELETE') {
          expect(options.headers['Idempotency-Key'], pending.operationKey);
        }
        return jsonResponse(receipt());
      });
      await repo.remove(photoTarget, pending.operationKey, CancelToken());
      await repo.status(photoTarget, pending.operationKey, CancelToken());
      expect(calls, [
        'DELETE:$path',
        'GET:$path/operations/${pending.operationKey}',
      ]);
    },
  );
  test(
    'foreign receipt URL or member ID is rejected as an unverified result',
    () async {
      for (final data in [
        receipt(url: 'https://attacker.invalid/photo'),
        {
          'success': true,
          'data': {'memberId': 'c' * 24, 'photoRevision': 1},
        },
      ]) {
        client.httpClientAdapter = CallbackAdapter((_) => jsonResponse(data));
        await expectLater(
          repo.remove(photoTarget, pending.operationKey, CancelToken()),
          throwsA(isA<MemberPhotoFailure>()),
        );
      }
    },
  );
  test(
    'photo bytes require same-gym protected relative URL and valid response type',
    () async {
      var calls = 0;
      client.httpClientAdapter = CallbackAdapter((options) {
        calls++;
        expect(options.responseType, ResponseType.bytes);
        return ResponseBody.fromBytes(
          photoBytes,
          200,
          headers: {
            Headers.contentTypeHeader: ['image/jpeg'],
          },
        );
      });
      expect(
        await repo.image(photoTarget, '$path?v=2', CancelToken()),
        photoBytes,
      );
      for (final url in [
        'https://example.invalid/$path?v=2',
        '$path?v=2&x=1',
        path.replaceAll(photoTarget.memberId!, 'c' * 24),
      ]) {
        await expectLater(
          repo.image(photoTarget, url, CancelToken()),
          throwsA(isA<MemberPhotoFailure>()),
        );
      }
      expect(calls, 1);
    },
  );
  test(
    'missing, oversized and non-image download uses recoverable fallback failure',
    () async {
      for (final bytes in [Uint8List(0), Uint8List(maxMemberPhotoBytes + 1)]) {
        client.httpClientAdapter = CallbackAdapter(
          (_) => ResponseBody.fromBytes(
            bytes,
            200,
            headers: {
              Headers.contentTypeHeader: ['image/jpeg'],
            },
          ),
        );
        await expectLater(
          repo.image(photoTarget, '$path?v=2', CancelToken()),
          throwsA(isA<MemberPhotoFailure>()),
        );
      }
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse({'provider': 'internal-secret-path'}),
      );
      await expectLater(
        repo.image(photoTarget, '$path?v=2', CancelToken()),
        throwsA(isA<MemberPhotoFailure>()),
      );
    },
  );
  test(
    'API provider errors expose only safe photo messages and stable error codes',
    () async {
      client.httpClientAdapter = CallbackAdapter(
        (_) => jsonResponse({
          'success': false,
          'error': {
            'code': 'PHOTO_STORAGE_UNAVAILABLE',
            'message': 'internal-provider-secret',
          },
        }, status: 503),
      );
      await expectLater(
        repo.remove(photoTarget, pending.operationKey, CancelToken()),
        throwsA(
          isA<MemberPhotoFailure>()
              .having((e) => e.code, 'code', 'PHOTO_STORAGE_UNAVAILABLE')
              .having(
                (e) => e.message.contains('internal'),
                'no internal details',
                false,
              ),
        ),
      );
    },
  );
}
