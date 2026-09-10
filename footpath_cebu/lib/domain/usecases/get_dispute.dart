import 'package:footpath_cebu/domain/entities/dispute.dart';
import 'package:footpath_cebu/domain/repositories/dispute_repository.dart';

class GetDispute {
  const GetDispute(this._reader);

  final DisputeDetailReader _reader;

  Future<Dispute> call(String disputeId) => _reader.fetchDispute(disputeId);
}
