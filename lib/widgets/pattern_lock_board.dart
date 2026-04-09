// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Secret Chat Contributors

import 'dart:math';

import 'package:flutter/material.dart';

class PatternLockBoard extends StatefulWidget {
  const PatternLockBoard({
    super.key,
    required this.onCompleted,
    this.size = 280,
  });

  final ValueChanged<String> onCompleted;
  final double size;

  @override
  State<PatternLockBoard> createState() => _PatternLockBoardState();
}

class _PatternLockBoardState extends State<PatternLockBoard> {
  static const int _gridSize = 3;
  static const double _dotRadius = 12;
  static const double _hitDistance = 26;

  final List<int> _selected = <int>[];
  Offset? _dragPoint;

  List<Offset> _dotCenters(double size) {
    const double padding = 30;
    final double spacing = (size - (padding * 2)) / (_gridSize - 1);

    final List<Offset> points = <Offset>[];
    for (int row = 0; row < _gridSize; row++) {
      for (int col = 0; col < _gridSize; col++) {
        points.add(Offset(padding + col * spacing, padding + row * spacing));
      }
    }
    return points;
  }

  int? _nearestDot(Offset local, List<Offset> points) {
    for (int i = 0; i < points.length; i++) {
      if ((points[i] - local).distance <= _hitDistance) {
        return i;
      }
    }
    return null;
  }

  void _handlePoint(Offset local, List<Offset> points) {
    final int? dot = _nearestDot(local, points);
    if (dot == null || _selected.contains(dot)) {
      return;
    }

    setState(() {
      _selected.add(dot);
    });
  }

  void _completePattern() {
    if (_selected.length < 4) {
      setState(() {
        _selected.clear();
        _dragPoint = null;
      });
      return;
    }

    final String pattern = _selected.join('-');
    widget.onCompleted(pattern);

    setState(() {
      _selected.clear();
      _dragPoint = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double size = min(constraints.maxWidth, constraints.maxHeight);
          final List<Offset> points = _dotCenters(size);

          return GestureDetector(
            onPanStart: (DragStartDetails details) {
              setState(() {
                _selected.clear();
                _dragPoint = details.localPosition;
              });
              _handlePoint(details.localPosition, points);
            },
            onPanUpdate: (DragUpdateDetails details) {
              setState(() {
                _dragPoint = details.localPosition;
              });
              _handlePoint(details.localPosition, points);
            },
            onPanEnd: (_) {
              _completePattern();
            },
            child: CustomPaint(
              painter: _PatternPainter(
                points: points,
                selected: _selected,
                dragPoint: _dragPoint,
                dotRadius: _dotRadius,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.points,
    required this.selected,
    required this.dragPoint,
    required this.dotRadius,
  });

  final List<Offset> points;
  final List<int> selected;
  final Offset? dragPoint;
  final double dotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = Colors.tealAccent.shade700
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint dotPaint = Paint()
      ..color = Colors.tealAccent.shade700
      ..style = PaintingStyle.fill;

    final Paint dotOutlinePaint = Paint()
      ..color = Colors.teal.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < selected.length - 1; i++) {
      canvas.drawLine(points[selected[i]], points[selected[i + 1]], linePaint);
    }

    if (selected.isNotEmpty && dragPoint != null) {
      canvas.drawLine(points[selected.last], dragPoint!, linePaint);
    }

    for (int i = 0; i < points.length; i++) {
      final bool isSelected = selected.contains(i);
      if (isSelected) {
        canvas.drawCircle(points[i], dotRadius, dotPaint);
      } else {
        canvas.drawCircle(points[i], dotRadius, dotOutlinePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return oldDelegate.selected != selected ||
        oldDelegate.dragPoint != dragPoint;
  }
}
