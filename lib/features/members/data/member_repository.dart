import 'package:dio/dio.dart';
import '../models/member_models.dart';
import '../models/member_draft.dart';
import 'member_failure.dart';

abstract interface class MemberRepository {
  Future<MembersPage> list(String gymId, MemberListQuery query);
  Future<MemberProfile> get(String gymId, String memberId);
  Future<MemberSummary> summary(String gymId, String memberId);
  Future<MemberProfile> onboard(String gymId, MemberDraft draft);
  Future<MemberProfile> update(
    String gymId,
    String memberId,
    MemberDraft draft,
  );
  Future<MembershipHistory> memberships(
    String gymId,
    String memberId,
    int page,
  );
  Future<MembershipDetail> membership(
    String gymId,
    String memberId,
    String subscriptionId,
  );
}

/// One authoritative, deduplicated history snapshot, including future/expired
/// periods. Callers supply their live account/gym guard between paginated reads.
extension MemberMembershipHistory on MemberRepository {
  Future<List<Membership>> allMemberships(
    String gymId,
    String memberId, {
    required void Function() guard,
    Future<MembershipHistory> Function(int page)? readPage,
  }) async {
    final records = <String, Membership>{};
    for (var page = 1; ; page++) {
      guard();
      final history =
          await (readPage?.call(page) ?? memberships(gymId, memberId, page));
      guard();
      for (final record in [
        ...history.subscriptions,
        if (history.current != null) history.current!,
      ]) {
        records[record.id] = record;
      }
      if (!history.pagination.hasNext) break;
    }
    return List.unmodifiable(records.values);
  }
}

class DioMemberRepository implements MemberRepository {
  DioMemberRepository(this._client);
  final Dio _client;
  void _id(String id) {
    if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id)) {
      throw const MemberFailure('Invalid member context.');
    }
  }

  String _members(String gymId, [String? memberId]) {
    _id(gymId);
    if (memberId != null) _id(memberId);
    return 'gyms/$gymId/members${memberId == null ? '' : '/$memberId'}';
  }

  Future<T> _request<T>(
    Future<Response<dynamic>> Function() send,
    T Function(Map<String, dynamic>) parse,
  ) async {
    try {
      final response = object((await send()).data);
      if (response['success'] != true) {
        throw const FormatException('Invalid envelope.');
      }
      return parse(response);
    } on DioException catch (error) {
      throw MemberFailure.fromDio(error);
    } on MemberFailure {
      rethrow;
    } catch (_) {
      throw invalidMemberResponse;
    }
  }

  MemberProfile _profile(Object? data, String gymId, [String? memberId]) {
    final member = MemberProfile.fromJson(object(data));
    if (member.gymId?.toLowerCase() != gymId.toLowerCase() ||
        memberId != null && member.id.toLowerCase() != memberId.toLowerCase()) {
      throw const FormatException('Member scope mismatch.');
    }
    return member;
  }

  @override
  Future<MembersPage> list(String gymId, MemberListQuery query) {
    final path = _members(gymId);
    return _request(
      () => _client.get(path, queryParameters: query.toParameters()),
      (response) {
        final pagination = Pagination.fromJson(
          object(object(response['meta'])['pagination']),
        );
        final members = items(
          response['data'],
          (data) => _profile(data, gymId),
        );
        if (pagination.page != query.page ||
            pagination.limit != query.limit ||
            members.length > pagination.limit) {
          throw const FormatException('Pagination mismatch.');
        }
        return MembersPage(members, pagination);
      },
    );
  }

  @override
  Future<MemberProfile> get(String gymId, String memberId) => _request(
    () => _client.get(_members(gymId, memberId)),
    (response) => _profile(response['data'], gymId, memberId),
  );
  @override
  Future<MemberSummary> summary(String gymId, String memberId) => _request(
    () => _client.get('${_members(gymId, memberId)}/summary'),
    (response) {
      final result = MemberSummary.fromJson(object(response['data']));
      if (result.member.id.toLowerCase() != memberId.toLowerCase()) {
        throw const FormatException('Member scope mismatch.');
      }
      return result;
    },
  );
  @override
  Future<MemberProfile> onboard(String gymId, MemberDraft draft) =>
      _request(() {
        _id(gymId);
        return _client.post(
          'gyms/$gymId/member-onboarding',
          data: draft.toJson(editing: false),
        );
      }, (response) => _profile(response['data'], gymId));
  @override
  Future<MemberProfile> update(
    String gymId,
    String memberId,
    MemberDraft draft,
  ) => _request(
    () => _client.patch(
      _members(gymId, memberId),
      data: draft.toJson(editing: true),
    ),
    (response) => _profile(response['data'], gymId, memberId),
  );
  @override
  Future<MembershipHistory> memberships(
    String gymId,
    String memberId,
    int page,
  ) => _request(
    () {
      final query = MemberListQuery(page: page);
      return _client.get(
        '${_members(gymId, memberId)}/memberships',
        queryParameters: query.toParameters(),
      );
    },
    (response) {
      final result = MembershipHistory.fromResponse(
        object(response['data']),
        object(object(response['meta'])['pagination']),
      );
      if (result.memberId.toLowerCase() != memberId.toLowerCase() ||
          result.pagination.page != page ||
          result.pagination.limit != 20) {
        throw const FormatException('History context mismatch.');
      }
      return result;
    },
  );
  @override
  Future<MembershipDetail> membership(
    String gymId,
    String memberId,
    String subscriptionId,
  ) => _request(
    () {
      _id(subscriptionId);
      return _client.get(
        '${_members(gymId, memberId)}/memberships/$subscriptionId',
      );
    },
    (response) {
      final data = object(response['data']);
      final subscription = object(data['subscription']);
      if (subscription['gymId'] != gymId ||
          subscription['memberId'] != memberId ||
          subscription['id'] != subscriptionId) {
        throw const FormatException('Membership scope mismatch.');
      }
      return MembershipDetail.fromJson(data);
    },
  );
}
