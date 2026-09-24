import 'dart:math';
import 'package:flutter/material.dart';
import 'designer_color_picker.dart';

class DesignerTableDialog extends StatefulWidget {
  final Map<String, dynamic> initialConfig;
  final ValueChanged<Map<String, dynamic>> onSave;

  const DesignerTableDialog({
    Key? key,
    required this.initialConfig,
    required this.onSave,
  }) : super(key: key);

  @override
  State<DesignerTableDialog> createState() => _DesignerTableDialogState();
}

class _DesignerTableDialogState extends State<DesignerTableDialog> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late List<Map<String, dynamic>> _subjects;
  late List<Map<String, dynamic>> _columns;
  late double _tableScale;
  late Color _headerBg;
  late Color _headerTextColor;
  late Color _rowTextColor;
  late Color _gridColor;
  late double _gridWidth;
  late double _rowSpacing;
  late double _colPadding;
  late bool _alternateRowColors;
  late Color _altRowBg;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    final cfg = widget.initialConfig;

    _subjects = List<Map<String, dynamic>>.from(
      (cfg['subjects'] as List<dynamic>? ?? [
        {'name': 'القرآن الكريم والتجويد', 'max': 100, 'pass': 33, 'obtained': 95, 'grade': 'ممتاز'},
        {'name': 'الحديث الشريف وأصوله', 'max': 100, 'pass': 33, 'obtained': 88, 'grade': 'جید جداً'},
        {'name': 'الفقه الإسلامي وأصوله', 'max': 100, 'pass': 33, 'obtained': 82, 'grade': 'جید جداً'},
        {'name': 'قواعد اللغة العربية والنحو', 'max': 100, 'pass': 33, 'obtained': 78, 'grade': 'جید'},
        {'name': 'الأدب العربي والإنشاء', 'max': 100, 'pass': 33, 'obtained': 85, 'grade': 'جید جداً'},
        {'name': 'العقائد الإسلامية والتوحيد', 'max': 100, 'pass': 33, 'obtained': 90, 'grade': 'ممتاز'},
      ]).map((e) => Map<String, dynamic>.from(e as Map)),
    );

    _columns = List<Map<String, dynamic>>.from(
      (cfg['columns'] as List<dynamic>? ?? [
        {'id': 'col1', 'title': 'نمبر شمار', 'width': 30.0, 'align': 'center'},
        {'id': 'col2', 'title': 'کتاب کا نام / مضمون', 'width': 90.0, 'align': 'right'},
        {'id': 'col3', 'title': 'کل نمبر', 'width': 35.0, 'align': 'center'},
        {'id': 'col4', 'title': 'کامیابی', 'width': 35.0, 'align': 'center'},
        {'id': 'col5', 'title': 'حاصل نمبر', 'width': 35.0, 'align': 'center'},
        {'id': 'col6', 'title': 'کیفیت / گریڈ', 'width': 45.0, 'align': 'center'},
      ]).map((e) => Map<String, dynamic>.from(e as Map)),
    );

    _tableScale = (cfg['scale'] as num?)?.toDouble() ?? 1.0;
    _headerBg = Color(cfg['headerBg'] as int? ?? 0xFF0D5C3A);
    _headerTextColor = Color(cfg['headerTextColor'] as int? ?? 0xFFFFFFFF);
    _rowTextColor = Color(cfg['rowTextColor'] as int? ?? 0xFF000000);
    _gridColor = Color(cfg['gridColor'] as int? ?? 0xFFCCCCCC);
    _gridWidth = (cfg['gridWidth'] as num?)?.toDouble() ?? 1.0;
    _rowSpacing = (cfg['rowSpacing'] as num?)?.toDouble() ?? 4.0;
    _colPadding = (cfg['colPadding'] as num?)?.toDouble() ?? 4.0;
    _alternateRowColors = cfg['alternateRowColors'] as bool? ?? true;
    _altRowBg = Color(cfg['altRowBg'] as int? ?? 0xFFF8FAFC);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  double get _totalMax => _subjects.fold(0.0, (sum, s) => sum + ((s['max'] as num?)?.toDouble() ?? 0.0));
  double get _totalObtained => _subjects.fold(0.0, (sum, s) => sum + ((s['obtained'] as num?)?.toDouble() ?? 0.0));
  double get _percentage => _totalMax > 0 ? (_totalObtained / _totalMax) * 100.0 : 0.0;

  String _calculateGrade(double pct) {
    if (pct >= 90) return 'ممتاز (Distinction)';
    if (pct >= 75) return 'جید جداً (First Class)';
    if (pct >= 60) return 'جید (Second Class)';
    if (pct >= 33) return 'مقبول (Pass)';
    return 'راسب (Fail)';
  }

  void _addSubject() {
    setState(() {
      _subjects.add({
        'name': 'نیا مضمون ${_subjects.length + 1}',
        'max': 100,
        'pass': 33,
        'obtained': 75,
        'grade': 'جید',
      });
    });
  }

  void _removeSubject(int idx) {
    setState(() {
      _subjects.removeAt(idx);
    });
  }

  void _save() {
    final updated = {
      'subjects': _subjects,
      'columns': _columns,
      'scale': _tableScale,
      'headerBg': _headerBg.toARGB32(),
      'headerTextColor': _headerTextColor.toARGB32(),
      'rowTextColor': _rowTextColor.toARGB32(),
      'gridColor': _gridColor.toARGB32(),
      'gridWidth': _gridWidth,
      'rowSpacing': _rowSpacing,
      'colPadding': _colPadding,
      'alternateRowColors': _alternateRowColors,
      'altRowBg': _altRowBg.toARGB32(),
      'totalMax': _totalMax,
      'totalObtained': _totalObtained,
      'percentage': _percentage,
      'grade': _calculateGrade(_percentage),
    };
    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogW = min(850.0, screenSize.width - 32);
    final dialogH = min(640.0, screenSize.height - 32);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: dialogW,
        height: dialogH,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Title Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.table_chart_rounded, color: Color(0xFF0F766E), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Marks & Subjects Table Studio (مضامین و کشف الدرجات)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Customize subject rows, marks, headers, colors, and auto calculations', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Summary Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D5C3A).withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0D5C3A).withAlpha(40)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _metric('Total Subjects', '${_subjects.length}'),
                  _metric('Max Marks', '${_totalMax.toInt()}'),
                  _metric('Obtained', '${_totalObtained.toInt()}'),
                  _metric('Percentage', '${_percentage.toStringAsFixed(1)}%'),
                  _metric('Grade', _calculateGrade(_percentage)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Tabs
            TabBar(
              controller: _tabCtrl,
              labelColor: const Color(0xFF0F766E),
              indicatorColor: const Color(0xFF0F766E),
              tabs: const [
                Tab(icon: Icon(Icons.menu_book_rounded, size: 18), text: 'Subjects & Marks (مضامین و نمبرات)'),
                Tab(icon: Icon(Icons.palette_rounded, size: 18), text: 'Table Styling & Columns (رنگ و ڈیزائن)'),
              ],
            ),
            const SizedBox(height: 12),

            // Content
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  // Tab 1: Subjects List
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Subject Rows', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                            icon: const Icon(Icons.add, size: 16, color: Colors.white),
                            label: const Text('Add Subject', style: TextStyle(color: Colors.white, fontSize: 12)),
                            onPressed: _addSubject,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _subjects.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (ctx, idx) {
                            final sub = _subjects[idx];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Text('#${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      initialValue: sub['name']?.toString() ?? '',
                                      style: const TextStyle(fontSize: 13, fontFamily: 'Jameel Noori Nastaleeq'),
                                      decoration: const InputDecoration(
                                        labelText: 'Book Name (کتاب)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (v) => sub['name'] = v,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: sub['max']?.toString() ?? '100',
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'Max', isDense: true, border: OutlineInputBorder()),
                                      onChanged: (v) => setState(() => sub['max'] = double.tryParse(v) ?? 100),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: sub['pass']?.toString() ?? '33',
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'Min', isDense: true, border: OutlineInputBorder()),
                                      onChanged: (v) => sub['pass'] = double.tryParse(v) ?? 33,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: sub['obtained']?.toString() ?? '0',
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'Obt', isDense: true, border: OutlineInputBorder()),
                                      onChanged: (v) => setState(() => sub['obtained'] = double.tryParse(v) ?? 0),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      initialValue: sub['grade']?.toString() ?? '',
                                      decoration: const InputDecoration(labelText: 'Grade / کیفیت', isDense: true, border: OutlineInputBorder()),
                                      onChanged: (v) => sub['grade'] = v,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                    onPressed: () => _removeSubject(idx),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  // Tab 2: Table Styling
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Table Dimensions & Scale', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Scale Factor: ', style: TextStyle(fontSize: 12)),
                            Expanded(
                              child: Slider(
                                value: _tableScale,
                                min: 0.5,
                                max: 1.5,
                                divisions: 20,
                                label: '${(_tableScale * 100).toInt()}%',
                                onChanged: (v) => setState(() => _tableScale = v),
                              ),
                            ),
                            Text('${(_tableScale * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Divider(),
                        const Text('Colors & Lines', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            _colorButton('Header Background', _headerBg, (c) => setState(() => _headerBg = c)),
                            _colorButton('Header Text Color', _headerTextColor, (c) => setState(() => _headerTextColor = c)),
                            _colorButton('Row Text Color', _rowTextColor, (c) => setState(() => _rowTextColor = c)),
                            _colorButton('Grid Border Color', _gridColor, (c) => setState(() => _gridColor = c)),
                            _colorButton('Alternate Row Color', _altRowBg, (c) => setState(() => _altRowBg = c)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          title: const Text('Alternate Row Background', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          value: _alternateRowColors,
                          onChanged: (v) => setState(() => _alternateRowColors = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: _save,
                  child: const Text('Save Table Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String val) {
    return Column(
      children: [
        Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0D5C3A))),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _colorButton(String label, Color color, ValueChanged<Color> onPicked) {
    return InkWell(
      onTap: () async {
        final c = await showDialog<Color>(
          context: context,
          builder: (_) => WindowsStyleColorPickerDialog(initialColor: color, title: label),
        );
        if (c != null) onPicked(c);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
