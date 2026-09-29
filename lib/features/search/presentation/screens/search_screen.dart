import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../capture/presentation/screens/memory_detail_screen.dart';
import '../../data/datasources/search_local_data_source.dart';
import '../../data/datasources/search_remote_data_source.dart';
import '../../data/repositories/search_repository_impl.dart';
import '../../domain/entities/search_result_item.dart';
import '../../domain/usecases/search_memories_usecase.dart';
import '../bloc/search_bloc.dart';
import '../bloc/search_event.dart';
import '../bloc/search_state.dart';

class SearchScreen extends StatefulWidget {
  final SearchBloc? searchBloc;
  final bool? showBackButton;
  final bool autofocus;
  final bool isActive;

  const SearchScreen({
    super.key,
    this.searchBloc,
    this.showBackButton,
    this.autofocus = true,
    this.isActive = true,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final SearchBloc _bloc;
  late final bool _ownsBloc;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void didUpdateWidget(SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When leaving or re-entering the Search screen as a fresh session, reset query and results
    if (oldWidget.isActive != widget.isActive) {
      if (!widget.isActive) {
        _clearSearch();
      } else if (_searchController.text.isNotEmpty ||
          _bloc.state is! SearchInitial) {
        _clearSearch();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.searchBloc != null) {
      _bloc = widget.searchBloc!;
      _ownsBloc = false;
    } else {
      final remoteDataSource = SearchRemoteDataSourceImpl();
      final localDataSource = SearchLocalDataSourceImpl();
      final repository = SearchRepositoryImpl(
        remoteDataSource: remoteDataSource,
        localDataSource: localDataSource,
      );
      final useCase = SearchMemoriesUseCase(repository);
      _bloc = SearchBloc(searchMemoriesUseCase: useCase);
      _ownsBloc = true;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    if (_ownsBloc) {
      _bloc.close();
    }
    super.dispose();
  }

  void _onQueryChanged(String query) {
    setState(() {}); // Updates clear button visibility
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _bloc.add(SearchQueryChanged(query));
      }
    });
  }

  void _onQuerySubmitted(String query) {
    _debounceTimer?.cancel();
    _bloc.add(SearchQueryChanged(query));
  }

  void _clearSearch() {
    _searchController.clear();
    _debounceTimer?.cancel();
    setState(() {});
    _bloc.add(ClearSearchRequested());
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(dateTime);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'work':
        return Icons.work_outline_rounded;
      case 'personal':
        return Icons.favorite_outline_rounded;
      case 'study':
        return Icons.school_outlined;
      case 'travel':
        return Icons.flight_takeoff_rounded;
      case 'food':
        return Icons.restaurant_outlined;
      case 'fashion':
        return Icons.checkroom_outlined;
      case 'finance':
        return Icons.account_balance_wallet_outlined;
      case 'health & fitness':
      case 'health':
        return Icons.fitness_center_rounded;
      default:
        return Icons.lightbulb_outline_rounded;
    }
  }

  Widget _buildThumbnail(SearchResultItem item) {
    if (item.mediaUrl != null && item.mediaUrl!.isNotEmpty) {
      final url = item.mediaUrl!;
      final isAudio =
          url.endsWith('.m4a') ||
          url.endsWith('.aac') ||
          url.endsWith('.mp3') ||
          url.endsWith('.wav');
      if (isAudio) {
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.lightCyanTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Icon(Icons.mic_rounded, color: AppColors.primary, size: 22),
          ),
        );
      }
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return Image.network(
          url,
          fit: BoxFit.cover,
          width: 46,
          height: 46,
          errorBuilder: (_, __, ___) =>
              _buildCategoryFallbackIcon(item.category),
        );
      } else {
        final localFile = File(url);
        if (localFile.existsSync()) {
          return Image.file(
            localFile,
            fit: BoxFit.cover,
            width: 46,
            height: 46,
            errorBuilder: (_, __, ___) =>
                _buildCategoryFallbackIcon(item.category),
          );
        }
      }
    }
    return _buildCategoryFallbackIcon(item.category);
  }

  Widget _buildCategoryFallbackIcon(String category) {
    return Center(
      child: Icon(
        _getCategoryIcon(category),
        color: AppColors.primary,
        size: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = widget.showBackButton ?? Navigator.of(context).canPop();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        backgroundColor: AppColors.backgroundOf(context),
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          toolbarHeight: 76,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          automaticallyImplyLeading: false,
          leading: canGoBack
              ? IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          actions: canGoBack ? const [SizedBox(width: 56)] : null,
          centerTitle: true,
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 36,
              padding: const EdgeInsets.only(left: 16, right: 8),
              decoration: BoxDecoration(
                color: AppColors.cardBackgroundOf(context),
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: AppColors.textSecondaryOf(context),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: widget.autofocus,
                      onChanged: _onQueryChanged,
                      onSubmitted: _onQuerySubmitted,
                      textInputAction: TextInputAction.search,
                      textAlignVertical: TextAlignVertical.center,
                      style: TextStyle(
                        color: AppColors.textPrimaryOf(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        fillColor: Colors.transparent,
                        hintText: AppStrings.homeSearchHint,
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondaryOf(
                            context,
                          ).withValues(alpha: 0.85),
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      splashRadius: 18,
                      onPressed: _clearSearch,
                    ),
                ],
              ),
            ),
          ),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: AppColors.headerGradientOf(context),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? AppColors.darkPrimary : AppColors.primary)
                      .withValues(alpha: 0.20),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
        ),
        body: BlocBuilder<SearchBloc, SearchState>(
          builder: (context, state) {
            if (state is SearchLoading) {
              return _buildLoadingState(state.query);
            } else if (state is SearchLoaded) {
              return _buildLoadedState(state);
            } else if (state is SearchEmpty) {
              return _buildEmptyState(state);
            } else if (state is SearchError) {
              return _buildErrorState(state);
            }
            return _buildInitialState();
          },
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 110, 24, 24),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.lightCyanTint,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 38,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Semantic Search',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search by meaning, feeling, or concept —\nnot just exact keywords.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(String query) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Searching memories for "$query"...',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedState(SearchLoaded state) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
      children: [
        if (state.isOffline) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9E6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE599)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 18,
                  color: Color(0xFFB45309),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Offline Mode • Showing local keyword matches',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              state.results.length == 1
                  ? '1 memory found'
                  : '${state.results.length} memories found',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            if (!state.isOffline)
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 13,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Ranked by AI meaning',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        ...state.results.map((result) => _buildResultCard(result)),
      ],
    );
  }

  Widget _buildResultCard(SearchResultItem item) {
    final similarityPercentage = (item.similarity * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.subtleBorderOf(context),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MemoryDetailScreen(
                    memoryId: item.id,
                    initialMemory: item.toMemoryEntity(),
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Thumbnail or Icon
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceTintOf(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildThumbnail(item),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Title & Subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title.isEmpty
                                  ? 'Untitled Memory'
                                  : item.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimaryOf(context),
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.clientCreatedAt != null
                                  ? '${item.category} • ${_formatTimeAgo(item.clientCreatedAt!)}'
                                  : item.category,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Match score badge
                      if (!item.isOfflineResult && item.similarity > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceTintOf(context),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 10,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '$similarityPercentage%',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (item.isOfflineResult)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.toggleBackgroundOf(context),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Keyword',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (item.content.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _cleanContentSnippet(item.content),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondaryOf(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: item.tags.take(3).map((tag) {
                        final cleanTag = tag.startsWith('#')
                            ? tag.substring(1)
                            : tag;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.toggleBackgroundOf(context),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.borderOf(context),
                            ),
                          ),
                          child: Text(
                            '#$cleanTag',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _cleanContentSnippet(String content) {
    var text = content.trim();
    if ((text.startsWith('http://') || text.startsWith('https://')) &&
        text.contains('\n')) {
      final after = text.substring(text.indexOf('\n')).trim();
      if (after.isNotEmpty) {
        text = after;
      }
    }
    return text;
  }

  Widget _buildEmptyState(SearchEmpty state) {
    return Center(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 34,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No memories found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We couldn\'t find any memories matching "${state.query}".\nTry searching with different concepts, topics, or words.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(SearchError state) {
    return Center(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 16),
            const Text(
              'Search Failed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              state.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _bloc.add(RetrySearchRequested()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
