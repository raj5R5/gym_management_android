import '../../../shared/models/profile_models.dart';
import '../../admin_dashboard/models/dashboard_models.dart';
export '../../../shared/models/profile_models.dart';

enum TrainerStatus { active, inactive, suspended }

const trainerGenders = [
  'female',
  'male',
  'non_binary',
  'other',
  'prefer_not_to_say',
];

class TrainerProfile {
  TrainerProfile.fromJson(Map<String, dynamic> json)
    : id = text(json, 'id'),
      gymId = text(json, 'gymId'),
      trainerCode = text(json, 'trainerCode'),
      firstName = text(json, 'firstName'),
      lastName = text(json, 'lastName'),
      phone = text(json, 'phone'),
      status = TrainerStatus.values.byName(text(json, 'status')),
      branchId = optionalText(json, 'branchId'),
      gender = optionalText(json, 'gender'),
      dateOfBirth = json['dateOfBirth'] == null
          ? null
          : CalendarDate.parse(text(json, 'dateOfBirth')),
      address = optionalObject(json['address'], ProfileAddress.fromJson),
      specializations = parseSpecializations(json['specializations']),
      createdAt = json['createdAt'] == null
          ? null
          : DateTime.parse(text(json, 'createdAt')),
      updatedAt = json['updatedAt'] == null
          ? null
          : DateTime.parse(text(json, 'updatedAt'));
  final String id, gymId, trainerCode, firstName, lastName, phone;
  final TrainerStatus status;
  final String? branchId, gender;
  final CalendarDate? dateOfBirth;
  final ProfileAddress? address;
  final List<String>? specializations;
  final DateTime? createdAt, updatedAt;
  // userId is intentionally not retained or displayed; account provisioning is
  // outside M29 and the DTO supplies no useful account display information.
  String get name => '$firstName $lastName';
}

List<String>? parseSpecializations(Object? value) {
  if (value == null) return null;
  if (value is! List ||
      value.length > 10 ||
      value.any(
        (item) =>
            item is! String || item.trim().isEmpty || item.trim().length > 80,
      )) {
    throw const FormatException('Invalid specializations.');
  }
  final result = value.cast<String>();
  if (result.map((item) => item.trim().toLowerCase()).toSet().length !=
      result.length) {
    throw const FormatException('Duplicate specializations.');
  }
  return List.unmodifiable(result);
}

class TrainersPage {
  TrainersPage(this.trainers, this.pagination);
  factory TrainersPage.fromResponse(Map<String, dynamic> response) =>
      TrainersPage(
        items(response['data'], TrainerProfile.fromJson),
        Pagination.fromJson(object(object(response['meta'])['pagination'])),
      );
  final List<TrainerProfile> trainers;
  final Pagination pagination;
}

class TrainerListQuery {
  TrainerListQuery({
    this.page = 1,
    this.limit = 20,
    String search = '',
    this.status,
  }) : search = search.trim() {
    if (page < 1 ||
        page > 10000 ||
        limit < 1 ||
        limit > 100 ||
        this.search.length > 100) {
      throw const FormatException('Invalid trainer query.');
    }
  }
  final int page, limit;
  final String search;
  final TrainerStatus? status;
  TrainerListQuery withPage(int page) => TrainerListQuery(
    page: page,
    limit: limit,
    search: search,
    status: status,
  );
  Map<String, dynamic> toParameters() => {
    'page': '$page',
    'limit': '$limit',
    if (search.isNotEmpty) 'search': search,
    if (status != null) 'status': status!.name,
  };
}
