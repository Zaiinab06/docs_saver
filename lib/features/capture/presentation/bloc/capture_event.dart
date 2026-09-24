import 'package:equatable/equatable.dart';
import '../../domain/entities/memory_entity.dart';

abstract class CaptureEvent extends Equatable {
  const CaptureEvent();

  @override
  List<Object?> get props => [];
}

class LoadMemoriesEvent extends CaptureEvent {}

class ClearMemoriesEvent extends CaptureEvent {}

class AddMemoryEvent extends CaptureEvent {
  final String title;
  final String content;
  final List<String> tags;
  final String category;
  final String? mediaUrl;
  final String aiStatus;
  final Map<String, dynamic>? metadata;

  const AddMemoryEvent({
    required this.title,
    required this.content,
    this.tags = const [],
    this.category = 'General',
    this.mediaUrl,
    this.aiStatus = 'pending',
    this.metadata,
  });

  @override
  List<Object?> get props => [
    title,
    content,
    tags,
    category,
    mediaUrl,
    aiStatus,
    metadata,
  ];
}

class DeleteMemoryEvent extends CaptureEvent {
  final String memoryId;

  const DeleteMemoryEvent(this.memoryId);

  @override
  List<Object?> get props => [memoryId];
}

class SyncPendingMemoriesEvent extends CaptureEvent {}

class MemoryUpdatedEvent extends CaptureEvent {
  final MemoryEntity updatedMemory;

  const MemoryUpdatedEvent(this.updatedMemory);

  @override
  List<Object?> get props => [updatedMemory];
}
