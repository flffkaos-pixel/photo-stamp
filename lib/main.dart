import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const PhotoStampApp());

class PhotoStampApp extends StatelessWidget {
  const PhotoStampApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photo Stamp',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const StampHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class StampHomePage extends StatefulWidget {
  const StampHomePage({super.key});

  @override
  State<StampHomePage> createState() => _StampHomePageState();
}

class _StampHomePageState extends State<StampHomePage> {
  List<File> _stamps = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadStamps();
  }

  Future<void> _loadStamps() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/stamps');
    if (!await dir.exists()) {
      setState(() => _stamps = []);
      return;
    }
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    setState(() => _stamps = files);
  }

  Future<void> _pickAndStamp() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1024);
    if (file == null) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StampPreviewScreen(imagePath: file.path)),
    );
    _loadStamps();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Photo Stamp')),
      body: _stamps.isEmpty
          ? Center(
              child: Text(
                '저장된 스탬프가 없습니다\n+ 버튼을 눌러 새 스탬프를 만드세요',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8,
              ),
              itemCount: _stamps.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => StampViewScreen(file: _stamps[i]))),
                child: Image.file(_stamps[i], fit: BoxFit.cover),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndStamp,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class StampPreviewScreen extends StatefulWidget {
  final String imagePath;
  const StampPreviewScreen({super.key, required this.imagePath});

  @override
  State<StampPreviewScreen> createState() => _StampPreviewScreenState();
}

class _StampPreviewScreenState extends State<StampPreviewScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _saving = false;

  Future<void> _saveStamp() async {
    setState(() => _saving = true);
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/stamps');
      if (!await dir.exists()) await dir.create();

      final name = 'stamp_${DateTime.now().millisecondsSinceEpoch}.png';
      await File('${dir.path}/$name').writeAsBytes(byteData.buffer.asUint8List());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('스탬프 저장 완료!')));
      Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('스탬프 미리보기'), actions: [
        _saving
            ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(onPressed: _saveStamp, icon: const Icon(Icons.save), tooltip: '저장'),
      ]),
      body: Center(
        child: SingleChildScrollView(
          child: RepaintBoundary(
            key: _repaintKey,
            child: StampWidget(imagePath: widget.imagePath),
          ),
        ),
      ),
    );
  }
}

class StampWidget extends StatelessWidget {
  final String imagePath;
  const StampWidget({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    const double stampSize = 280;
    const double margin = 20;
    const double imageSize = stampSize - margin * 2;

    return CustomPaint(
      painter: StampEdgePainter(perforationR: 7),
      child: Container(
        width: stampSize,
        height: stampSize,
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(3, 5))],
        ),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(File(imagePath), width: imageSize, height: imageSize, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class StampEdgePainter extends CustomPainter {
  final double perforationR;

  const StampEdgePainter({this.perforationR = 7});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final double r = perforationR;
    final double step = r * 3.0;

    for (double x = 0; x <= size.width; x += step) {
      canvas.drawCircle(Offset(x, 0), r, paint);
      canvas.drawCircle(Offset(x, size.height), r, paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawCircle(Offset(0, y), r, paint);
      canvas.drawCircle(Offset(size.width, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StampViewScreen extends StatelessWidget {
  final File file;
  const StampViewScreen({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('스탬프')),
      body: Center(child: InteractiveViewer(child: Image.file(file))),
    );
  }
}
