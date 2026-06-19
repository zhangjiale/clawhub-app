import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// Shared Markdown stylesheet used by both [MessageBubble] and [StreamingBubble].
///
/// Extracted to ui_kit to keep markdown rendering consistent across chat bubbles.
/// When adding or modifying a markdown style, update it here once — both widgets
/// pick up the change automatically.
class XiaMarkdownStyles {
  XiaMarkdownStyles._();

  /// Full-featured stylesheet for rendered message bubbles (headings, links,
  /// code blocks, blockquotes, tables).
  static final MarkdownStyleSheet message = MarkdownStyleSheet(
    p: const TextStyle(color: XiaColors.text1, fontSize: 15, height: 1.6),
    h1: const TextStyle(
      color: XiaColors.text1,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
    h2: const TextStyle(
      color: XiaColors.text1,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
    h3: const TextStyle(
      color: XiaColors.text1,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
    strong: const TextStyle(
      color: XiaColors.text1,
      fontWeight: FontWeight.bold,
    ),
    em: const TextStyle(color: XiaColors.text1, fontStyle: FontStyle.italic),
    a: const TextStyle(
      color: XiaColors.accent,
      decoration: TextDecoration.underline,
    ),
    code: const TextStyle(
      backgroundColor: XiaColors.codeBlockBg,
      color: XiaColors.accent,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    codeblockDecoration: BoxDecoration(
      color: XiaColors.surface2,
      borderRadius: BorderRadius.circular(XiaRadius.md),
    ),
    codeblockPadding: const EdgeInsets.all(XiaSpacing.s4),
    blockquoteDecoration: const BoxDecoration(
      border: Border(left: BorderSide(color: XiaColors.accent, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.only(left: XiaSpacing.s3),
    tableBorder: TableBorder.all(color: XiaColors.divider),
    tableHead: const TextStyle(
      color: XiaColors.text1,
      fontWeight: FontWeight.bold,
    ),
    tableBody: const TextStyle(color: XiaColors.text1),
    listBullet: const TextStyle(color: XiaColors.text1),
  );

  /// Lightweight stylesheet for streaming text (p, code, strong only).
  /// The streaming bubble renders incrementally and doesn't need full
  /// block-level formatting.
  static final MarkdownStyleSheet streaming = MarkdownStyleSheet(
    p: const TextStyle(color: XiaColors.text1, fontSize: 15, height: 1.6),
    code: const TextStyle(
      backgroundColor: XiaColors.codeBlockBg,
      color: XiaColors.accent,
      fontSize: 13,
      fontFamily: 'monospace',
    ),
    strong: const TextStyle(fontWeight: FontWeight.bold),
  );
}
