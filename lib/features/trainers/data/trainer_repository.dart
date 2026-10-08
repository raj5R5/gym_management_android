import 'package:dio/dio.dart';
import '../models/trainer_models.dart';
import '../models/trainer_draft.dart';
import 'trainer_failure.dart';

abstract interface class TrainerRepository {
  Future<TrainersPage> list(String gymId, TrainerListQuery query);
  Future<TrainerProfile> get(String gymId, String trainerId);
  Future<TrainerProfile> create(String gymId, TrainerDraft draft);
  Future<TrainerProfile> update(
    String gymId,
    String trainerId,
    TrainerDraft draft,
  );
}

class DioTrainerRepository implements TrainerRepository {
  DioTrainerRepository(this._client);
  final Dio _client;
  String _path(String gymId, [String? trainerId]) {
    for (final id in [gymId, ?trainerId]) {
      if (!RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id)) {
        throw const TrainerFailure('Invalid trainer context.');
      }
    }
    return 'gyms/$gymId/trainers${trainerId == null ? '' : '/$trainerId'}';
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
      throw TrainerFailure.fromDio(error);
    } on TrainerFailure {
      rethrow;
    } catch (_) {
      throw invalidTrainerResponse;
    }
  }

  void _scope(TrainerProfile trainer, String gymId, [String? trainerId]) {
    if (trainer.gymId.toLowerCase() != gymId.toLowerCase() ||
        trainerId != null &&
            trainer.id.toLowerCase() != trainerId.toLowerCase()) {
      throw const FormatException('Trainer scope mismatch.');
    }
  }

  TrainerProfile _profile(Object? data, String gymId, [String? trainerId]) {
    final trainer = TrainerProfile.fromJson(object(data));
    _scope(trainer, gymId, trainerId);
    return trainer;
  }

  @override
  Future<TrainersPage> list(String gymId, TrainerListQuery query) => _request(
    () => _client.get(_path(gymId), queryParameters: query.toParameters()),
    (response) {
      final result = TrainersPage.fromResponse(response);
      if (result.pagination.page != query.page ||
          result.pagination.limit != query.limit ||
          result.trainers.length > query.limit) {
        throw const FormatException('Pagination mismatch.');
      }
      for (final trainer in result.trainers) {
        _scope(trainer, gymId);
      }
      return result;
    },
  );
  @override
  Future<TrainerProfile> get(String gymId, String trainerId) => _request(
    () => _client.get(_path(gymId, trainerId)),
    (response) => _profile(response['data'], gymId, trainerId),
  );
  @override
  Future<TrainerProfile> create(String gymId, TrainerDraft draft) => _request(
    () => _client.post(_path(gymId), data: draft.toJson(editing: false)),
    (response) => _profile(response['data'], gymId),
  );
  @override
  Future<TrainerProfile> update(
    String gymId,
    String trainerId,
    TrainerDraft draft,
  ) => _request(
    () => _client.patch(
      _path(gymId, trainerId),
      data: draft.toJson(editing: true),
    ),
    (response) => _profile(response['data'], gymId, trainerId),
  );
}
