import 'package:equatable/equatable.dart';
import '../../domain/entities/memory_entity.dart';

abstract class CaptureState extends Equatable {
  const CaptureState();

  @override
  List<Object?> get props => [];
}

class CaptureInitial extends CaptureState {}

class CaptureLoading extends CaptureState {}

class CaptureLoaded extends CaptureState {
  final List<MemoryEntity> memories;

  const CaptureLoaded(this.memories);

  @override
  List<Object?> get props => [memories];
}

class CaptureSuccess extends CaptureState {
  final String message;

  const CaptureSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

class CaptureFailure extends CaptureState {
  final String errorMessage;

  const CaptureFailure(this.errorMessage);

  @override
  List<Object?> get props => [errorMessage];
}
