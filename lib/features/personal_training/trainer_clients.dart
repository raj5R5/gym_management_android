import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../auth/providers/auth_providers.dart';
import 'pt.dart';

/// A member the signed-in trainer works with.
class TrainerClient {
  const TrainerClient({
    required this.memberId,
    required this.memberCode,
    required this.name,
    this.phone,
  });
  TrainerClient.fromJson(Map<String, dynamic> json)
    : memberId = (json['memberId'] ?? json['id']) as String,
      memberCode = json['memberCode'] as String,
      name = '${json['firstName']} ${json['lastName']}'.trim(),
      phone = json['phone'] as String?;
  final String memberId, memberCode, name;
  final String? phone;
}

/// The trainer's own client list: take on any active member, or let one go.
class TrainerClientRepository {
  TrainerClientRepository(this._client);
  final Dio _client;

  Future<T> _call<T>(
    Future<Response<dynamic>> Function() call,
    T Function(dynamic data) parse,
  ) async {
    try {
      final body = (await call()).data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        throw const PtFailure('Unexpected response.');
      }
      return parse(body['data']);
    } on DioException catch (error) {
      final data = error.response?.data;
      final failure = data is Map ? data['error'] : null;
      final code = failure is Map ? failure['code'] : null;
      throw switch (code) {
        'MEMBER_NOT_FOUND' => const PtFailure(
          'That member is not in this gym.',
        ),
        'ASSIGNMENT_NOT_FOUND' => const PtFailure(
          'This member is no longer on your list.',
        ),
        'FORBIDDEN' => const PtFailure('Only active members can be taken on.'),
        _ => PtFailure.fromDio(error),
      };
    } on TypeError {
      throw const PtFailure('The server returned unexpected data.');
    }
  }

  // `/members` returns a bare list; `/trainer-assignments/me` a page object.
  List<TrainerClient> _rows(dynamic data) => [
    for (final row in (data is Map ? data['data'] : data) as List)
      TrainerClient.fromJson(row as Map<String, dynamic>),
  ];

  Future<List<TrainerClient>> mine(String gymId) => _call(
    () => _client.get<dynamic>(
      'gyms/$gymId/trainer-assignments/me',
      queryParameters: {'limit': '100'},
    ),
    _rows,
  );

  Future<List<TrainerClient>> search(String gymId, String text) => _call(
    () => _client.get<dynamic>(
      'gyms/$gymId/members',
      queryParameters: {'search': text, 'status': 'active', 'limit': '10'},
    ),
    _rows,
  );

  Future<void> takeOn(String gymId, String memberId) => _call(
    () => _client.post<dynamic>(
      'gyms/$gymId/trainer-assignments/me',
      data: {'memberId': memberId},
    ),
    (_) {},
  );

  Future<void> release(String gymId, String memberId) => _call(
    () =>
        _client.delete<dynamic>('gyms/$gymId/trainer-assignments/me/$memberId'),
    (_) {},
  );
}

final trainerClientRepositoryProvider = Provider<TrainerClientRepository>(
  (ref) => TrainerClientRepository(ref.watch(authenticatedApiClientProvider)),
);

final myClientsProvider = FutureProvider.autoDispose<List<TrainerClient>?>((
  ref,
) {
  final gymId = ref.watch(ptGymIdProvider);
  if (gymId == null) return null;
  return ref.watch(trainerClientRepositoryProvider).mine(gymId);
}, retry: (_, _) => null);

/// Searches active members; pops the chosen one. Members already on the
/// trainer's list are marked rather than hidden.
class TakeOnMemberDialog extends ConsumerStatefulWidget {
  const TakeOnMemberDialog({super.key, this.alreadyMine = const {}});
  final Set<String> alreadyMine;
  @override
  ConsumerState<TakeOnMemberDialog> createState() => _TakeOnMemberDialogState();
}

class _TakeOnMemberDialogState extends ConsumerState<TakeOnMemberDialog> {
  List<TrainerClient>? _results;
  String _query = '';
  String? _error;
  bool _loading = false;

  Future<void> _search(String value) async {
    final text = value.trim();
    _query = text;
    final gymId = ref.read(ptGymIdProvider);
    if (gymId == null || text.length < 2) {
      setState(() => _results = null);
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await ref
          .read(trainerClientRepositoryProvider)
          .search(gymId, text);
      // Ignore answers to a query the trainer has already typed past.
      if (mounted && text == _query) {
        setState(() {
          _results = rows;
          _error = null;
        });
      }
    } on PtFailure catch (failure) {
      if (mounted && text == _query) setState(() => _error = failure.message);
    } finally {
      if (mounted && text == _query) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Take on a member'),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('take-on-search'),
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name, code or phone',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _search,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_results case final rows?)
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Text('No active member matches.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final row in rows)
                      ListTile(
                        dense: true,
                        title: Text(row.name),
                        subtitle: Text(row.memberCode),
                        trailing: widget.alreadyMine.contains(row.memberId)
                            ? const Text('On your list')
                            : const Icon(Icons.add),
                        onTap: widget.alreadyMine.contains(row.memberId)
                            ? null
                            : () => Navigator.pop(context, row),
                      ),
                  ],
                ),
              ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
