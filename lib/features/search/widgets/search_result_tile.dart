import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/core/utils/time_format.dart';
import 'package:claw_hub/ui_kit/emoji_avatar.dart';
import 'package:claw_hub/features/search/models/search_result.dart';

/// Renders a single search result: agent avatar + name + highlighted content + time.
///
/// Keyword highlighting uses case-insensitive matching against [result.highlightQuery]
/// with accent-colored [TextSpan]s.
class SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback? onTap;

  const SearchResultTile({super.key, required this.result, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.s4,
          vertical: XiaSpacing.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmojiAvatar(
              displayName: result.agentName,
              themeColor: result.agentThemeColor,
              radius: 18,
              borderRadius: XiaRadius.sm,
              fontSize: 14,
            ),
            const SizedBox(width: XiaSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Agent name + timestamp row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          result.agentName,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: XiaSpacing.s2),
                      Text(
                        formatRelativeTime(result.messageTimestamp),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Message content with keyword highlighting
                  _buildHighlightedContent(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedContent(ThemeData theme) {
    final content = result.messageContent;
    final query = result.highlightQuery;

    if (query.isEmpty || content.isEmpty) {
      return Text(
        content.isEmpty ? '(无文本内容)' : content,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Case-insensitive keyword highlighting.
    final spans = <TextSpan>[];
    final lowerContent = content.toLowerCase();
    final lowerQuery = query.toLowerCase();

    int start = 0;
    while (start < content.length) {
      final matchIndex = lowerContent.indexOf(lowerQuery, start);
      if (matchIndex == -1) {
        // No more matches — add remaining text.
        spans.add(TextSpan(text: content.substring(start)));
        break;
      }

      // Text before the match.
      if (matchIndex > start) {
        spans.add(TextSpan(text: content.substring(start, matchIndex)));
      }

      // The matched text (highlighted).
      spans.add(
        TextSpan(
          text: content.substring(matchIndex, matchIndex + query.length),
          style: TextStyle(
            backgroundColor: XiaColors.accentMuted,
            color: XiaColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

      start = matchIndex + query.length;
    }

    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
