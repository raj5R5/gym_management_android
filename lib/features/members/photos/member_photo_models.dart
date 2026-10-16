import 'dart:convert';
import 'dart:math';
import '../models/pending_onboarding.dart';

const maxMemberPhotoBytes = 5 * 1024 * 1024;

class MemberPhotoFailure implements Exception {
  const MemberPhotoFailure(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}

String newPhotoOperationKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class MemberPhotoTarget {
  MemberPhotoTarget(this.scope, {this.memberId}) {
    if (memberId != null && !RegExp(r'^[a-f0-9]{24}$').hasMatch(memberId!)) {
      throw const FormatException('Invalid photo member scope.');
    }
  }
  factory MemberPhotoTarget.fromJson(Map<String, dynamic> json) =>
      MemberPhotoTarget(
        OnboardingScope.fromJson(
          Map<String, dynamic>.from(json['scope'] as Map),
        ),
        memberId: json['memberId'] as String?,
      );
  final OnboardingScope scope;
  final String? memberId;
  String get key => '${scope.storageKey}.photo.${memberId ?? 'draft'}';
  Map<String, dynamic> toJson() => {
    'scope': scope.toJson(),
    'memberId': memberId,
  };
  @override
  bool operator ==(Object other) =>
      other is MemberPhotoTarget && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

class PendingMemberPhoto {
  PendingMemberPhoto({
    required this.target,
    required this.operationKey,
    required this.remove,
    this.fileName,
    this.attempted = false,
    this.registrationKeys = const [],
  }) {
    if (!RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(operationKey) ||
        (!remove &&
            (fileName == null ||
                !RegExp(
                  r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}\.photo$',
                ).hasMatch(fileName!)))) {
      throw const FormatException('Invalid saved photo operation.');
    }
  }
  factory PendingMemberPhoto.fromJson(Map<String, dynamic> json) =>
      PendingMemberPhoto(
        target: MemberPhotoTarget.fromJson(
          Map<String, dynamic>.from(json['target'] as Map),
        ),
        operationKey: json['operationKey'] as String,
        remove: json['remove'] as bool,
        fileName: json['fileName'] as String?,
        attempted: json['attempted'] as bool,
        registrationKeys: (json['registrationKeys'] as List).cast<String>(),
      );
  final MemberPhotoTarget target;
  final String operationKey;
  final bool remove, attempted;
  final String? fileName;
  final List<String> registrationKeys;
  PendingMemberPhoto copyWith({
    MemberPhotoTarget? target,
    bool? attempted,
    List<String>? registrationKeys,
    String? operationKey,
  }) => PendingMemberPhoto(
    target: target ?? this.target,
    operationKey: operationKey ?? this.operationKey,
    remove: remove,
    fileName: fileName,
    attempted: attempted ?? this.attempted,
    registrationKeys: registrationKeys ?? this.registrationKeys,
  );
  Map<String, dynamic> toJson() => {
    'target': target.toJson(),
    'operationKey': operationKey,
    'remove': remove,
    'fileName': fileName,
    'attempted': attempted,
    'registrationKeys': registrationKeys,
  };
  String encode() => jsonEncode(toJson());
}

class MemberPhotoReceipt {
  MemberPhotoReceipt.fromJson(Map<String, dynamic> json)
    : memberId = json['memberId'] as String,
      url = json['photoUrl'] as String?,
      revision = json['photoRevision'] as int,
      state = json['state'] as String?;
  final String memberId;
  final String? url, state;
  final int revision;
}
