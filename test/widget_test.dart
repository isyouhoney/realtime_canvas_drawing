import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:realtime_canvas_drawing/main.dart';

void main() {
  testWidgets('drawing screen renders isolated canvas', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: DrawingScreen(enableRemoteSimulation: false)),
    );

    expect(find.text('Realtime Canvas Drawing'), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsWidgets);
    expect(find.byKey(const ValueKey('drawing-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawing-paint')), findsOneWidget);
  });

  testWidgets('dragging on canvas records a stroke', (tester) async {
    final controller = DrawingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(
          controller: controller,
          enableRemoteSimulation: false,
        ),
      ),
    );

    await tester.dragFrom(const Offset(120, 180), const Offset(160, 120));
    await tester.pump();

    expect(controller.strokes, hasLength(1));
    expect(controller.strokes.single.points.length, greaterThan(1));

    await tester.tap(find.byTooltip('Clear canvas'));
    await tester.pump();

    expect(controller.strokes, isEmpty);
  });

  testWidgets('remote stroke syncs while local stroke is active', (
    tester,
  ) async {
    final controller = DrawingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DrawingScreen(
          controller: controller,
          enableRemoteSimulation: false,
        ),
      ),
    );

    controller.beginStroke(const Offset(20, 20));
    controller.appendPoint(const Offset(40, 40));
    controller.applyRemoteEvent(
      const RemoteStrokeEvent(
        strokeId: 'remote-1',
        userId: 'remote-user',
        phase: StrokePhase.start,
        point: Offset(80, 80),
        color: Colors.deepOrange,
      ),
    );
    controller.applyRemoteEvent(
      const RemoteStrokeEvent(
        strokeId: 'remote-1',
        userId: 'remote-user',
        phase: StrokePhase.update,
        point: Offset(120, 100),
        color: Colors.deepOrange,
      ),
    );
    await tester.pump();

    expect(controller.visibleStrokes, hasLength(2));
    expect(
      controller.visibleStrokes.map((stroke) => stroke.source),
      containsAll(<StrokeSource>[StrokeSource.local, StrokeSource.remote]),
    );

    controller.endStroke();
    controller.applyRemoteEvent(
      const RemoteStrokeEvent(
        strokeId: 'remote-1',
        userId: 'remote-user',
        phase: StrokePhase.end,
        point: Offset(140, 120),
        color: Colors.deepOrange,
      ),
    );

    expect(controller.strokes, hasLength(2));
  });
}
