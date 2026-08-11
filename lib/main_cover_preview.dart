import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

String? _globalError;

// Synchronous trace logger — flushes immediately to survive native crashes.
void _trace(String tag) {
  final line = '[${DateTime.now().toIso8601String()}] $tag\n';
  final targets = <String>['/storage/emulated/0/PhotoStamp/trace.log'];
  try {
    final storage = Directory('/storage');
    if (storage.existsSync()) {
      for (final d in storage.listSync().whereType<Directory>()) {
        final name = d.path.split(Platform.pathSeparator).last;
        if (name == 'emulated' || name == 'self') continue;
        targets.add('${d.path}/PhotoStamp/trace.log');
      }
    }
  } catch (_) {}
  for (final path in targets) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      final raf = file.openSync(mode: FileMode.append);
      raf.writeStringSync(line);
      raf.flushSync();
      raf.closeSync();
    } catch (_) {}
  }
}

Future<void> _reportError(Object error, StackTrace? stack) async {
  _globalError = '$error';
  final entry = '[${DateTime.now()}]\n$error\n${stack ?? ''}\n${'=' * 40}\n';
  final targets = <String>['/storage/emulated/0/PhotoStamp/crash.log'];
  try {
    final storage = Directory('/storage');
    if (await storage.exists()) {
      for (final d in storage.listSync().whereType<Directory>()) {
        final name = d.path.split(Platform.pathSeparator).last;
        if (name == 'emulated' || name == 'self') continue;
        targets.add('${d.path}/PhotoStamp/crash.log');
      }
    }
  } catch (_) {}
  for (final path in targets) {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(entry, mode: FileMode.append);
    } catch (_) {}
  }
  try {
    final doc = await getApplicationDocumentsDirectory();
    final file = File('${doc.path}/crash.log');
    await file.parent.create(recursive: true);
    await file.writeAsString(entry, mode: FileMode.append);
  } catch (_) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _trace('main start');
  FlutterError.onError = (details) {
    _reportError(details.exception, details.stack);
  };
  runZonedGuarded(
    () => runApp(const PhotoStampApp()),
    (e, s) => _reportError(e, s),
  );
}

class PhotoStampApp extends StatelessWidget {
  const PhotoStampApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photo Stamp',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const StampHomePage(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        if (_globalError == null) return child!;
        return Stack(
          children: [
            child!,
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: Material(
                color: Colors.red.shade900,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    '오류 발생: $_globalError',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum StampStyle { classic }

class StampHomePage extends StatefulWidget {
  const StampHomePage({super.key});

  @override
  State<StampHomePage> createState() => _StampHomePageState();
}

class _StampHomePageState extends State<StampHomePage> {
  List<File> _stamps = [];
  List<File> _samples = [];
  Map<String, Map<String, String>> _captions = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _ensureSamples();
    } catch (e, s) {
      _reportError(e, s);
    }
    try {
      await _loadStamps();
    } catch (e, s) {
      _reportError(e, s);
    }
  }

  Future<void> _ensureSamples() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/stamps');
    if (!await dir.exists()) await dir.create();
    final classic = File('${dir.path}/sample_stamp_classic.png');
    if (!await classic.exists()) {
      await _createSampleStamp(dir, StampStyle.classic, classic.path, '우표');
    }
    _loadStamps();
  }

  Future<File> _createSampleStamp(Directory dir, StampStyle style, String path, String label) async {
    const size = 1200.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(size, size),
          const [Color(0xFFD32F2F), Color(0xFFFF8A65)],
        ),
    );

    final dotPaint = Paint()..color = Colors.white.withOpacity(0.15);
    for (double x = 70; x < size; x += 140) {
      for (double y = 70; y < size; y += 140) {
        canvas.drawCircle(Offset(x, y), 20, dotPaint);
      }
    }

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 160,
          fontWeight: FontWeight.bold,
          letterSpacing: 24,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));

    final outerPath = _perforatedStampRect(Rect.fromLTWH(0, 0, size, size), size * 0.012);
    final ringPath = buildStampPath(Rect.fromLTWH(0, 0, size, size), style);
    final masked = ui.PictureRecorder();
    final maskedCanvas = Canvas(masked, Rect.fromLTWH(0, 0, size, size));
    maskedCanvas.save();
    maskedCanvas.clipPath(outerPath);
    maskedCanvas.drawPicture(recorder.endRecording());
    maskedCanvas.restore();
    maskedCanvas.drawPath(ringPath, Paint()..color = Colors.black);
    maskedCanvas.drawPath(
      outerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..color = Colors.black,
    );

    final image = await masked.endRecording().toImage(1200, 1200);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return File(path);
    final file = File(path);
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }

  Future<void> _loadStamps() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/stamps');
    if (!await dir.exists()) {
      setState(() { _stamps = []; _samples = []; _captions = {}; });
      return;
    }
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    final samples = files.where((f) => f.path.contains('sample_')).toList();
    final stamps = files.where((f) => !f.path.contains('sample_')).toList();

    // load captions
    final metaFile = File('${dir.path}/meta.json');
    Map<String, Map<String, String>> capMap = {};
    if (await metaFile.exists()) {
      try {
        final metaList = json.decode(await metaFile.readAsString()) as List;
        for (final m in metaList) {
          if (m is Map) {
            final fn = m['file']?.toString() ?? '';
            capMap['${dir.path}/$fn'] = {
              'date': m['date']?.toString() ?? '',
              'comment': m['comment']?.toString() ?? '',
            };
          }
        }
      } catch (_) {}
    }

    setState(() {
      _stamps = stamps;
      _samples = samples;
      _captions = capMap;
    });
  }

  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('카메라를 찾을 수 없습니다')));
        }
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StampCameraScreen(camera: cameras.first)),
      );
      _loadStamps();
    } catch (e, s) {
      _reportError(e, s);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('카메라 오류: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('스탬프 앨범'),
        actions: [
          if (_stamps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('내 컬렉션 ${_stamps.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      backgroundColor: const Color(0xFFF5EFE0),
      body: () {
        final showReal = _stamps.isNotEmpty;
        final realList = _stamps;
        if (!showReal && _samples.isEmpty) {
          return Center(
            child: Text(
              '저장된 스탬프가 없습니다\n+ 버튼을 눌러 새 스탬프를 찍으세요',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            if (showReal) ...[
              _sectionHeader('내 컬렉션'),
              _albumGrid(realList, _captions, showCaptions: true),
            ],
            ...[
              _sectionHeader(showReal ? '기본 스탬프' : '샘플'),
              _albumGrid(_samples, _captions, onTap: _openCamera),
            ],
          ],
        );
      }(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCamera,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              )),
        ],
      ),
    );
  }

  }

  Future<void> _showShareOptions(BuildContext context, File file) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('시스템 공유'),
              onTap: () async {
                Navigator.pop(context);
                final bytes = await file.readAsBytes();
                await Share.shareXFiles([XFile.fromData(bytes, name: file.path.split('/').last, mimeType: 'image/png')],
                    text: '내 스탬프 사진');
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('갤러리에 저장'),
              onTap: () async {
                Navigator.pop(context);
                // TODO: 갤러리 저장 구현 (필요시 image_gallery_saver 패키지 추가)
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('갤러리 저장 기능은 추후 추가 예정')));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.purple),
              title: const Text('Instagram'),
              onTap: () async {
                Navigator.pop(context);
                await Share.shareXFiles([XFile.fromData(await file.readAsBytes(), name: 'stamp.png', mimeType: 'image/png')]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.facebook, color: Colors.blue),
              title: const Text('Facebook'),
              onTap: () async {
                Navigator.pop(context);
                await Share.shareXFiles([XFile.fromData(await file.readAsBytes(), name: 'stamp.png', mimeType: 'image/png')]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.alternate_email, color: Colors.black),
              title: const Text('Threads'),
              onTap: () async {
                Navigator.pop(context);
                await Share.shareXFiles([XFile.fromData(await file.readAsBytes(), name: 'stamp.png', mimeType: 'image/png')]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.alternate_email, color: Colors.black),
              title: const Text('X (Twitter)'),
              onTap: () async {
                Navigator.pop(context);
                await Share.shareXFiles([XFile.fromData(await file.readAsBytes(), name: 'stamp.png', mimeType: 'image/png')]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _albumGrid(List<File> files, Map<String, Map<String, String>> captions, {VoidCallback? onTap, bool showCaptions = false}) {
    if (files.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('항목이 없습니다', style: TextStyle(color: Colors.grey))),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: files.length,
      itemBuilder: (context, i) {
        final file = files[i];
        final cap = captions[file.path];
        final tap = onTap ??
            () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => StampViewScreen(file: file)),
                );
        return GestureDetector(
          onTap: tap,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(color: Colors.black12, width: 0.5),
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(file, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    if (showCaptions && cap != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                        ),
                        child: Text(
                          [cap['date'], cap['comment']].where((s) => s != null && s!.isNotEmpty).join('  '),
                          style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.black54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _showShareOptions(context, file),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.share, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
}

class StampCameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const StampCameraScreen({super.key, required this.camera});

  @override
  State<StampCameraScreen> createState() => _StampCameraScreenState();
}

class _StampCameraScreenState extends State<StampCameraScreen> {
  late CameraController _controller;
  late Future<void> _initFuture;
  StampStyle _currentStyle = StampStyle.classic;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.medium, enableAudio: false);
    _initFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    _trace('camera: takePhoto start');
    try {
      await _initFuture;
      final file = await _controller.takePicture();
      _trace('camera: picture taken ${file.path}');
      final fsize = await File(file.path).length();
      _trace('camera: file size $fsize bytes');
      if (!mounted) return;
      final aspect = _controller.value.aspectRatio;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => StampCropScreen(
            imagePath: file.path,
            style: _currentStyle,
            previewAspect: aspect,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('촬영 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder(
        future: _initFuture,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('카메라 오류: ${snap.error}'));
          }
          return Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: CameraPreview(_controller),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: OverlayMaskPainter(style: _currentStyle),
                ),
              ),
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStyleBar(),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _takePhoto,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, size: 36, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStyleBar() {
    final styles = [
      (StampStyle.classic, Icons.local_post_office, '우표'),
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: styles.map((s) {
          final selected = _currentStyle == s.$1;
          return GestureDetector(
            onTap: () => setState(() => _currentStyle = s.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(s.$2, size: 20, color: selected ? Colors.black87 : Colors.white70),
                  const SizedBox(width: 6),
                  Text(s.$3, style: TextStyle(
                    color: selected ? Colors.black87 : Colors.white70,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  )),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// 3:4 stamp rect centered like the middle cell of a 3x3 grid.
Rect _stampRect34(Size size) {
  // middle cell of a 3x3 grid:
  final cellW = size.width / 3;
  final cellH = size.height / 3;
  // fit a 3:4 box inside the middle cell
  double w = cellW;
  double h = w * 4.0 / 3.0;
  if (h > cellH) {
    h = cellH;
    w = h * 3.0 / 4.0;
  }
  final left = (size.width - w) / 2;
  final top = (size.height - h) / 2;
  return Rect.fromLTWH(left, top, w, h);
}

class StampFramePainter extends CustomPainter {
  final StampStyle style;
  const StampFramePainter({required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final stampRect = _stampRect34(size);
    final outerPath = _perforatedStampRect(stampRect, stampRect.width * 0.012);
    final ringPath = buildStampPath(stampRect, style);

    canvas.drawPath(ringPath, Paint()..color = Colors.black);
    canvas.drawPath(
      outerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(covariant StampFramePainter oldDelegate) =>
      oldDelegate.style != style;
}

class OverlayMaskPainter extends CustomPainter {
  final StampStyle style;
  const OverlayMaskPainter({required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final stampRect = _stampRect34(size);

    final maskPaint = Paint()..color = const Color(0x88000000);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), maskPaint);

    final outerPath = _perforatedStampRect(stampRect, stampRect.width * 0.012);
    final ringPath = buildStampPath(stampRect, style);

    final clearPaint = Paint()..blendMode = BlendMode.clear;
    canvas.drawPath(outerPath, clearPaint);

    canvas.drawPath(ringPath, Paint()..color = Colors.black);

    canvas.drawPath(
      outerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(covariant OverlayMaskPainter oldDelegate) =>
      oldDelegate.style != style;
}

Path buildStampPath(Rect rect, StampStyle style) => _buildClassicPath(rect);

Path _buildClassicPath(Rect rect) {
  final r = rect.shortestSide * 0.012;
  final outer = _perforatedStampRect(rect, r);
  final c = rect.center;
  final m = Matrix4.translationValues(c.dx, c.dy, 0)
      ..scale(0.88)
      ..translate(-c.dx, -c.dy);
  final inner = outer.transform(m.storage);
  return Path.combine(PathOperation.difference, outer, inner);
}

Path _perforatedStampRect(Rect rect, double r) {
  final base = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)));
  final holes = Path();
  final step = r * 3.8;
  void addHoles(double start, double end, double fixed, bool horizontal) {
    for (double pos = start + step * 0.8; pos < end - step * 0.8; pos += step) {
      if (horizontal) {
        holes.addOval(Rect.fromCircle(center: Offset(pos, fixed), radius: r));
      } else {
        holes.addOval(Rect.fromCircle(center: Offset(fixed, pos), radius: r));
      }
    }
  }
  addHoles(rect.left, rect.right, rect.top, true);
  addHoles(rect.left, rect.right, rect.bottom, true);
  addHoles(rect.top, rect.bottom, rect.left, false);
  addHoles(rect.top, rect.bottom, rect.right, false);
  return Path.combine(PathOperation.difference, base, holes);
}

class StampCropScreen extends StatefulWidget {
  final String imagePath;
  final StampStyle style;
  final double previewAspect;
  const StampCropScreen({
    super.key,
    required this.imagePath,
    required this.style,
    this.previewAspect = 0.75,
  });

  @override
  State<StampCropScreen> createState() => _StampCropScreenState();
}

class _StampCropScreenState extends State<StampCropScreen> {
  late StampStyle _currentStyle;
  late TextEditingController _commentCtrl;
  Size? _screenBox;
  int? _photoW;
  int? _photoH;
  ui.Image? _maskImage;

  @override
  void initState() {
    super.initState();
    _currentStyle = widget.style;
    _commentCtrl = TextEditingController();
    _trace('preview: initState');
    _preparePhoto();
  }

  Future<void> _preparePhoto() async {
    try {
      final bytes = File(widget.imagePath).readAsBytesSync();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final oriented = img.bakeOrientation(decoded);
        _photoW = oriented.width;
        _photoH = oriented.height;
      }
      try {
        final maskBytes = await rootBundle.load('assets/stamp_mask.png');
        final maskDecoded = img.decodePng(maskBytes.buffer.asUint8List());
        if (maskDecoded != null) {
          final c = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            maskDecoded.getBytes(order: img.ChannelOrder.rgba),
            maskDecoded.width,
            maskDecoded.height,
            ui.PixelFormat.rgba8888,
            (result) { if (!c.isCompleted) c.complete(result); },
          );
          _maskImage = await c.future;
        }
      } catch (me) {
        _trace('preview: mask load fail $me');
      }
      if (mounted) setState(() {});
    } catch (e, s) {
      _reportError(e, s);
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _maskImage?.dispose();
    super.dispose();
  }

  Future<void> _saveStamp() async {
    _trace('preview: saveStamp start');
    try {
      _trace('preview: before read');
      final photoBytes = File(widget.imagePath).readAsBytesSync();
      _trace('preview: bytes ${photoBytes.length}B');

      _trace('preview: before decode');
      var src = img.decodeImage(photoBytes);
      if (src == null) throw Exception('디코딩 실패');
      src = img.bakeOrientation(src);
      _trace('preview: decoded ${src.width}x${src.height}');

      const outW = 720;
      const outH = 960;

      // stamp-window 매핑: 미리보기와 동일한 cover 표시 → 같은 픽셀 영역 crop
      final box = _screenBox;
      int cropW, cropH, cropX, cropY;
      final pw = _photoW;
      final ph = _photoH;
      if (box != null && pw != null && ph != null) {
        final rect = _stampRect34(box);
        final boxAspect = box.width / box.height;
        final photoAspect = pw / ph;
        double scale;
        if (photoAspect > boxAspect) {
          scale = pw / box.width;
        } else {
          scale = ph / box.height;
        }
        final sx = (rect.left * scale).round().clamp(0, pw - 1);
        final sy = (rect.top * scale).round().clamp(0, ph - 1);
        final sw = (rect.width * scale).round().clamp(1, pw - sx);
        final sh = (rect.height * scale).round().clamp(1, ph - sy);
        cropX = sx;
        cropY = sy;
        cropW = sw;
        cropH = sh;
        _trace('preview: stamp-window crop $cropW x $cropH @ ($cropX,$cropY)');
      } else {
        // 폴백: 3:4 중앙 crop
        if (src.width / src.height > outW / outH) {
          cropH = src.height;
          cropW = (cropH * outW / outH).round();
        } else {
          cropW = src.width;
          cropH = (cropW * outH / outW).round();
        }
        cropX = ((src.width - cropW) / 2).round().clamp(0, src.width - cropW);
        cropY = ((src.height - cropH) / 2).round().clamp(0, src.height - cropH);
        _trace('preview: fallback 3:4 crop');
      }

      var cropped = img.copyCrop(src, x: cropX, y: cropY, width: cropW, height: cropH);
      final resized = img.copyResize(cropped, width: outW, height: outH, interpolation: img.Interpolation.average);
      _trace('preview: resized ${resized.width}x${resized.height}');

      // 마스크 알파 합성 (마스크 luminance로 src 합성)
      var maskSrc = img.decodePng((await rootBundle.load('assets/stamp_mask.png')).buffer.asUint8List());
      if (maskSrc != null) {
        try {
          final maskResized = img.copyResize(maskSrc, width: outW, height: outH, interpolation: img.Interpolation.average);
          final composed = img.compositeImage(
            resized,
            resized,
            mask: maskResized,
            maskChannel: img.Channel.luminance,
            blend: img.BlendMode.direct,
          );
          final png = img.encodePng(composed);
          _trace('preview: png(masked) ${png.length}B');
          await _writeStamp(png);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('스탬프 저장 완료!')));
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        } catch (me, ms) {
          _trace('preview: mask composite fail $me — fallback to plain crop');
          _reportError(me, ms);
        }
      }

      final png = img.encodePng(resized);
      _trace('preview: png ${png.length}B');
      await _writeStamp(png);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('스탬프 저장 완료!')));
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e, s) {
      _trace('preview: saveStamp ERROR $e');
      _reportError(e, s);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }

  Future<void> _writeStamp(Uint8List png) async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/stamps');
    if (!await dir.exists()) await dir.create();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final name = 'stamp_$timestamp.png';
    await File('${dir.path}/$name').writeAsBytes(png);

    final comment = _commentCtrl.text.trim();
    final now = DateTime.now();
    final dateStr = '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
    final metaFile = File('${dir.path}/meta.json');
    List<Map<String, dynamic>> metaList = [];
    if (await metaFile.exists()) {
      try {
        metaList = (json.decode(await metaFile.readAsString()) as List).cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    metaList.add({'file': name, 'date': dateStr, 'comment': comment});
    await metaFile.writeAsString(const JsonEncoder.withIndent('  ').convert(metaList));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('미리보기'),
        leading: IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '다시 찍기',
          onPressed: _retake,
        ),
        actions: [
          IconButton(
            onPressed: _saveStamp,
            icon: const Icon(Icons.save),
            tooltip: '저장'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final box = Size(constraints.maxWidth, constraints.maxHeight);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _screenBox != box) {
                    setState(() => _screenBox = box);
                  }
                });
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.cover,
                        cacheWidth: 1080,
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _StampWindowPainter(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _commentCtrl,
                decoration: const InputDecoration(
                  hintText: '코멘트 (선택)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _retake() async {
    _trace('crop: retake');
    try {
      Navigator.of(context).pop();
    } catch (_) {}
  }
}

class _StampClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    return _perforatedStampRect(rect, rect.width * 0.012);
  }

  @override
  bool shouldReclip(covariant _StampClipper oldClipper) => false;
}

class _StampWindowPainter extends CustomPainter {
  const _StampWindowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _stampRect34(size);
    final outerPath = _perforatedStampRect(rect, rect.width * 0.012);
    final ringPath = buildStampPath(rect, StampStyle.classic);

    final outside = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..close();
    final stampWindow = Path.combine(PathOperation.intersect, outside, outerPath);
    final overlay = Path.combine(PathOperation.difference, outside, stampWindow);
    canvas.drawPath(overlay, Paint()..color = const Color(0xE6000000));

    canvas.drawPath(ringPath, Paint()..color = Colors.black);
    canvas.drawPath(
      outerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(covariant _StampWindowPainter oldDelegate) => false;
}

class StampViewScreen extends StatelessWidget {
  final File file;
  const StampViewScreen({super.key, required this.file});

  Future<void> _shareStamp(BuildContext context) async {
    final bytes = await file.readAsBytes();
    await Share.shareXFiles([XFile.fromData(bytes, name: file.path.split('/').last, mimeType: 'image/png')],
        text: '내 스탬프 사진');
  }

  Future<void> _shareToApp(BuildContext context, String app) async {
    final bytes = await file.readAsBytes();
    final tempFile = File('${(await getTemporaryDirectory()).path}/stamp_share.png');
    await tempFile.writeAsBytes(bytes);

    String url;
    switch (app) {
      case 'instagram':
        url = 'instagram://app';
        break;
      case 'facebook':
        url = 'fb://';
        break;
      case 'threads':
        url = 'threads://';
        break;
      case 'x':
        url = 'twitter://';
        break;
      default:
        return;
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await Share.shareXFiles([XFile.fromData(await tempFile.readAsBytes(), name: 'stamp.png', mimeType: 'image/png')]);
} else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$app 앱이 설치되어 있지 않습니다')));
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('스탬프'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.share),
            onSelected: (value) async {
              if (value == 'share') {
                await _shareStamp(context);
              } else if (value.startsWith('app_')) {
                await _shareToApp(context, value.replaceFirst('app_', ''));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'share', child: Text('시스템 공유')),
              const PopupMenuItem(value: 'app_instagram', child: Text('Instagram')),
              const PopupMenuItem(value: 'app_facebook', child: Text('Facebook')),
              const PopupMenuItem(value: 'app_threads', child: Text('Threads')),
              const PopupMenuItem(value: 'app_x', child: Text('X (Twitter)')),
              const PopupMenuItem(value: 'save_gallery', child: Text('갤러리에 저장')),
            ],
          ),
        ],
      ),
      body: Center(child: InteractiveViewer(child: Image.file(file))),
    );
  }
}
