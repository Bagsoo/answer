import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import '../../l10n/app_localizations.dart';

class DrawingStroke {
  final Color color;
  final double size;
  final List<List<int>> points; // [x, y, p] compressed (ratio * 10000)

  DrawingStroke({
    required this.color,
    required this.size,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        'c': color.value,
        's': size,
        'p': points,
      };

  factory DrawingStroke.fromJson(Map<String, dynamic> json) => DrawingStroke(
        color: Color(json['c'] as int),
        size: (json['s'] as num).toDouble(),
        points: (json['p'] as List).map((e) => List<int>.from(e as List)).toList(),
      );
}

class HandwritingCanvasSheet extends StatefulWidget {
  final String? initialVectorJson;

  const HandwritingCanvasSheet({super.key, this.initialVectorJson});

  @override
  State<HandwritingCanvasSheet> createState() => _HandwritingCanvasSheetState();
}

class _HandwritingCanvasSheetState extends State<HandwritingCanvasSheet> {
  final GlobalKey _canvasKey = GlobalKey();
  
  List<DrawingStroke> _strokes = [];
  List<DrawingStroke> _redoStack = [];
  DrawingStroke? _currentStroke;

  Color _selectedColor = Colors.black;
  double _selectedSize = 3.0;
  bool _isEraser = false;

  final List<Color> _colors = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.white, // Eraser if background is transparent/white, wait, true eraser is better
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialVectorJson != null && widget.initialVectorJson!.isNotEmpty) {
      try {
        final list = jsonDecode(widget.initialVectorJson!) as List;
        _strokes = list.map((e) => DrawingStroke.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        debugPrint('Failed to parse initial vector json: $e');
      }
    }
  }

  // --- Input Handling ---
  void _onPointerDown(PointerEvent details, Size size) {
    if (_isEraser) {
      // Very simple bounding box eraser check later, or just draw with background color for simplicity
      // In perfect_freehand real erasing is complex, so let's use white color as an eraser
    }
    
    final colorToUse = _isEraser ? Theme.of(context).colorScheme.surface : _selectedColor;
    
    // Compression
    int x = (details.localPosition.dx / size.width * 10000).round();
    int y = (details.localPosition.dy / size.height * 10000).round();
    int p = (details.pressure * 100).round();
    
    setState(() {
      _currentStroke = DrawingStroke(
        color: colorToUse,
        size: _isEraser ? _selectedSize * 3 : _selectedSize, // Eraser is bigger
        points: [[x, y, p]],
      );
      _redoStack.clear();
    });
  }

  void _onPointerMove(PointerEvent details, Size size) {
    if (_currentStroke == null) return;
    
    int x = (details.localPosition.dx / size.width * 10000).round();
    int y = (details.localPosition.dy / size.height * 10000).round();
    int p = (details.pressure * 100).round();

    // Prevent too many duplicate points
    final lastPoint = _currentStroke!.points.last;
    if (lastPoint[0] == x && lastPoint[1] == y && (lastPoint[2] - p).abs() < 5) {
      return; 
    }

    setState(() {
      _currentStroke!.points.add([x, y, p]);
    });
  }

  void _onPointerUp(PointerEvent details) {
    if (_currentStroke != null) {
      setState(() {
        _strokes.add(_currentStroke!);
        _currentStroke = null;
      });
    }
  }

  // --- Toolbar Actions ---
  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _redoStack.add(_strokes.removeLast());
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _strokes.add(_redoStack.removeLast());
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _redoStack.clear();
    });
  }

  Future<void> _save() async {
    if (_strokes.isEmpty) {
      Navigator.pop(context);
      return;
    }

    // 1. To PNG
    RenderRepaintBoundary boundary =
        _canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    // 2. Save PNG to temp file
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/handwriting_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(buffer);

    // 3. To JSON Vector
    final vectorJson = jsonEncode(_strokes.map((s) => s.toJson()).toList());

    Navigator.pop(context, {
      'file': file,
      'json': vectorJson,
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        title: Text(l.handwritingMemo, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(l.save, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Toolbar
          Container(
            color: cs.surface,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.undo),
                  onPressed: _strokes.isNotEmpty ? _undo : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo),
                  onPressed: _redoStack.isNotEmpty ? _redo : null,
                ),
                const Spacer(),
                ..._colors.map((c) => GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = c;
                      _isEraser = false;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedColor == c && !_isEraser ? cs.primary : Colors.grey.withOpacity(0.5),
                        width: _selectedColor == c && !_isEraser ? 3 : 1,
                      ),
                    ),
                  ),
                )),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.edit, color: !_isEraser ? cs.primary : null),
                  onPressed: () => setState(() => _isEraser = false),
                ),
                IconButton(
                  icon: Icon(Icons.cleaning_services, color: _isEraser ? cs.primary : null), // eraser icon
                  onPressed: () => setState(() => _isEraser = true),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _clear,
                ),
              ],
            ),
          ),
          // Canvas
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 3 / 4, // Define a fixed ratio for consistent viewing across devices
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(constraints.maxWidth, constraints.maxHeight);
                        return Listener(
                          onPointerDown: (e) => _onPointerDown(e, size),
                          onPointerMove: (e) => _onPointerMove(e, size),
                          onPointerUp: _onPointerUp,
                          onPointerCancel: _onPointerUp,
                          child: RepaintBoundary(
                            key: _canvasKey,
                            child: CustomPaint(
                              size: size,
                              painter: _HandwritingPainter(
                                strokes: _strokes,
                                currentStroke: _currentStroke,
                                backgroundColor: cs.surface,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
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

class _HandwritingPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? currentStroke;
  final Color backgroundColor;

  _HandwritingPainter({
    required this.strokes,
    required this.currentStroke,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill white/surface background so png is not entirely transparent (which ruins white ink)
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);

    final allStrokes = List<DrawingStroke>.from(strokes);
    if (currentStroke != null) {
      allStrokes.add(currentStroke!);
    }

    for (final stroke in allStrokes) {
      if (stroke.points.isEmpty) continue;

      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.fill;

      // perfect_freehand requires Point
      final pfPoints = stroke.points.map((p) {
        final x = p[0] / 10000.0 * size.width;
        final y = p[1] / 10000.0 * size.height;
        final pressure = p[2] / 100.0;
        return Point(x, y, pressure);
      }).toList();

      final outlinePoints = getStroke(
        pfPoints,
        options: StrokeOptions(
          size: stroke.size,
          thinning: 0.7,
          smoothing: 0.5,
          streamline: 0.5,
          simulatePressure: false, // We use actual pressure from Apple Pencil/S Pen!
        ),
      );

      final path = Path();
      if (outlinePoints.isNotEmpty) {
        path.moveTo(outlinePoints.first.dx, outlinePoints.first.dy);
        for (int i = 1; i < outlinePoints.length - 1; ++i) {
          final p0 = outlinePoints[i];
          final p1 = outlinePoints[i + 1];
          path.quadraticBezierTo(
            p0.dx,
            p0.dy,
            (p0.dx + p1.dx) / 2,
            (p0.dy + p1.dy) / 2,
          );
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HandwritingPainter oldDelegate) {
    return true; 
  }
}
