import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:claw_hub/app/theme/agent_theme.dart';
import 'package:claw_hub/domain/models/message.dart';
import 'package:claw_hub/domain/models/message_status.dart';
import 'package:claw_hub/domain/models/enums.dart';
import 'package:claw_hub/ui_kit/status_icon.dart';
import 'package:claw_hub/ui_kit/press_feedback_buttons.dart';
import 'package:claw_hub/app/theme/tokens.dart';
import 'package:claw_hub/ui_kit/xia_markdown_styles.dart';
import 'message_image_content.dart';
import 'message_file_content.dart';

/// Message bubble — matching V2 ComponentSpec Section 4.2.2.
///
/// 渲染优先级（按 [message.role] 分支):
/// - [MessageRole.user] (真实文本输入): sapphire 右气泡，白字，14px 圆角带右下角 tail
/// - [MessageRole.agent]: surface2 左气泡，text1，14px 圆角带左下角 tail + hairline border
/// - [MessageRole.userPlaceholder]: OpenClaw 上传占位 → 居中折叠小条（📎 1 个文件已上传）
/// - [MessageRole.toolResult]: 工具调用输出 → 居中折叠卡（⌨ exec · 0.02s）
/// - [MessageRole.system]: 居中淡灰斜体小条(系统通知,内容可见不丢)
///
/// **Animation (B3)**: 250ms opacity(0→1) + translateY(10px→0) enter
/// animation via [StaggeredEnterItem] based on [index].
class MessageBubble extends StatelessWidget {
  final Message message;
  final String agentName;
  final int index; // B3: for staggered enter delay
  final VoidCallback? onRetry; // US-015 AC2: retry FAILED messages
  final bool isHighlighted; // search-result highlight

  const MessageBubble({
    super.key,
    required this.message,
    required this.agentName,
    this.index = 0,
    this.onRetry,
    this.isHighlighted = false,
  });

  bool get _isUser => message.role == MessageRole.user;
  bool get _isUserPlaceholder => message.role == MessageRole.userPlaceholder;
  bool get _isToolResult => message.role == MessageRole.toolResult;
  bool get _isSystem => message.role == MessageRole.system;

  /// 失败消息且 [onRetry] 可用时，渲染可点击的"状态图标 + 重试"组合；
  /// 否则渲染普通 [StatusIcon]。
  Widget _buildStatusIndicator() {
    if (message.status != MessageStatus.failed || onRetry == null) {
      return StatusIcon(status: message.status, size: 14);
    }
    return Tooltip(
      message: '重试发送',
      child: GestureDetector(
        onTap: onRetry,
        behavior: HitTestBehavior.opaque, // larger hit area
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusIcon(status: message.status, size: 14),
              const SizedBox(width: 2),
              const Icon(Icons.refresh, size: 12, color: XiaColors.red),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 非气泡类消息(userPlaceholder / toolResult / system)走各自折叠渲染,
    // 不占 user/agent 气泡。system 不再凭空消失(原 SizedBox.shrink 会静默
    // 丢消息,且未知 role 也兜到 system)——渲染成居中淡灰小条,内容可见。
    if (_isUserPlaceholder) return _buildPlaceholder(context);
    if (_isToolResult) return _buildToolResult(context);
    if (_isSystem) return _buildSystemNotice(context);

    return StaggeredEnterItem(
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: XiaSpacing.pagePaddingH,
          vertical: 4,
        ),
        child: Row(
          mainAxisAlignment: _isUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: _isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: _isUser
                          ? AgentTheme.of(context).primary
                          : isHighlighted
                          ? XiaColors.accent.withAlpha(38)
                          : XiaColors.surface2,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(XiaRadius.xl),
                        topRight: const Radius.circular(XiaRadius.xl),
                        bottomLeft: Radius.circular(
                          _isUser ? XiaRadius.xl : XiaRadius.xs,
                        ),
                        bottomRight: Radius.circular(
                          _isUser ? XiaRadius.xs : XiaRadius.xl,
                        ),
                      ),
                      // V2: removed boxShadow (replaced by hairline border).
                      // 高亮边框优先于失败边框 —— 搜索结果高亮是用户主动导航的目标，
                      // 即使消息发送失败，用户仍需看到"这就是你搜的那条"的视觉反馈。
                      border: isHighlighted
                          ? Border.all(color: XiaColors.accent, width: 2)
                          : message.status == MessageStatus.failed
                          ? Border.all(color: XiaColors.red, width: 1)
                          : _isUser
                          ? null
                          : Border.all(color: XiaColors.border),
                    ),
                    child: _buildContent(message),
                  ),
                  // Message time
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 3,
                      left: XiaSpacing.s1,
                      right: XiaSpacing.s1,
                    ),
                    child: Text(
                      _formatTime(message.timestamp),
                      style: const TextStyle(
                        fontSize: XiaTypography.timestamp, // V2: 10
                        color: XiaColors.text4,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isUser) ...[const SizedBox(width: 4), _buildStatusIndicator()],
          ],
        ),
      ),
    );
  }

  /// 用户上传文件占位（role=userPlaceholder,占位文本固定为 OpenClaw
  /// 拼接的「[User sent media without caption]」）— 折叠为居中淡灰小条，
  /// 不占用户气泡。metadata.mediaPaths 中携带具体文件清单，按份数染上
  /// 「📎 N 个文件已上传」之类的提示文案。
  Widget _buildPlaceholder(BuildContext context) {
    final rawPaths = message.metadata?['mediaPaths'];
    final fileCount = (rawPaths is List) ? rawPaths.length : 1;
    final label = fileCount > 1 ? '📎 $fileCount 个文件已上传' : '📎 文件已上传';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.pagePaddingH,
        vertical: 6,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: XiaSpacing.s3,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: XiaColors.surface2,
            borderRadius: BorderRadius.circular(XiaRadius.lg),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: XiaColors.text3),
          ),
        ),
      ),
    );
  }

  /// 工具调用输出（role=toolResult,例如 atlas 跑 `ls / wc` 后的多行输出）
  /// — 折叠为居中淡紫边的折叠卡。用户可点开查看完整输出。
  Widget _buildToolResult(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.pagePaddingH,
        vertical: 4,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.86,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: XiaColors.surface,
              borderRadius: BorderRadius.circular(XiaRadius.md),
              border: const Border(
                left: BorderSide(color: XiaColors.accent2, width: 2),
              ),
            ),
            child: Material(
              // ListTile 的 ink 画在最近 Material 祖先上;Container 的 bg color
              // (DecoratedBox)夹在中间会触发"ListTile background color may be
              // invisible" debug 断言。包一层透明 Material 让 ListTile 在装饰盒
              // 内找到 Material 祖先(Theme 已禁 splash,透明即可)。
              type: MaterialType.transparency,
              child: Theme(
                // 去掉 ExpansionTile 默认的点击水波 + 惨怏高亮，保持低调。
                data: Theme.of(context).copyWith(
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: XiaSpacing.s4,
                    vertical: 0,
                  ),
                  childrenPadding: const EdgeInsets.only(
                    left: XiaSpacing.s4,
                    right: XiaSpacing.s4,
                    bottom: XiaSpacing.s3,
                  ),
                  leading: const Icon(
                    Icons.terminal,
                    size: 16,
                    color: XiaColors.accent2,
                  ),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.metadata?['toolName']?.toString() ?? 'tool',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: XiaColors.accent2,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTime(message.timestamp),
                        style: const TextStyle(
                          fontSize: 11,
                          color: XiaColors.text4,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(XiaSpacing.s2),
                      decoration: BoxDecoration(
                        color: XiaColors.bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        message.content ?? '',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: XiaColors.text1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// system 消息(含未知 role 兜底过来的)——渲染成居中淡灰斜体小条,内容可见。
  /// 原实现返回 SizedBox.shrink 会让消息凭空消失(chat_room 无上游 banner 兜它,
  /// 且 commit 1 后未知 role 也归到 system)。空内容的 system 仍返回空 widget。
  Widget _buildSystemNotice(BuildContext context) {
    final text = message.content ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XiaSpacing.pagePaddingH,
        vertical: 4,
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: XiaColors.text3,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  static String _displayContent(Message message) {
    if (message.content != null && message.content!.isNotEmpty) {
      return message.content!;
    }
    return switch (message.type) {
      MessageType.image => '[图片]',
      MessageType.file => '[文件]',
      MessageType.toolCall => '[工具调用]',
      MessageType.text => '',
    };
  }

  /// 按消息类型分派渲染:image/file 走专用 widget,text/toolCall 走原有文本/Markdown。
  Widget _buildContent(Message message) {
    switch (message.type) {
      case MessageType.image:
        return MessageImageContent(message: message, isUser: _isUser);
      case MessageType.file:
        return MessageFileContent(message: message, isUser: _isUser);
      case MessageType.text:
      case MessageType.toolCall:
        final text = _displayContent(message);
        if (_isUser) {
          return Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
            ),
          );
        }
        return _buildMarkdownContent(text);
    }
  }

  static String _formatTime(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static Widget _buildMarkdownContent(String data) {
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: XiaMarkdownStyles.message,
    );
  }
}
