import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:footpath_cebu/core/di/runtime_config.dart';
import 'package:footpath_cebu/data/repositories/api_dispute_repository.dart';
import 'package:footpath_cebu/data/repositories/mock_dispute_repository.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';
import 'package:footpath_cebu/domain/usecases/get_dispute.dart';
import 'package:footpath_cebu/domain/usecases/get_disputes.dart';
import 'package:footpath_cebu/domain/usecases/raise_dispute.dart';
import 'package:footpath_cebu/domain/usecases/respond_to_dispute.dart';

final disputeRepositoryProvider = Provider<DisputeRepository>(
  (ref) => useMockData ? MockDisputeRepository() : ApiDisputeRepository(),
);

final getDisputesProvider = Provider<GetDisputes>(
  (ref) => GetDisputes(ref.watch(disputeRepositoryProvider)),
);

final getDisputeProvider = Provider<GetDispute>(
  (ref) => GetDispute(ref.watch(disputeRepositoryProvider)),
);

final raiseDisputeProvider = Provider<RaiseDispute>(
  (ref) => RaiseDispute(ref.watch(disputeRepositoryProvider)),
);

final respondToDisputeProvider = Provider<RespondToDispute>(
  (ref) => RespondToDispute(ref.watch(disputeRepositoryProvider)),
);
