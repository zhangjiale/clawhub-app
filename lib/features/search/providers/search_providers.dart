import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/features/search/viewmodels/search_view_model.dart';

/// Provider for the global message search ViewModel.
///
/// Constructs [SearchViewModel] with all required repositories,
/// registers dispose cleanup, and exposes [SearchState] reactively.
final searchViewModelProvider =
    StateNotifierProvider<SearchViewModel, SearchState>((ref) {
      final vm = SearchViewModel(
        messageRepo: ref.watch(messageRepoProvider),
        agentRepo: ref.watch(agentRepoProvider),
        conversationRepo: ref.watch(conversationRepoProvider),
      );
      ref.onDispose(() => vm.dispose());
      return vm;
    });
