import 'dart:math' as math;

import 'package:flutter/material.dart';

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    required this.minItemWidth,
    this.gap = 14,
    this.collapseEmpty = true,
    this.equalHeight = true,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double gap;
  final bool collapseEmpty;
  final bool equalHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        var columns = math.max(1, ((box.maxWidth + gap) / (minItemWidth + gap)).floor());
        if (collapseEmpty) columns = math.min(columns, math.max(1, children.length));

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += columns) {
          final slice = children.skip(i).take(columns).toList();
          final row = Row(
            crossAxisAlignment:
                equalHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) SizedBox(width: gap),
                Expanded(child: j < slice.length ? slice[j] : const SizedBox.shrink()),
              ],
            ],
          );
          rows.add(Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: equalHeight ? IntrinsicHeight(child: row) : row,
          ));
        }
        return Column(children: rows);
      },
    );
  }
}
