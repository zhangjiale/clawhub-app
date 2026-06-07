import '../models/enums.dart';

/// 消息预览生成器（纯函数）
/// 对齐: 架构 vFinal 5.2 (消息中心聚合与预览生成引擎)
///
/// 规则:
/// - 用户消息前缀 "你: "
/// - 图片消息: [图片]
/// - 文件消息: [文件]
/// - 工具调用: [工具调用]
/// - 文本消息: 去除 Markdown 标记后截断到 40 字
class GeneratePreview {
  static const int _maxLength = 40;
  static const String _userPrefix = '你: ';

  /// 生成消息预览文本
  String execute({
    required MessageRole role,
    required MessageType type,
    String? content,
  }) {
    if (content == null || content.isEmpty) {
      if (role == MessageRole.user) return _userPrefix;
      return '';
    }

    final prefix = _getPrefix(role);
    final body = _getBody(type, content);

    return '$prefix$body';
  }

  String _getPrefix(MessageRole role) {
    return role == MessageRole.user ? _userPrefix : '';
  }

  String _getBody(MessageType type, String content) {
    switch (type) {
      case MessageType.image:
        return '[图片]';
      case MessageType.file:
        return '[文件]';
      case MessageType.toolCall:
        return '[工具调用]';
      case MessageType.text:
        return _truncate(_stripMarkdown(content));
    }
  }

  // Compiled once — stripMarkdown is called on every preview generation.
  static final _boldRe = RegExp(r'\*\*(.+?)\*\*');
  static final _italicRe = RegExp(r'\*(.+?)\*');
  static final _codeBlockRe = RegExp(r'```[\s\S]*?```');
  static final _inlineCodeRe = RegExp(r'`([^`]+)`');
  static final _linkRe = RegExp(r'\[([^\]]*)\]\([^)]*\)');
  static final _headingRe = RegExp(r'#{1,6}\s+');
  static final _listMarkerRe = RegExp(r'[-*+]\s+');
  static final _newlineRe = RegExp(r'\n+');
  static final _quoteRe = RegExp(r'>\s+');

  /// 去除 Markdown 标记（保留文本内容，移除格式标记）
  String _stripMarkdown(String text) {
    return text
        .replaceAllMapped(_boldRe, (m) => m.group(1)!) // 加粗
        .replaceAllMapped(_italicRe, (m) => m.group(1)!) // 斜体
        .replaceAll(_codeBlockRe, '') // 代码块（多行）移除
        .replaceAllMapped(_inlineCodeRe, (m) => m.group(1)!) // 行内代码：去标记保留内容
        .replaceAllMapped(_linkRe, (m) => m.group(1)!) // 链接
        .replaceAll(_headingRe, '') // 标题
        .replaceAll(_listMarkerRe, '') // 列表标记
        .replaceAll(_newlineRe, ' ') // 换行→空格
        .replaceAll(_quoteRe, '') // 引用
        .trim();
  }

  /// 截断到最大长度
  String _truncate(String text) {
    if (text.length <= _maxLength) return text;
    return text.substring(0, _maxLength);
  }
}
