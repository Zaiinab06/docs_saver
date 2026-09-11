import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/capture_bloc.dart';
import '../bloc/capture_event.dart';
import '../bloc/capture_state.dart';
import 'package:second_brain/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:second_brain/features/auth/presentation/bloc/auth_event.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _submitMemory() {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;

    context.read<CaptureBloc>().add(
      AddMemoryEvent(title: _titleController.text.trim(), content: content),
    );

    _titleController.clear();
    _contentController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('2nd Brain - Capture'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync Pending Memories',
            onPressed: () {
              context.read<CaptureBloc>().add(SyncPendingMemoriesEvent());
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () {
              context.read<AuthBloc>().add(SignOutRequested());
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What is on your mind?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitMemory,
                icon: const Icon(Icons.save),
                label: const Text('Capture Memory'),
              ),
            ),
            const Divider(height: 32),
            Expanded(
              child: BlocConsumer<CaptureBloc, CaptureState>(
                listener: (context, state) {
                  if (state is CaptureFailure) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(state.errorMessage)));
                  }
                },
                builder: (context, state) {
                  if (state is CaptureLoading) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (state is CaptureLoaded) {
                    if (state.memories.isEmpty) {
                      return const Center(
                        child: Text('No memories saved yet.'),
                      );
                    }
                    return ListView.builder(
                      itemCount: state.memories.length,
                      itemBuilder: (context, index) {
                        final memory = state.memories[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4.0, horizontal: 2.0),
                            child: ListTile(
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      memory.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (memory.aiStatus == 'processed')
                                    const Tooltip(
                                      message: 'AI Processed',
                                      child: Icon(
                                        Icons.auto_awesome,
                                        size: 16,
                                        color: Colors.amber,
                                      ),
                                    )
                                  else if (memory.aiStatus == 'pending')
                                    const Tooltip(
                                      message: 'AI Ingestion Pending',
                                      child: SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    memory.content,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (memory.tags.isNotEmpty ||
                                      memory.category != 'General') ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                      children: [
                                        if (memory.category != 'General')
                                          Chip(
                                            label: Text(
                                              memory.category,
                                              style:
                                                  const TextStyle(fontSize: 10),
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                          ),
                                        ...memory.tags.take(3).map(
                                              (tag) => Chip(
                                                label: Text(
                                                  '#$tag',
                                                  style: const TextStyle(
                                                      fontSize: 10),
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                              ),
                                            ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              trailing: Text(
                                '${memory.clientCreatedAt.hour}:${memory.clientCreatedAt.minute.toString().padLeft(2, '0')}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
