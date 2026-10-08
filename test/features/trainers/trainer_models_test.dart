import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/features/trainers/models/trainer_models.dart';
import 'package:gym_management_app/features/trainers/models/trainer_draft.dart';
import 'package:gym_management_app/features/admin_dashboard/models/dashboard_models.dart';
import 'trainer_fakes.dart';

void main() {
  test('required profile and absent/null optional fields', () {
    final profile = TrainerProfile.fromJson(
      trainerJson()
        ..addAll({'gender': null, 'address': null, 'specializations': null}),
    );
    expect(profile.name, 'Pat Lee');
    expect(profile.trainerCode, 'TR01');
    expect(profile.status, TrainerStatus.active);
    expect(profile.branchId, isNull);
    expect(profile.address, isNull);
    expect(profile.specializations, isNull);
    expect(profile.dateOfBirth, isNull);
  });
  test(
    'full DTO parses dates, address, specializations and preserves branch ID',
    () {
      final profile = TrainerProfile.fromJson(
        trainerJson()..addAll({
          'branchId': '000000000000000000000099',
          'dateOfBirth': '1995-06-12',
          'gender': 'other',
          'address': {
            'line1': 'Road',
            'city': 'City',
            'countryCode': 'IN',
            'line2': 'Floor 2',
          },
          'specializations': ['Strength', 'Mobility'],
          'createdAt': '2026-03-01T12:00:00Z',
          'updatedAt': '2026-03-02T12:00:00Z',
          'userId': 'unused-account-id',
        }),
      );
      expect(profile.dateOfBirth.toString(), '1995-06-12');
      expect(profile.address!.display, 'Road, Floor 2, City, IN');
      expect(profile.specializations, ['Strength', 'Mobility']);
      expect(profile.createdAt!.isUtc, isTrue);
      expect(profile.updatedAt!.day, 2);
      expect(profile.branchId, '000000000000000000000099');
    },
  );
  test('server list pagination and empty results', () {
    final page = TrainersPage.fromResponse({
      'data': [trainerJson()],
      'meta': {
        'pagination': {'page': 2, 'limit': 20, 'total': 41},
      },
    });
    expect(page.trainers.single.trainerCode, 'TR01');
    expect(page.pagination.hasPrevious, isTrue);
    expect(page.pagination.hasNext, isTrue);
    expect(
      TrainersPage.fromResponse({
        'data': [],
        'meta': {
          'pagination': {'page': 1, 'limit': 20, 'total': 0},
        },
      }).trainers,
      isEmpty,
    );
  });
  for (final page in [0, 10001]) {
    test(
      'page $page rejected',
      () => expect(() => TrainerListQuery(page: page), throwsFormatException),
    );
  }
  for (final limit in [0, 101]) {
    test(
      'limit $limit rejected',
      () => expect(() => TrainerListQuery(limit: limit), throwsFormatException),
    );
  }
  test('maximum page and limit honored', () {
    expect(TrainerListQuery(page: 10000, limit: 100).toParameters(), {
      'page': '10000',
      'limit': '100',
    });
    expect(
      Pagination.fromJson({
        'page': 10000,
        'limit': 100,
        'total': 1000001,
      }).hasNext,
      isFalse,
    );
  });
  test('malformed DTO/collection/pagination fails parsing', () {
    expect(
      () => TrainerProfile.fromJson(trainerJson()..remove('phone')),
      throwsFormatException,
    );
    expect(
      () => TrainersPage.fromResponse({'data': {}, 'meta': {}}),
      throwsFormatException,
    );
    expect(
      () => Pagination.fromJson({'page': 1, 'limit': 20, 'total': -1}),
      throwsFormatException,
    );
  });
  for (final value in <Object>[
    ['Strength', 'strength'],
    [' '],
    [1],
    List.filled(11, 'x'),
    ['x' * 81],
  ]) {
    test(
      'invalid specializations $value rejected',
      () => expect(() => parseSpecializations(value), throwsFormatException),
    );
  }
  test(
    'specialization input keeps commas literal and validates duplicates/limits',
    () {
      expect(specializationsFromInput(' Strength, mobility\n Fitness '), [
        'Strength, mobility',
        'Fitness',
      ]);
      expect(validateSpecializations('Yoga\nyoga'), isNotNull);
      expect(validateSpecializations(''), isNull);
    },
  );
  test('POST whitelist omits protected fields and optional values', () {
    expect(draft().toJson(editing: false), {
      'trainerCode': 'TR01',
      'firstName': 'Pat',
      'lastName': 'Lee',
      'phone': '+91 9876543210',
    });
  });
  test(
    'PATCH excludes code/scope/linkage/branch, supports nullable clearing',
    () {
      final json = draft().toJson(editing: true);
      for (final key in [
        'trainerCode',
        'gymId',
        'userId',
        'branchId',
        'role',
        'permissions',
      ]) {
        expect(json.containsKey(key), isFalse);
      }
      for (final key in [
        'dateOfBirth',
        'gender',
        'address',
        'specializations',
      ]) {
        expect(json.containsKey(key), isTrue);
        expect(json[key], isNull);
      }
    },
  );
  test(
    'specializations can be replaced or explicitly empty; status is supported',
    () {
      final input = TrainerDraft(
        trainerCode: ' tr01 ',
        firstName: ' Pat ',
        lastName: 'Lee',
        phone: '9876543210',
        status: TrainerStatus.inactive,
        specializations: [],
      );
      expect(input.toJson(editing: false)['trainerCode'], 'TR01');
      expect(input.toJson(editing: true)['specializations'], []);
      expect(input.toJson(editing: true)['status'], 'inactive');
    },
  );
  test('invalid identity/dob/gender cannot construct a request', () {
    expect(
      () => draft(firstName: '').toJson(editing: false),
      throwsFormatException,
    );
    expect(
      () => TrainerDraft(
        trainerCode: 'TR01',
        firstName: 'Pat',
        lastName: 'Lee',
        phone: '9876543210',
        dateOfBirth: CalendarDate(9999, 1, 1),
      ).toJson(editing: false),
      throwsFormatException,
    );
    expect(
      () => TrainerDraft(
        trainerCode: 'TR01',
        firstName: 'Pat',
        lastName: 'Lee',
        phone: '9876543210',
        gender: 'unknown',
      ).toJson(editing: false),
      throwsFormatException,
    );
  });
}
