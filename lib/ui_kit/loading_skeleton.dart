import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

/// 加载骨架屏组件
/// 对齐: 架构 vFinal 8.2 (ui_kit/empty_states/)
///
/// 在数据加载中展示占位卡片，提供视觉反馈。
class LoadingSkeleton extends StatelessWidget {
  final int count;

  const LoadingSkeleton({super.key, this.count = 1});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    return ListView.builder(
      itemCount: count,
      padding: const EdgeInsets.all(XiaSpacing.s4),
      itemBuilder: (context, index) {
        return const Padding(
          padding: EdgeInsets.only(bottom: XiaSpacing.s3),
          child: _SkeletonCard(),
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(XiaSpacing.s4),
        child: Row(
          children: [
            // Avatar placeholder
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: XiaSpacing.s3),
            // Text placeholders
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 120,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: XiaSpacing.s2),
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
