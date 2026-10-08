import 'dart:async';
import 'package:gym_management_app/features/trainers/data/trainer_repository.dart';
import 'package:gym_management_app/features/trainers/models/trainer_draft.dart';
import 'package:gym_management_app/features/trainers/models/trainer_models.dart';
import '../admin_dashboard/dashboard_fakes.dart';

const trainerId = '000000000000000000000088';
Map<String, dynamic> trainerJson({
  String gymId = gymA,
  String firstName = 'Pat',
}) => {
  'id': trainerId,
  'gymId': gymId,
  'trainerCode': 'TR01',
  'firstName': firstName,
  'lastName': 'Lee',
  'phone': '+91 9876543210',
  'status': 'active',
};
TrainerDraft draft({String firstName = 'Pat'}) => TrainerDraft(
  trainerCode: 'TR01',
  firstName: firstName,
  lastName: 'Lee',
  phone: '+91 9876543210',
);

class FakeTrainerRepository implements TrainerRepository {
  Object? failure;
  bool empty = false, delayLists = false;
  int total = 1;
  final listCalls = <({String gymId, TrainerListQuery query})>[];
  final operations = <String>[];
  final writes = <Map<String, dynamic>>[];
  final pendingLists = <Completer<TrainersPage>>[];
  Completer<TrainerProfile>? saveGate;
  Map<String, dynamic> profile = trainerJson();
  void _check() {
    if (failure != null) throw failure!;
  }

  @override
  Future<TrainersPage> list(String gymId, TrainerListQuery query) async {
    listCalls.add((gymId: gymId, query: query));
    _check();
    if (delayLists) {
      final pending = Completer<TrainersPage>();
      pendingLists.add(pending);
      return pending.future;
    }
    return TrainersPage(
      empty
          ? []
          : [
              TrainerProfile.fromJson({...profile, 'gymId': gymId}),
            ],
      Pagination.fromJson({
        'page': query.page,
        'limit': query.limit,
        'total': empty ? 0 : total,
      }),
    );
  }

  @override
  Future<TrainerProfile> get(String gymId, String id) async {
    operations.add('get:$gymId:$id');
    _check();
    return TrainerProfile.fromJson({...profile, 'gymId': gymId});
  }

  @override
  Future<TrainerProfile> create(String gymId, TrainerDraft draft) async {
    operations.add('create:$gymId');
    writes.add(draft.toJson(editing: false));
    _check();
    if (saveGate != null) return saveGate!.future;
    profile = {...trainerJson(gymId: gymId), ...writes.last};
    return TrainerProfile.fromJson(profile);
  }

  @override
  Future<TrainerProfile> update(
    String gymId,
    String id,
    TrainerDraft draft,
  ) async {
    operations.add('update:$gymId:$id');
    writes.add(draft.toJson(editing: true));
    _check();
    if (saveGate != null) return saveGate!.future;
    profile = {...profile, ...writes.last, 'gymId': gymId};
    return TrainerProfile.fromJson(profile);
  }
}
