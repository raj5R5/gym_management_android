import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../data/owner_registration_repository.dart';

final ownerRegistrationRepositoryProvider =
    Provider<OwnerRegistrationRepository>(
      (ref) => DioOwnerRegistrationRepository(ref.watch(apiClientProvider)),
    );
