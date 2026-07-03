import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Realtime Canvas Drawing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DrawingScreen(),
    );
  }
}

class DrawingScreen extends StatefulWidget {
  const DrawingScreen({
    super.key,
    this.controller,
    this.enableRemoteSimulation = true,
  });

  final DrawingController? controller;
  final bool enableRemoteSimulation;

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  late final DrawingController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DrawingController();
    _ownsController = widget.controller == null;
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime Canvas Drawing'),
        actions: [
          IconButton(
            tooltip: 'Clear canvas',
            onPressed: _controller.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: DrawingCanvas(
          controller: _controller,
          enableRemoteSimulation: widget.enableRemoteSimulation,
        ),
      ),
    );
  }
}

class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    super.key,
    required this.controller,
    required this.enableRemoteSimulation,
  });

  final DrawingController controller;
  final bool enableRemoteSimulation;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  StreamSubscription<RemoteStrokeEvent>? _remoteSubscription;
  Size? _simulatedCanvasSize;

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    super.dispose();
  }

  void _syncRemoteSimulation(Size canvasSize) {
    if (!widget.enableRemoteSimulation) {
      _remoteSubscription?.cancel();
      _remoteSubscription = null;
      _simulatedCanvasSize = null;
      return;
    }

    if (_simulatedCanvasSize == canvasSize && _remoteSubscription != null) {
      return;
    }

    _remoteSubscription?.cancel();
    _simulatedCanvasSize = canvasSize;
    _remoteSubscription = VirtualRemoteStrokeStream(
      canvasSize,
    ).listen(widget.controller.applyRemoteEvent);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
          _syncRemoteSimulation(canvasSize);

          return Listener(
            key: const ValueKey('drawing-canvas'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              widget.controller.beginStroke(event.localPosition);
            },
            onPointerMove: (event) {
              widget.controller.appendPoint(event.localPosition);
            },
            onPointerUp: (_) => widget.controller.endStroke(),
            onPointerCancel: (_) => widget.controller.endStroke(),
            child: CustomPaint(
              key: const ValueKey('drawing-paint'),
              foregroundPainter: DrawingPainter(widget.controller),
              isComplex: true,
              willChange: true,
              child: const _CanvasChrome(),
            ),
          );
        },
      ),
    );
  }
}

class _CanvasChrome extends StatelessWidget {
  const _CanvasChrome();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GridPainter(colorScheme.outlineVariant),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.8,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'Drag to draw in blue. Simulated remote users stream in orange on the same canvas.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DrawingController extends ChangeNotifier {
  final List<Stroke> _strokes = <Stroke>[];
  Stroke? _activeStroke;
  final Map<String, Stroke> _activeRemoteStrokes = <String, Stroke>{};

  List<Stroke> get strokes => List<Stroke>.unmodifiable(_strokes);
  Stroke? get activeStroke => _activeStroke;
  List<Stroke> get visibleStrokes => List<Stroke>.unmodifiable(<Stroke>[
    ..._strokes,
    ?_activeStroke,
    ..._activeRemoteStrokes.values,
  ]);

  void beginStroke(Offset point) {
    _activeStroke = Stroke(
      userId: 'local-user',
      source: StrokeSource.local,
      points: <Offset>[point],
      color: const Color(0xFF1E40AF),
    );
    notifyListeners();
  }

  void appendPoint(Offset point) {
    final stroke = _activeStroke;
    if (stroke == null) {
      return;
    }

    final lastPoint = stroke.points.last;
    if ((point - lastPoint).distance < 0.5) {
      return;
    }

    stroke.points.add(point);
    notifyListeners();
  }

  void endStroke() {
    final stroke = _activeStroke;
    if (stroke == null) {
      return;
    }

    if (stroke.points.isNotEmpty) {
      _strokes.add(stroke);
    }
    _activeStroke = null;
    notifyListeners();
  }

  void applyRemoteEvent(RemoteStrokeEvent event) {
    switch (event.phase) {
      case StrokePhase.start:
        _activeRemoteStrokes[event.strokeId] = Stroke(
          userId: event.userId,
          source: StrokeSource.remote,
          points: <Offset>[event.point],
          color: event.color,
          width: 4,
        );
      case StrokePhase.update:
        final stroke = _activeRemoteStrokes[event.strokeId];
        if (stroke == null) {
          return;
        }
        final lastPoint = stroke.points.last;
        if ((event.point - lastPoint).distance < 0.5) {
          return;
        }
        stroke.points.add(event.point);
      case StrokePhase.end:
        final stroke = _activeRemoteStrokes.remove(event.strokeId);
        if (stroke == null) {
          return;
        }
        stroke.points.add(event.point);
        _strokes.add(stroke);
    }

    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty &&
        _activeStroke == null &&
        _activeRemoteStrokes.isEmpty) {
      return;
    }

    _strokes.clear();
    _activeStroke = null;
    _activeRemoteStrokes.clear();
    notifyListeners();
  }
}

class Stroke {
  Stroke({
    required this.userId,
    required this.source,
    required this.points,
    this.color = const Color(0xFF1E40AF),
    this.width = 5,
  });

  final String userId;
  final StrokeSource source;
  final List<Offset> points;
  final Color color;
  final double width;
}

enum StrokeSource { local, remote }

enum StrokePhase { start, update, end }

class RemoteStrokeEvent {
  const RemoteStrokeEvent({
    required this.strokeId,
    required this.userId,
    required this.phase,
    required this.point,
    required this.color,
  });

  final String strokeId;
  final String userId;
  final StrokePhase phase;
  final Offset point;
  final Color color;
}

class VirtualRemoteStrokeStream extends Stream<RemoteStrokeEvent> {
  VirtualRemoteStrokeStream(this.canvasSize);

  final Size canvasSize;

  @override
  StreamSubscription<RemoteStrokeEvent> listen(
    void Function(RemoteStrokeEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controller = StreamController<RemoteStrokeEvent>();
    final simulator = _RemoteStrokeSimulator(canvasSize, controller);
    simulator.start();

    controller.onCancel = simulator.dispose;

    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _RemoteStrokeSimulator {
  _RemoteStrokeSimulator(this.canvasSize, this.controller);

  final Size canvasSize;
  final StreamController<RemoteStrokeEvent> controller;
  Timer? _timer;
  int _sampleIndex = 0;
  int _strokeIndex = 0;
  String _strokeId = 'remote-stroke-0';

  static const _samplesPerStroke = 72;
  static const _remoteUserId = 'remote-user-1';
  static const _remoteColor = Color(0xFFEA580C);

  void start() {
    _emit(StrokePhase.start);
    _timer = Timer.periodic(const Duration(milliseconds: 24), (_) {
      _sampleIndex++;
      final isStrokeEnd = _sampleIndex >= _samplesPerStroke;
      _emit(isStrokeEnd ? StrokePhase.end : StrokePhase.update);

      if (isStrokeEnd) {
        _sampleIndex = 0;
        _strokeIndex++;
        _strokeId = 'remote-stroke-$_strokeIndex';
        _emit(StrokePhase.start);
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _emit(StrokePhase phase) {
    if (controller.isClosed) {
      return;
    }

    controller.add(
      RemoteStrokeEvent(
        strokeId: _strokeId,
        userId: _remoteUserId,
        phase: phase,
        point: _pointFor(_sampleIndex, _strokeIndex),
        color: _remoteColor,
      ),
    );
  }

  Offset _pointFor(int sampleIndex, int strokeIndex) {
    final progress = sampleIndex / _samplesPerStroke;
    final insetX = math.min(48.0, canvasSize.width * 0.16);
    final insetY = math.min(96.0, canvasSize.height * 0.18);
    final usableWidth = math.max(1.0, canvasSize.width - insetX * 2);
    final usableHeight = math.max(1.0, canvasSize.height - insetY * 2);
    final wave = math.sin((progress * math.pi * 2) + strokeIndex);

    return Offset(
      insetX + usableWidth * progress,
      insetY + usableHeight * (0.35 + wave * 0.18 + (strokeIndex % 3) * 0.12),
    );
  }
}

class DrawingPainter extends CustomPainter {
  DrawingPainter(this.controller) : super(repaint: controller);

  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in controller.visibleStrokes) {
      _paintStroke(canvas, stroke);
    }
  }

  void _paintStroke(Canvas canvas, Stroke stroke) {
    final points = stroke.points;
    if (points.isEmpty) {
      return;
    }

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      canvas.drawCircle(points.first, stroke.width / 2, paint);
      return;
    }

    for (var i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    return oldDelegate.controller != controller;
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..strokeWidth = 1;

    const gap = 24.0;
    for (var x = 0.0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
