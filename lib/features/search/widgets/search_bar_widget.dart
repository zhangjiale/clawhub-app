import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Search input bar with auto-focus, clear button, and 300ms debounce.
///
/// Calls [onChanged] on every keystroke — debouncing is handled by
/// [SearchViewModel.onQueryChanged], not by this widget.
class SearchBarWidget extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  const SearchBarWidget({super.key, required this.onChanged, this.focusNode});

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _controller.addListener(() {
      // Rebuild to show/hide the clear button based on text content.
      if (mounted) setState(() {});
    });
    // Auto-focus on mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        XiaSpacing.s4,
        XiaSpacing.s2,
        XiaSpacing.s4,
        XiaSpacing.s2,
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: '搜索所有消息记录...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                )
              : null,
        ),
      ),
    );
  }
}
