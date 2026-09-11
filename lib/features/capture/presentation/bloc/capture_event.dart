import 'package:equatable/equatable.dart';
import '../../domain/entities/memory_entity.dart';

abstract class CaptureEvent extends Equatable {
  const CaptureEvent();

  @override
  List<Object?> get props => [];
}

class LoadMemoriesEvent extends CaptureEvent {}

class AddMemoryEvent extends CaptureEvent {
  final String title;
  final String content;
  final List<String> tags;
  final String? mediaUrl;

  const AddMemoryEvent({
    required this.title,
    required this.content,
    this.tags = const [],
    this.mediaUrl,
  });

  @override
  List<Object?> get props => [title, content, tags, mediaUrl];
}

class SyncPendingMemoriesEvent extends CaptureEvent {}

class MemoryUpdatedEvent extends CaptureEvent {
  final MemoryEntity updatedMemory;

  const MemoryUpdatedEvent(this.updatedMemory);

  @override
  List<Object?> get props => [updatedMemory];
}
