import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../auth/data/auth_failure.dart';
import 'member_photo_models.dart';

abstract interface class MemberPhotoRepository {
  Future<MemberPhotoReceipt> upload(
    MemberPhotoTarget target,
    PendingMemberPhoto pending,
    Uint8List bytes,
    void Function(double) progress,
    CancelToken cancel,
  );
  Future<MemberPhotoReceipt> remove(
    MemberPhotoTarget target,
    String operationKey,
    CancelToken cancel,
  );
  Future<MemberPhotoReceipt> status(
    MemberPhotoTarget target,
    String operationKey,
    CancelToken cancel,
  );
  Future<Uint8List> image(
    MemberPhotoTarget target,
    String url,
    CancelToken cancel,
  );
}

class DioMemberPhotoRepository implements MemberPhotoRepository {
  DioMemberPhotoRepository(this.client);
  final Dio client;
  String _path(MemberPhotoTarget target) {
    if (target.memberId == null) {
      throw const MemberPhotoFailure(
        'Save the member before uploading a photo.',
      );
    }
    return 'gyms/${target.scope.gymId}/members/${target.memberId}/photo';
  }

  MemberPhotoFailure _failure(DioException error) {
    final cause = error.error;
    if (cause is AuthFailure) {
      return MemberPhotoFailure(cause.message, code: cause.kind.name);
    }
    Object? data = error.response?.data;
    if (data is List<int>) {
      try {
        data = jsonDecode(utf8.decode(data));
      } catch (_) {
        data = null;
      }
    }
    final code = data is Map && data['error'] is Map
        ? data['error']['code'] as String?
        : null;
    final message = switch (code) {
      'PHOTO_STORAGE_UNAVAILABLE' =>
        'Photo storage is unavailable. Your selection is saved on this device; retry later.',
      'PHOTO_TOO_LARGE' => 'Choose a photo no larger than 5 MB.',
      'PHOTO_INVALID_IMAGE' || 'PHOTO_UNSUPPORTED_TYPE' =>
        'Choose a valid, single-frame JPEG, PNG or WebP photo, up to 20 megapixels.',
      'PHOTO_OPERATION_PENDING' =>
        'This saved photo is still processing. Retry it shortly.',
      'PHOTO_CHANGED' || 'PHOTO_OPERATION_CONFLICT' =>
        'The saved photo changed. Reload the member before choosing another photo.',
      'FORBIDDEN' => 'You no longer have permission to manage this photo.',
      'MEMBER_NOT_FOUND' =>
        'This member could not be found in the selected gym.',
      _ =>
        'The photo update could not be confirmed. Your selection is saved; retry the same operation.',
    };
    return MemberPhotoFailure(message, code: code);
  }

  Future<MemberPhotoReceipt> _send(
    MemberPhotoTarget target,
    Future<Response<dynamic>> Function() send,
  ) async {
    try {
      final response = (await send()).data;
      if (response is! Map ||
          response['success'] != true ||
          response['data'] is! Map) {
        throw const FormatException();
      }
      final receipt = MemberPhotoReceipt.fromJson(
        Map<String, dynamic>.from(response['data'] as Map),
      );
      if (receipt.memberId != target.memberId || receipt.revision < 0) {
        throw const FormatException();
      }
      if (receipt.url != null &&
          receipt.url != '${_path(target)}?v=${receipt.revision}') {
        throw const FormatException();
      }
      return receipt;
    } on DioException catch (error) {
      throw _failure(error);
    } catch (_) {
      throw const MemberPhotoFailure(
        'The photo response could not be verified. Retry the saved operation.',
      );
    }
  }

  @override
  Future<MemberPhotoReceipt> upload(
    MemberPhotoTarget target,
    PendingMemberPhoto pending,
    Uint8List bytes,
    void Function(double) progress,
    CancelToken cancel,
  ) {
    final type = bytes.length >= 12 && bytes[0] == 0x89
        ? 'image/png'
        : bytes.length >= 12 &&
              ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF'
        ? 'image/webp'
        : 'image/jpeg';
    return _send(
      target,
      () => client.put(
        _path(target),
        data: FormData.fromMap({
          'photo': MultipartFile.fromBytes(
            bytes,
            filename: 'member-photo',
            contentType: DioMediaType.parse(type),
          ),
        }),
        options: Options(
          contentType: Headers.multipartFormDataContentType,
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 90),
          headers: {'Idempotency-Key': pending.operationKey},
        ),
        cancelToken: cancel,
        onSendProgress: (sent, total) {
          if (total > 0) progress((sent / total).clamp(0, 1));
        },
      ),
    );
  }

  @override
  Future<MemberPhotoReceipt> remove(
    MemberPhotoTarget target,
    String operationKey,
    CancelToken cancel,
  ) => _send(
    target,
    () => client.delete(
      _path(target),
      options: Options(headers: {'Idempotency-Key': operationKey}),
      cancelToken: cancel,
    ),
  );
  @override
  Future<MemberPhotoReceipt> status(
    MemberPhotoTarget target,
    String operationKey,
    CancelToken cancel,
  ) => _send(
    target,
    () => client.get(
      '${_path(target)}/operations/$operationKey',
      cancelToken: cancel,
    ),
  );
  @override
  Future<Uint8List> image(
    MemberPhotoTarget target,
    String url,
    CancelToken cancel,
  ) async {
    if (!RegExp(
      '^${RegExp.escape(_path(target))}\\?v=[0-9]+\$',
    ).hasMatch(url)) {
      throw const MemberPhotoFailure('The member photo address is invalid.');
    }
    try {
      final response = await client.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 30),
        ),
        cancelToken: cancel,
      );
      final bytes = response.data;
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > maxMemberPhotoBytes ||
          !(response.headers.value('content-type')?.startsWith('image/jpeg') ??
              false)) {
        throw const FormatException();
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (error) {
      throw _failure(error);
    } catch (_) {
      throw const MemberPhotoFailure('The photo could not be displayed.');
    }
  }
}
