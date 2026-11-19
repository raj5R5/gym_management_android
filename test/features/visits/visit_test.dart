import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/visits/visit_models.dart';
import 'package:gym_management_app/features/visits/visit_repository.dart';
import '../auth/auth_fakes.dart';

const gym = '6af80a503ad696b0ec816cd7';
const member = '6af80a763ad696b0ec816ce1';

Map<String, dynamic> visitJson({bool override = false}) => {
  'id': 'visit-1',
  'memberId': member,
  'visitDate': '2026-11-14',
  'checkedInAt': '2026-11-14T08:40:00.000Z',
  'method': 'qr',
  'membershipState': override ? 'expired' : 'active',
  'override': override,
};

void main() {
  group('member QR', () {
    test('encodes gym and member, and parses only this gym’s cards', () {
      final raw = MemberQrCode.encode(gymId: gym, memberId: member);
      expect(raw, 'MDK1:$gym:$member');
      expect(MemberQrCode.memberIdFor(raw, gymId: gym), member);
      expect(MemberQrCode.memberIdFor(' $raw\n', gymId: gym), member);
      const other = '6af80a503ad696b0ec816cd8';
      expect(MemberQrCode.memberIdFor(raw, gymId: other), isNull);
      expect(MemberQrCode.isOtherGym(raw, gymId: other), isTrue);
    });
    test('rejects other QR codes and malformed ids', () {
      for (final raw in [
        'https://example.com',
        'MDK1:$gym',
        'MDK2:$gym:$member',
        'MDK1:$gym:not-an-id',
        'MDK1:$gym:$member:extra',
      ]) {
        expect(MemberQrCode.memberIdFor(raw, gymId: gym), isNull, reason: raw);
        expect(MemberQrCode.isOtherGym(raw, gymId: gym), isFalse, reason: raw);
      }
    });
  });

  group('visit repository', () {
    late List<RequestOptions> requests;
    VisitRepository repository(ResponseBody Function(RequestOptions) respond) {
      requests = [];
      final client =
          Dio(BaseOptions(baseUrl: 'https://api.example.invalid/api/v1/'))
            ..httpClientAdapter = CallbackAdapter((request) {
              requests.add(request);
              return respond(request);
            });
      return VisitRepository(client);
    }

    test(
      'check-in posts member, method and override and parses the result',
      () async {
        final result = await repository(
          (_) => jsonResponse({
            'success': true,
            'data': {
              'member': {
                'id': member,
                'memberCode': 'IT001',
                'firstName': 'Aarav',
                'lastName': 'Sharma',
                'phone': '9876543201',
                'status': 'active',
              },
              'membership': null,
              'balancePaise': 0,
              'visit': visitJson(),
              'alreadyCheckedIn': true,
            },
          }, status: 200),
        ).checkIn(gym, member, method: VisitMethod.qr);
        expect(requests.single.path, 'gyms/$gym/visits');
        expect(requests.single.data, {
          'memberId': member,
          'method': 'qr',
          'override': false,
        });
        expect(result.alreadyCheckedIn, isTrue);
        expect(result.member.name, 'Aarav Sharma');
        expect(result.visit.method, VisitMethod.qr);
      },
    );

    test(
      'a refused check-in reports the membership state for the prompt',
      () async {
        final refusing = repository(
          (_) => jsonResponse({
            'success': false,
            'error': {
              'code': 'MEMBERSHIP_NOT_ACTIVE',
              'message': 'No active membership.',
              'details': {
                'membershipState': 'expired',
                'planName': 'Monthly',
                'endDate': '2026-11-04',
              },
            },
          }, status: 409),
        );
        await expectLater(
          refusing.checkIn(gym, member),
          throwsA(
            isA<MembershipNotActive>()
                .having((e) => e.state, 'state', 'expired')
                .having(
                  (e) => e.message,
                  'message',
                  'The Monthly membership has expired. Renew it, or check in anyway.',
                ),
          ),
        );
      },
    );

    test('inactive profiles and bad ids fail with safe messages', () async {
      final failing = repository(
        (_) => jsonResponse({
          'success': false,
          'error': {'code': 'MEMBER_NOT_ACTIVE', 'message': 'x'},
        }, status: 409),
      );
      await expectLater(
        failing.checkIn(gym, member),
        throwsA(
          isA<VisitFailure>().having(
            (e) => e.message,
            'message',
            contains('inactive or suspended'),
          ),
        ),
      );
      await expectLater(
        failing.checkIn(gym, 'nope'),
        throwsA(isA<VisitFailure>()),
      );
      expect(requests, hasLength(1), reason: 'invalid ids never reach the API');
    });

    test('history labels the last visit in plain words', () async {
      final history = await repository(
        (_) => jsonResponse({
          'success': true,
          'data': {
            'memberId': member,
            'today': '2026-11-14',
            'visitsLast30Days': 4,
            'lastVisitDate': '2026-11-12',
            'daysSinceLastVisit': 2,
            'data': [visitJson()],
            'pagination': {'page': 1, 'limit': 10, 'total': 9},
          },
        }),
      ).history(gym, member);
      expect(history.lastVisitLabel, '2 days ago');
      expect(history.visitsLast30Days, 4);
      expect(history.pagination.total, 9);
    });
  });
}
