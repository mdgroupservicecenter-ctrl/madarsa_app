import 'package:flutter/material.dart';

class WindowsStyleColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final String title;

  const WindowsStyleColorPickerDialog({
    Key? key,
    required this.initialColor,
    this.title = 'Color Picker',
  }) : super(key: key);

  @override
  State<WindowsStyleColorPickerDialog> createState() => _WindowsStyleColorPickerDialogState();
}

class _WindowsStyleColorPickerDialogState extends State<WindowsStyleColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _val;
  String _colorModel = 'RGB';

  late TextEditingController _rCtrl;
  late TextEditingController _gCtrl;
  late TextEditingController _bCtrl;
  late TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor == Colors.transparent ? Colors.black : widget.initialColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _val = hsv.value;

    _rCtrl = TextEditingController();
    _gCtrl = TextEditingController();
    _bCtrl = TextEditingController();
    _hexCtrl = TextEditingController();

    _syncControllersFromHSV();
  }

  @override
  void dispose() {
    _rCtrl.dispose();
    _gCtrl.dispose();
    _bCtrl.dispose();
    _hexCtrl.dispose();
    super.dispose();
  }

  Color get _currentColor => HSVColor.fromAHSV(1.0, _hue, _saturation, _val).toColor();

  void _syncControllersFromHSV() {
    final c = _currentColor;
    _rCtrl.text = '${c.red}';
    _gCtrl.text = '${c.green}';
    _bCtrl.text = '${c.blue}';
    _hexCtrl.text = '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  void _updateFromRGB(int r, int g, int b) {
    final c = Color.fromARGB(255, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    final hsv = HSVColor.fromColor(c);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _val = hsv.value;
      _syncControllersFromHSV();
    });
  }

  void _handlePanSpectrum(Offset localPos, Size size) {
    setState(() {
      _hue = (localPos.dx / size.width * 360.0).clamp(0.0, 360.0);
      _saturation = (1.0 - (localPos.dy / size.height)).clamp(0.0, 1.0);
      _syncControllersFromHSV();
    });
  }

  void _handlePanValue(double dy, double height) {
    setState(() {
      _val = (1.0 - (dy / height)).clamp(0.0, 1.0);
      _syncControllersFromHSV();
    });
  }

  Widget _buildSpinnerRow(String label, TextEditingController ctrl, String channel, int value) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          width: 65,
          height: 32,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              border: OutlineInputBorder(),
            ),
            onChanged: (val) {
              final parsed = int.tryParse(val);
              if (parsed != null && parsed >= 0 && parsed <= 255) {
                final c = _currentColor;
                if (channel == 'R') _updateFromRGB(parsed, c.green, c.blue);
                if (channel == 'G') _updateFromRGB(c.red, parsed, c.blue);
                if (channel == 'B') _updateFromRGB(c.red, c.green, parsed);
              }
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _currentColor;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.color_lens_rounded, color: Color(0xFF0F766E), size: 18),
          const SizedBox(width: 8),
          Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 330,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 180,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onPanUpdate: (d) => _handlePanSpectrum(d.localPosition, const Size(240, 180)),
                        onTapDown: (d) => _handlePanSpectrum(d.localPosition, const Size(240, 180)),
                        child: CustomPaint(
                          size: const Size(double.infinity, 180),
                          painter: _ColorSpectrumPainter(
                            hue: _hue,
                            saturation: _saturation,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onPanUpdate: (d) => _handlePanValue(d.localPosition.dy, 180),
                      onTapDown: (d) => _handlePanValue(d.localPosition.dy, 180),
                      child: SizedBox(
                        width: 28,
                        height: 180,
                        child: CustomPaint(
                          painter: _ValueBarPainter(
                            hue: _hue,
                            saturation: _saturation,
                            value: _val,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 32,
                    decoration: BoxDecoration(
                      color: currentColor,
                      border: Border.all(color: Colors.grey.shade500),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Hex:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 95,
                    height: 32,
                    child: TextField(
                      controller: _hexCtrl,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        final clean = val.replaceAll('#', '');
                        if (clean.length == 6) {
                          try {
                            final parsed = int.parse('FF$clean', radix: 16);
                            final c = Color(parsed);
                            _updateFromRGB(c.red, c.green, c.blue);
                          } catch (_) {}
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildSpinnerRow('R:', _rCtrl, 'R', currentColor.red),
                  const SizedBox(width: 8),
                  _buildSpinnerRow('G:', _gCtrl, 'G', currentColor.green),
                  const SizedBox(width: 8),
                  _buildSpinnerRow('B:', _bCtrl, 'B', currentColor.blue),
                ],
              ),
              const SizedBox(height: 12),
              // Preset Palette Swatches
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Colors.black,
                  Colors.white,
                  const Color(0xFF0D5C3A), // Islamic Green
                  const Color(0xFF1B4D3E),
                  const Color(0xFFFFD700), // Gold
                  const Color(0xFFB8860B),
                  const Color(0xFF1E3A8A), // Navy
                  const Color(0xFF0F766E), // Teal
                  const Color(0xFF991B1B), // Dark Red
                  const Color(0xFF7C3AED), // Purple
                  const Color(0xFF4B5563), // Slate Gray
                  Colors.transparent,
                ].map((c) {
                  return InkWell(
                    onTap: () {
                      if (c == Colors.transparent) {
                        Navigator.pop(context, Colors.transparent);
                      } else {
                        final hsv = HSVColor.fromColor(c);
                        setState(() {
                          _hue = hsv.hue;
                          _saturation = hsv.saturation;
                          _val = hsv.value;
                          _syncControllersFromHSV();
                        });
                      }
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: c == Colors.transparent
                          ? const Icon(Icons.block, size: 14, color: Colors.red)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
          onPressed: () => Navigator.pop(context, currentColor),
          child: const Text('Select Color', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _ColorSpectrumPainter extends CustomPainter {
  final double hue;
  final double saturation;

  _ColorSpectrumPainter({required this.hue, required this.saturation});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    const hueGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF00FF00),
        Color(0xFF00FFFF),
        Color(0xFF0000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ],
    );

    final paintHue = Paint()..shader = hueGradient.createShader(rect);
    canvas.drawRect(rect, paintHue);

    const satGradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Colors.white, Colors.transparent],
    );

    final paintSat = Paint()..shader = satGradient.createShader(rect);
    canvas.drawRect(rect, paintSat);

    final selX = (hue / 360.0) * size.width;
    final selY = (1.0 - saturation) * size.height;

    canvas.drawCircle(
      Offset(selX, selY),
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawCircle(
      Offset(selX, selY),
      5,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorSpectrumPainter old) =>
      old.hue != hue || old.saturation != saturation;
}

class _ValueBarPainter extends CustomPainter {
  final double hue;
  final double saturation;
  final double value;

  _ValueBarPainter({required this.hue, required this.saturation, required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width - 8, size.height);
    final pureColor = HSVColor.fromAHSV(1.0, hue, saturation, 1.0).toColor();

    final valGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white, pureColor, Colors.black],
    );

    final paintVal = Paint()..shader = valGradient.createShader(rect);
    canvas.drawRect(rect, paintVal);
    canvas.drawRect(rect, Paint()..color = Colors.grey.shade600..style = PaintingStyle.stroke);

    final arrowY = (1.0 - value) * size.height;
    final arrowPath = Path()
      ..moveTo(size.width, arrowY - 5)
      ..lineTo(size.width - 7, arrowY)
      ..lineTo(size.width, arrowY + 5)
      ..close();

    canvas.drawPath(arrowPath, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant _ValueBarPainter old) =>
      old.hue != hue || old.saturation != saturation || old.value != value;
}
