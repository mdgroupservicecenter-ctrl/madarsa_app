import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:hijri/hijri_calendar.dart';
import '../../../../core/utils/urdu_number_helper.dart';
import '../../data/models/designer_template_model.dart';
import '../../data/models/sample_document_data.dart';
import '../../data/repositories/designer_template_repository.dart';
import '../services/universal_pdf_exporter.dart';
import '../services/designer_data_service.dart';
import '../widgets/designer_color_picker.dart';
import '../widgets/designer_font_dropdown.dart';
import '../widgets/designer_table_dialog.dart';

class CardDesignerScreen extends StatefulWidget {
  const CardDesignerScreen({super.key});

  @override
  State<CardDesignerScreen> createState() => _CardDesignerScreenState();
}

class _CardDesignerScreenState extends State<CardDesignerScreen> {
  final _repository = DesignerTemplateRepository();
  late DesignerTemplate _currentTemplate;

  // Active UI states
  String _activeSide = 'front'; // 'front' or 'back'
  String? _selectedElementId;
  bool _isPreviewMode = false;
  double _zoomScale = 1.0;
  bool _showGrid = true;
  bool _snapToGrid = false;
  double _snapStepMm = 10.0;
  bool _isSaving = false;

  // Real Database / Sample Records
  List<DesignerStudentItem> _students = [];
  List<String> _availableClasses = ['All Classes'];
  String _selectedClass = 'All Classes';
  int _currentRecordIndex = 0;
  String _searchQuery = '';

  // Dates
  DateTime _issueDate = DateTime.now();
  late HijriCalendar _hijriDate;

  // All Templates
  List<DesignerTemplate> _allTemplates = [];

  // Left panel active tab (0: Tools, 1: Page Setup, 2: Themes & JSON)
  int _leftPanelTabIndex = 0;

  // Right panel active tab (0: Inspector, 1: Table Studio)
  int _rightPanelTabIndex = 0;

  // Table Studio State
  bool _isTableGrouped = true;
  bool _enableSecondTable = false;
  bool _enableConditionalColors = true;
  double _distinctionThreshold = 90.0;
  double _highMarkThreshold = 75.0;
  double _averageMarkThreshold = 60.0;
  double _passMarkThreshold = 33.0;

  @override
  void initState() {
    super.initState();
    _hijriDate = HijriCalendar.fromDate(_issueDate);
    _currentTemplate = DesignerTemplateRepository.getStarterTemplates().first;
    _loadAllTemplates();
    _loadRealData();
  }

  Future<void> _loadAllTemplates() async {
    final list = await _repository.getAllTemplates();
    if (mounted) {
      setState(() {
        _allTemplates = list;
      });
    }
  }

  Future<void> _loadRealData() async {
    final classes = await DesignerDataService.fetchClasses();
    final students = await DesignerDataService.fetchStudents();
    if (mounted) {
      setState(() {
        _availableClasses = ['All Classes', ...classes];
        _students = students;
      });
    }
  }

  Future<void> _filterByClass(String className) async {
    setState(() {
      _selectedClass = className;
      _currentRecordIndex = 0;
    });
    final students = await DesignerDataService.fetchStudents(classFilter: className);
    if (mounted) {
      setState(() {
        _students = students;
      });
    }
  }

  DesignerStudentItem? get _currentStudent {
    if (_students.isEmpty) return null;
    final filtered = _effectiveStudents;
    if (filtered.isEmpty) return null;
    return filtered[_currentRecordIndex.clamp(0, filtered.length - 1)];
  }

  List<DesignerStudentItem> get _effectiveStudents {
    if (_searchQuery.isEmpty) return _students;
    return _students.where((s) {
      return s.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (s.grNo?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
    }).toList();
  }

  Map<String, String> get _currentTokens {
    final s = _currentStudent;
    final Map<String, String> tokens = s != null ? s.toTokensMap() : Map.from(SampleDocumentData.sampleTokensMap);
    tokens['{{card.date}}'] = '${_issueDate.day}/${_issueDate.month}/${_issueDate.year}';
    tokens['{{card.hijri_date}}'] = '${_hijriDate.hDay} ${_hijriDate.longMonthName} ${_hijriDate.hYear}ھ';
    return tokens;
  }

  DesignerElement? get _selectedElement {
    if (_selectedElementId == null) return null;
    try {
      return _currentTemplate.elements.firstWhere((e) => e.id == _selectedElementId);
    } catch (_) {
      return null;
    }
  }

  DesignerElement? get _activeTableElement {
    final sel = _selectedElement;
    if (sel != null && sel.type == DesignerElementType.table) return sel;
    try {
      return _currentTemplate.elements.firstWhere((e) => e.type == DesignerElementType.table);
    } catch (_) {
      return null;
    }
  }

  void _switchDocumentType(DocumentType type) {
    final starter = DesignerTemplateRepository.getStarterTemplates().firstWhere(
      (t) => t.documentType == type,
      orElse: () => DesignerTemplate(
        id: 'blank_${type.name}_${DateTime.now().millisecondsSinceEpoch}',
        name: '${type.labelUr} (New Design)',
        documentType: type,
        preset: type == DocumentType.resultCard || type == DocumentType.purchaseBill
            ? CanvasPreset.a4Portrait
            : (type == DocumentType.certificate
                ? CanvasPreset.a4Landscape
                : (type == DocumentType.feeReceipt ? CanvasPreset.a5Portrait : CanvasPreset.cr80Vertical)),
      ),
    );

    setState(() {
      _currentTemplate = starter.copyWith();
      _selectedElementId = null;
      _activeSide = 'front';
      if (type == DocumentType.resultCard || type == DocumentType.feeReceipt || type == DocumentType.purchaseBill || type == DocumentType.libraryCard || type == DocumentType.admitCard) {
        _rightPanelTabIndex = 1; // Auto open Table Studio!
      } else {
        _rightPanelTabIndex = 0;
      }
    });
  }

  void _switchPreset(CanvasPreset preset) {
    setState(() {
      _currentTemplate = _currentTemplate.copyWith(
        preset: preset,
        widthMm: preset.widthMm,
        heightMm: preset.heightMm,
      );
    });
  }

  // ── Apply Signature Themes ──

  void _applyTheme(String themeName) {
    setState(() {
      if (themeName == 'Golden Amber Royal') {
        _currentTemplate.backgroundColor = Colors.white;
        _currentTemplate.backgroundColor2 = const Color(0xFFFFFBEB);
        _currentTemplate.borderColor = const Color(0xFFD97706);
        _currentTemplate.borderWidth = 2.0;
        for (final el in _currentTemplate.elements) {
          if (el.type == DesignerElementType.table) {
            el.tableConfig?['headerBg'] = 0xFF0D5C3A;
            el.tableConfig?['headerTextColor'] = 0xFFFFFFFF;
            el.tableConfig?['gridColor'] = 0xFFD97706;
          }
        }
      } else if (themeName == 'Executive Sapphire Navy') {
        _currentTemplate.backgroundColor = Colors.white;
        _currentTemplate.backgroundColor2 = const Color(0xFFF0F9FF);
        _currentTemplate.borderColor = const Color(0xFF1E3A8A);
        _currentTemplate.borderWidth = 2.0;
        for (final el in _currentTemplate.elements) {
          if (el.type == DesignerElementType.table) {
            el.tableConfig?['headerBg'] = 0xFF1E3A8A;
            el.tableConfig?['headerTextColor'] = 0xFFFFFFFF;
            el.tableConfig?['gridColor'] = 0xFF0284C7;
          }
        }
      } else if (themeName == 'Crimson Ruby Gold') {
        _currentTemplate.backgroundColor = Colors.white;
        _currentTemplate.backgroundColor2 = const Color(0xFFFFF1F2);
        _currentTemplate.borderColor = const Color(0xFF881337);
        _currentTemplate.borderWidth = 2.5;
        for (final el in _currentTemplate.elements) {
          if (el.type == DesignerElementType.table) {
            el.tableConfig?['headerBg'] = 0xFF881337;
            el.tableConfig?['headerTextColor'] = 0xFFFFFFFF;
            el.tableConfig?['gridColor'] = 0xFFFDA4AF;
          }
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Theme "$themeName" applied!'), backgroundColor: const Color(0xFF0F766E)),
    );
  }

  // ── Element Management ──

  void _addNewElement(DesignerElementType type, {String? tokenKey, String? defaultText, Map<String, dynamic>? tableCfg}) {
    final id = 'elem_${DateTime.now().millisecondsSinceEpoch}';
    double w = 0.35;
    double h = 0.08;
    double x = 0.32;
    double y = 0.45;
    String text = defaultText ?? type.label;

    if (tokenKey != null) {
      final token = SampleDocumentData.allTokens.firstWhere(
        (t) => t.key == tokenKey,
        orElse: () => SampleDocumentData.allTokens.first,
      );
      text = token.labelUr;
    }

    if (type == DesignerElementType.photo) {
      w = 0.28;
      h = 0.24;
      text = 'Photo';
    } else if (type == DesignerElementType.qrCode) {
      w = 0.20;
      h = 0.20;
      text = '{{student.gr_no}}';
    } else if (type == DesignerElementType.barcode) {
      w = 0.45;
      h = 0.12;
      text = '1045268';
    } else if (type == DesignerElementType.table) {
      w = 0.90;
      h = 0.45;
      x = 0.05;
      y = 0.32;
      text = 'Smart Table';
    } else if (type == DesignerElementType.gradingScale) {
      w = 0.40;
      h = 0.18;
      x = 0.06;
      y = 0.76;
      text = 'Grading Scale';
    } else if (type == DesignerElementType.signature || type == DesignerElementType.stamp) {
      w = 0.25;
      h = 0.12;
      text = type == DesignerElementType.signature ? 'Authorized Signature' : 'Official Seal';
    } else if (type == DesignerElementType.dividerLine) {
      w = 0.90;
      h = 0.01;
      x = 0.05;
    }

    final newEl = DesignerElement(
      id: id,
      type: type,
      side: _activeSide,
      xRatio: x,
      yRatio: y,
      widthRatio: w,
      heightRatio: h,
      label: tokenKey != null ? SampleDocumentData.allTokens.firstWhere((t) => t.key == tokenKey).labelEn : text,
      text: text,
      tokenKey: tokenKey,
      tableConfig: tableCfg,
      zIndex: _currentTemplate.elements.length,
    );

    setState(() {
      _currentTemplate.elements.add(newEl);
      _selectedElementId = id;
      if (type == DesignerElementType.table) {
        _rightPanelTabIndex = 1;
      } else {
        _rightPanelTabIndex = 0;
      }
    });
  }

  void _duplicateElement(DesignerElement el) {
    final dup = el.copyWith(
      id: 'elem_${DateTime.now().millisecondsSinceEpoch}',
      xRatio: (el.xRatio + 0.03).clamp(0.0, 0.9),
      yRatio: (el.yRatio + 0.03).clamp(0.0, 0.9),
      zIndex: _currentTemplate.elements.length,
    );
    setState(() {
      _currentTemplate.elements.add(dup);
      _selectedElementId = dup.id;
    });
  }

  void _deleteElement(String id) {
    setState(() {
      _currentTemplate.elements.removeWhere((e) => e.id == id);
      if (_selectedElementId == id) _selectedElementId = null;
    });
  }

  void _autoFitElement(DesignerElement el) {
    final len = max(el.text.length, 6);
    setState(() {
      el.widthRatio = (len * 0.025).clamp(0.15, 0.95);
      el.heightRatio = (el.fontSize * 0.0035).clamp(0.04, 0.30);
    });
  }

  void _reorderElement(DesignerElement el, bool bringForward) {
    setState(() {
      if (bringForward) {
        el.zIndex += 2;
      } else {
        el.zIndex = max(0, el.zIndex - 2);
      }
    });
  }

  // ── JSON Template Export & Import ──

  Future<void> _exportTemplateJson() async {
    try {
      final jsonStr = jsonEncode(_currentTemplate.toJson());
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Template JSON',
        fileName: '${_currentTemplate.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (savePath != null) {
        final f = File(savePath);
        await f.writeAsString(jsonStr, encoding: utf8);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Template JSON exported successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _importTemplateJson() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (res != null && res.files.single.path != null) {
        final f = File(res.files.single.path!);
        final jsonStr = await f.readAsString(encoding: utf8);
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        final imported = DesignerTemplate.fromJson(data);
        setState(() {
          _currentTemplate = imported;
          _selectedElementId = null;
        });
        await _saveTemplate();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Template "${imported.name}" imported successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── Template Uploads ──

  Future<void> _pickBackgroundTemplate() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (res != null && res.files.single.path != null) {
      final path = res.files.single.path!;
      setState(() {
        if (_activeSide == 'front') {
          _currentTemplate.backgroundImageFrontPath = path;
          _currentTemplate.useFrontTemplate = true;
        } else {
          _currentTemplate.backgroundImageBackPath = path;
          _currentTemplate.useBackTemplate = true;
        }
      });
    }
  }

  void _removeBackgroundTemplate() {
    setState(() {
      if (_activeSide == 'front') {
        _currentTemplate.backgroundImageFrontPath = null;
        _currentTemplate.useFrontTemplate = false;
      } else {
        _currentTemplate.backgroundImageBackPath = null;
        _currentTemplate.useBackTemplate = false;
      }
    });
  }

  // ── Template Save / Load ──

  Future<void> _saveTemplate() async {
    setState(() => _isSaving = true);
    await _repository.saveTemplate(_currentTemplate);
    await _loadAllTemplates();
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template "${_currentTemplate.name}" saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _openSaveAsDialog() {
    final ctrl = TextEditingController(text: '${_currentTemplate.name} (Copy)');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Design Template As', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Template Name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(ctx);
                final newTmpl = _currentTemplate.copyWith(
                  id: 'tmpl_${DateTime.now().millisecondsSinceEpoch}',
                  name: newName,
                );
                setState(() => _currentTemplate = newTmpl);
                await _saveTemplate();
              }
            },
            child: const Text('Save Template', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openLoadTemplateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Readymade or Saved Template', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SizedBox(
          width: min(520.0, MediaQuery.of(context).size.width - 48),
          height: min(420.0, MediaQuery.of(context).size.height - 120),
          child: ListView.builder(
            itemCount: _allTemplates.length,
            itemBuilder: (context, idx) {
              final tmpl = _allTemplates[idx];
              final isCurrent = tmpl.id == _currentTemplate.id;
              return ListTile(
                leading: Icon(tmpl.documentType.icon, color: const Color(0xFF0F766E)),
                title: Text(tmpl.name, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text('${tmpl.documentType.labelEn} • ${tmpl.widthMm.toInt()}x${tmpl.heightMm.toInt()}mm'),
                trailing: isCurrent ? const Icon(Icons.check_circle, color: Colors.green) : null,
                onTap: () {
                  setState(() {
                    _currentTemplate = tmpl.copyWith();
                    _selectedElementId = null;
                  });
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // ── Record Switcher Actions ──

  void _nextStudent() {
    final filtered = _effectiveStudents;
    if (filtered.isEmpty) return;
    setState(() {
      _currentRecordIndex = (_currentRecordIndex + 1) % filtered.length;
    });
  }

  void _prevStudent() {
    final filtered = _effectiveStudents;
    if (filtered.isEmpty) return;
    setState(() {
      _currentRecordIndex = (_currentRecordIndex - 1 + filtered.length) % filtered.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // ── 1. Top Unified Studio Header ──
          _buildStudioHeader(isDark),

          // ── 2. Secondary Context Toolbar ──
          _buildSecondaryToolbar(isDark),

          // ── 3. Main Workspace ──
          Expanded(
            child: Row(
              children: [
                // Contextual Left Toolbox Panel with 3 Tabs
                _buildLeftToolboxTabs(isDark),

                // Center Interactive Canvas Area
                Expanded(
                  child: _buildCanvasArea(isDark),
                ),

                // Right Properties Inspector / Table Studio Panel
                _buildRightPanelWithTabs(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 1. Studio Header
  // ─────────────────────────────────────────────────────────────
  Widget _buildStudioHeader(bool isDark) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF0D5C3A), Color(0xFF0F766E)]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.palette_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Universal Card & Document Studio',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                          ),
                          Text(
                            'ID Cards, Result Cards, Certificates, Receipts & Bills Designer',
                            style: TextStyle(fontSize: 10.5, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                          ),
                        ],
                      ),

                      const SizedBox(width: 16),
                      const SizedBox(height: 36, child: VerticalDivider(indent: 6, endIndent: 6)),
                      const SizedBox(width: 12),

                      // Document Type Selector
                      DropdownButtonHideUnderline(
                        child: DropdownButton<DocumentType>(
                          value: _currentTemplate.documentType,
                          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          items: DocumentType.values.map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(type.icon, size: 16, color: const Color(0xFF0F766E)),
                                  const SizedBox(width: 8),
                                  Text(type.labelEn, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) _switchDocumentType(v);
                          },
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Paper Preset Selector
                      DropdownButtonHideUnderline(
                        child: DropdownButton<CanvasPreset>(
                          value: _currentTemplate.preset,
                          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          items: CanvasPreset.values.map((p) {
                            return DropdownMenuItem(
                              value: p,
                              child: Text(p.label, style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) _switchPreset(v);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 20),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Template Manager Buttons
                      OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        label: const Text('Templates', style: TextStyle(fontSize: 12)),
                        onPressed: _openLoadTemplateDialog,
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.save_as_rounded, size: 16),
                        label: const Text('Save As', style: TextStyle(fontSize: 12)),
                        onPressed: _openSaveAsDialog,
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D5C3A)),
                        icon: const Icon(Icons.save_rounded, size: 16, color: Colors.white),
                        label: Text(_isSaving ? 'Saving...' : 'Save', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: _isSaving ? null : _saveTemplate,
                      ),

                      const SizedBox(width: 12),
                      const SizedBox(height: 36, child: VerticalDivider(indent: 6, endIndent: 6)),
                      const SizedBox(width: 12),

                      // Direct Print
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                        icon: const Icon(Icons.print_rounded, size: 16, color: Colors.white),
                        label: const Text('Print', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => UniversalPdfExporter.printDirectly(context, _currentTemplate, dynamicData: _currentTokens),
                      ),
                      const SizedBox(width: 8),

                      // Entire Class Batch Print
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                        icon: const Icon(Icons.groups_rounded, size: 16, color: Colors.white),
                        label: const Text('Class Batch Print', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          final records = _effectiveStudents.map((s) => s.toTokensMap()).toList();
                          UniversalPdfExporter.printClassBatchDirectly(context, _currentTemplate, records);
                        },
                      ),
                      const SizedBox(width: 8),

                      // Export PDF
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Colors.white),
                        label: const Text('Export PDF', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => UniversalPdfExporter.exportAndSavePdf(context, _currentTemplate, dynamicData: _currentTokens),
                      ),
                      if (_currentTemplate.documentType == DocumentType.studentIdCard || _currentTemplate.documentType == DocumentType.libraryCard) ...[
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
                          icon: const Icon(Icons.grid_view_rounded, size: 16, color: Colors.white),
                          label: const Text('Bulk Sheet (8/A4)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            final records = _effectiveStudents.map((s) => s.toTokensMap()).toList();
                            UniversalPdfExporter.printBulkGridDirectly(context, _currentTemplate, records);
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 2. Secondary Toolbar
  // ─────────────────────────────────────────────────────────────
  Widget _buildSecondaryToolbar(bool isDark) {
    final s = _currentStudent;
    final totalRecords = _effectiveStudents.length;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withAlpha(180) : Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _sideTab('front', 'Front Side (سامنے کا رخ)', Icons.flip_to_front_rounded),
                            _sideTab('back', 'Back Side (پچھلا رخ)', Icons.flip_to_back_rounded),
                          ],
                        ),
                      ),

                      const SizedBox(width: 14),
                      const SizedBox(height: 24, child: VerticalDivider(indent: 4, endIndent: 4)),
                      const SizedBox(width: 14),

                      // Class Filter Dropdown
                      const Text('Class: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedClass,
                          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          items: _availableClasses.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (v) {
                            if (v != null) _filterByClass(v);
                          },
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Record Switcher
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: _prevStudent,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF0F766E).withAlpha(40)),
                        ),
                        child: Text(
                          s != null
                              ? '${s.fullName} (${s.grNo ?? 'No GR'}) [${_currentRecordIndex + 1}/$totalRecords]'
                              : 'Sample Preview Data',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: _nextStudent,
                      ),
                    ],
                  ),

                  const SizedBox(width: 16),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Grid & Snap toggles
                      IconButton(
                        icon: Icon(_showGrid ? Icons.grid_on_rounded : Icons.grid_off_rounded, size: 18),
                        color: _showGrid ? const Color(0xFF0F766E) : Colors.grey,
                        tooltip: 'Toggle Grid',
                        onPressed: () => setState(() => _showGrid = !_showGrid),
                      ),
                      IconButton(
                        icon: Icon(_snapToGrid ? Icons.straighten_rounded : Icons.square_foot_rounded, size: 18),
                        color: _snapToGrid ? const Color(0xFF0F766E) : Colors.grey,
                        tooltip: 'Snap to Grid',
                        onPressed: () => setState(() => _snapToGrid = !_snapToGrid),
                      ),

                      const SizedBox(width: 8),

                      // Zoom Controls
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                        onPressed: () => setState(() => _zoomScale = (_zoomScale - 0.1).clamp(0.5, 2.5)),
                      ),
                      Text('${(_zoomScale * 100).toInt()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                        onPressed: () => setState(() => _zoomScale = (_zoomScale + 0.1).clamp(0.5, 2.5)),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _zoomScale = 1.0),
                        child: const Text('Reset', style: TextStyle(fontSize: 11)),
                      ),

                      const SizedBox(width: 12),

                      // Live Preview Toggle
                      FilterChip(
                        selected: _isPreviewMode,
                        label: Text(_isPreviewMode ? 'Preview Mode' : 'Edit Mode', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        onSelected: (val) => setState(() => _isPreviewMode = val),
                        selectedColor: const Color(0xFF0F766E).withAlpha(50),
                        checkmarkColor: const Color(0xFF0F766E),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sideTab(String side, String label, IconData icon) {
    final isSel = _activeSide == side;
    return InkWell(
      onTap: () => setState(() => _activeSide = side),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF0F766E) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSel ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, color: isSel ? Colors.white : null)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 3. Left Panel with 3 Tabs: Tools | Page Setup | Themes & JSON
  // ─────────────────────────────────────────────────────────────
  Widget _buildLeftToolboxTabs(bool isDark) {
    return Container(
      width: 295,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(right: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                _toolboxSubTab(0, 'Tools', Icons.widgets_rounded),
                _toolboxSubTab(1, 'Page Setup', Icons.tune_rounded),
                _toolboxSubTab(2, 'Themes & JSON', Icons.style_rounded),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _leftPanelTabIndex,
              children: [
                _buildToolsTab(isDark),
                _buildPageSetupTab(isDark),
                _buildThemesAndJsonTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolboxSubTab(int index, String label, IconData icon) {
    final isSel = _leftPanelTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _leftPanelTabIndex = index),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSel ? const Color(0xFF0F766E) : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: isSel ? const Color(0xFF0F766E) : Colors.grey),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    color: isSel ? const Color(0xFF0F766E) : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sub-Tab 1: Context-Aware Tools ──
  Widget _buildToolsTab(bool isDark) {
    final type = _currentTemplate.documentType;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (type == DocumentType.resultCard) ...[
          _sectionTitle('📊 Result Card & Marksheet Tools'),
          const SizedBox(height: 6),
          _toolButton('بِسْمِ اللَّهِ Calligraphy', Icons.auto_awesome, () => _addNewElement(DesignerElementType.text, defaultText: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ')),
          _toolButton('Examination Title (امتحان)', Icons.title_rounded, () => _addNewElement(DesignerElementType.text, defaultText: 'کشف الدرجات برائے سالانہ امتحان')),
          _toolButton('Academic Session (تعلیمی سال)', Icons.event_note_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{exam.session}}')),
          _toolButton('Marks Table 1 (جدول سالانہ)', Icons.table_chart_rounded, () => _addResultMarksTable('سالانہ امتحان', 1)),
          _toolButton('Marks Table 2 (جدول ششماہی)', Icons.table_rows_rounded, () => _addResultMarksTable('ششماہی امتحان', 2)),
          _toolButton('Match Table 2 with Table 1', Icons.sync_alt_rounded, _matchTable2WithSizeOfTable1),
          _toolButton('Grading Scale Box (پیمانہ درجات)', Icons.auto_graph_rounded, () => _addNewElement(DesignerElementType.gradingScale)),
          _toolButton('Total Marks & Percentage Badge', Icons.percent_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{exam.obtained_marks}}')),
          _toolButton('Overall Grade (ممتاز / جید)', Icons.grade_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{exam.grade}}')),
          _toolButton('Position / Rank Badge (#1, #2)', Icons.emoji_events_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{exam.rank}}')),
          _toolButton('Result Status Badge (ناجح / راسب)', Icons.verified_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{exam.result_status}}')),
          _toolButton('Head Examiner Signature', Icons.draw_rounded, () => _addNewElement(DesignerElementType.signature, defaultText: 'دستخط ممتحن اعلیٰ')),
          _toolButton('Nazim / Principal Signature', Icons.edit_rounded, () => _addNewElement(DesignerElementType.signature, defaultText: 'دستخط ناظم / مہتمم')),
          _toolButton('Official Madarsa Stamp / Seal', Icons.verified_rounded, () => _addNewElement(DesignerElementType.stamp, defaultText: 'مہر جامعہ')),
        ] else if (type == DocumentType.studentIdCard) ...[
          _sectionTitle('🪪 Student ID Card Tools'),
          const SizedBox(height: 6),
          _toolButton('Student Photo (Circle/Square)', Icons.account_box_rounded, () => _addNewElement(DesignerElementType.photo)),
          _toolButton('Student QR Code (کیو آر)', Icons.qr_code_rounded, () => _addNewElement(DesignerElementType.qrCode)),
          _toolButton('Student Barcode (بارکوڈ)', Icons.view_column_rounded, () => _addNewElement(DesignerElementType.barcode)),
          _toolButton('Student Full Name (مکمل نام)', Icons.badge_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.combined_name}}')),
          _toolButton('GR Number (جی آر نمبر)', Icons.pin_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.gr_no}}')),
          _toolButton('Class / Darja (درجہ)', Icons.school_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.class_name}}')),
          _toolButton('Roll Number (رول نمبر)', Icons.format_list_numbered_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.roll_no}}')),
          _toolButton('Date of Birth (تاریخ پیدائش)', Icons.cake_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.dob}}')),
          _toolButton('Combined Address (مکمل پتہ)', Icons.location_on_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.combined_address}}')),
          _toolButton('Emergency Mobile (فون)', Icons.phone_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.phone}}')),
          _toolButton('Attendance & Fee Table (Back Side)', Icons.table_chart_rounded, _addStudentAttendanceTable),
          _toolButton('Madarsa Rules (Back Side)', Icons.rule_folder_rounded, () => _addNewElement(DesignerElementType.text, defaultText: 'قوانین و ضوابط:\n۱. کارڈ ساتھ رکھنا لازمی ہے۔\n۲. گمشدگی پر دفتر رجوع کریں۔')),
          _toolButton('Principal Signature', Icons.draw_rounded, () => _addNewElement(DesignerElementType.signature, defaultText: 'دستخط مہتمم')),
          _toolButton('Official Seal / Stamp', Icons.verified_rounded, () => _addNewElement(DesignerElementType.stamp, defaultText: 'مہر ادارہ')),
        ] else if (type == DocumentType.staffIdCard) ...[
          _sectionTitle('👔 Staff ID Card Tools'),
          const SizedBox(height: 6),
          _toolButton('Staff Photo', Icons.account_box_rounded, () => _addNewElement(DesignerElementType.photo)),
          _toolButton('Staff Full Name', Icons.badge_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{staff.name}}')),
          _toolButton('Designation (عہدہ)', Icons.work_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{staff.designation}}')),
          _toolButton('Department (شعبہ)', Icons.business_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{staff.department}}')),
          _toolButton('Employee ID (آئی ڈی)', Icons.pin_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{staff.employee_id}}')),
          _toolButton('Staff Phone (موبائل)', Icons.phone_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{staff.phone}}')),
          _toolButton('Assigned Schedule Table', Icons.table_chart_rounded, _addStaffScheduleTable),
          _toolButton('Staff QR Code', Icons.qr_code_rounded, () => _addNewElement(DesignerElementType.qrCode)),
          _toolButton('Authorized Signature', Icons.draw_rounded, () => _addNewElement(DesignerElementType.signature, defaultText: 'دستخط مجاز')),
        ] else if (type == DocumentType.certificate) ...[
          _sectionTitle('📜 Sanad & Certificate Tools'),
          const SizedBox(height: 6),
          _toolButton('بِسْمِ اللَّهِ Calligraphy', Icons.auto_awesome, () => _addNewElement(DesignerElementType.text, defaultText: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ')),
          _toolButton('Certificate Heading (سند الفراغ)', Icons.workspace_premium_rounded, () => _addNewElement(DesignerElementType.text, defaultText: 'سند الفراغ و شہادت العالمیہ')),
          _toolButton('Sanad Body Text (متن سند)', Icons.article_rounded, () => _addNewElement(DesignerElementType.text, defaultText: 'تصدیق کی جاتی ہے کہ مسمی {{student.name}} ولد {{student.father_name}} نے جامعہ ہذا سے درجہ {{student.class_name}} کا امتحان کامیابی کے ساتھ مکمل کیا...')),
          _toolButton('Sanad Academic Marks Table', Icons.table_chart_rounded, _addSanadAcademicTable),
          _toolButton('Student Full Name', Icons.person_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.combined_name}}')),
          _toolButton('Father Name (ولدیت)', Icons.person_outline_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.father_name}}')),
          _toolButton('Hijri Date (تاریخ ہجری)', Icons.calendar_today_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{card.hijri_date}}')),
          _toolButton('Certificate Serial No.', Icons.tag_rounded, () => _addNewElement(DesignerElementType.text, defaultText: 'سند نمبر: SND-2026/786')),
          _toolButton('Nazim / Mohtamim Signature', Icons.draw_rounded, () => _addNewElement(DesignerElementType.signature, defaultText: 'دستخط مہتمم')),
          _toolButton('Sadar Mudarris Signature', Icons.edit_rounded, () => _addNewElement(DesignerElementType.signature, defaultText: 'دستخط صدر المدرسین')),
          _toolButton('Golden Official Seal', Icons.verified_rounded, () => _addNewElement(DesignerElementType.stamp, defaultText: 'مہر خاص')),
        ] else if (type == DocumentType.feeReceipt) ...[
          _sectionTitle('🧾 Fee Receipt Tools'),
          const SizedBox(height: 6),
          _toolButton('Receipt No. (رسید نمبر)', Icons.tag_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{fee.receipt_no}}')),
          _toolButton('Payment Date (تاریخ)', Icons.calendar_today_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{card.date}}')),
          _toolButton('Student Name & GR', Icons.badge_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.name}}')),
          _toolButton('Fee Breakdown Table (جدول فیس)', Icons.table_chart_rounded, _addFeeBreakdownTable),
          _toolButton('Total Paid Amount (رقم)', Icons.payments_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{fee.amount}}')),
          _toolButton('Amount in Words (بلفظ)', Icons.text_fields_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{fee.amount_words}}')),
          _toolButton('Payment Mode (نقد / آن لائن)', Icons.credit_card_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{fee.payment_mode}}')),
          _toolButton('Receiver Signature (وصول کنندہ)', Icons.draw_rounded, () => _addNewElement(DesignerElementType.signature, defaultText: 'دستخط وصول کنندہ')),
        ] else if (type == DocumentType.purchaseBill) ...[
          _sectionTitle('🛒 Sale & Purchase Bill Tools'),
          const SizedBox(height: 6),
          _toolButton('Invoice / Bill No.', Icons.receipt_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{bill.invoice_no}}')),
          _toolButton('Bill Date (تاریخ)', Icons.calendar_today_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{card.date}}')),
          _toolButton('Vendor / Party Name (نام فریق)', Icons.business_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{bill.supplier_name}}')),
          _toolButton('Items & Quantity Table (جدول اشیاء)', Icons.table_chart_rounded, _addPurchaseItemsTable),
          _toolButton('Grand Total Amount', Icons.monetization_on_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{bill.total_amount}}')),
          _toolButton('Authorized Signature', Icons.draw_rounded, () => _addNewElement(DesignerElementType.signature, defaultText: 'دستخط مجاز')),
          _toolButton('Official Paid Stamp', Icons.verified_rounded, () => _addNewElement(DesignerElementType.stamp, defaultText: 'PAID / ادا شدہ')),
        ] else if (type == DocumentType.libraryCard) ...[
          _sectionTitle('📚 Library Ticket Tools'),
          const SizedBox(height: 6),
          _toolButton('Member ID / Card No.', Icons.card_membership_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{library.card_no}}')),
          _toolButton('Student Name & Class', Icons.badge_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.name}}')),
          _toolButton('Barcode (بارکوڈ)', Icons.view_column_rounded, () => _addNewElement(DesignerElementType.barcode)),
          _toolButton('Book Issue Slots Table (جدول کتب)', Icons.table_chart_rounded, _addLibrarySlotsTable),
          _toolButton('Librarian Signature', Icons.draw_rounded, () => _addNewElement(DesignerElementType.signature, defaultText: 'دستخط لائبریرین')),
        ] else if (type == DocumentType.admitCard) ...[
          _sectionTitle('🎫 Exam Admit Card Tools'),
          const SizedBox(height: 6),
          _toolButton('Admit Card Title (داخلہ کارڈ)', Icons.assignment_ind_rounded, () => _addNewElement(DesignerElementType.text, defaultText: 'داخلہ کارڈ برائے سالانہ امتحان')),
          _toolButton('Student Photo', Icons.account_box_rounded, () => _addNewElement(DesignerElementType.photo)),
          _toolButton('Student Name & Father Name', Icons.badge_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.combined_name}}')),
          _toolButton('Roll No & GR No', Icons.pin_rounded, () => _addNewElement(DesignerElementType.token, tokenKey: '{{student.roll_no}}')),
          _toolButton('Exam Timetable Schedule Table', Icons.table_chart_rounded, _addAdmitCardScheduleTable),
          _toolButton('Exam Rules & Instructions', Icons.rule_folder_rounded, () => _addNewElement(DesignerElementType.text, defaultText: 'امتحانی ہدایات:\n۱. داخلہ کارڈ لانا لازمی ہے۔\n۲. وقت مقررہ پر حاضر ہوں۔')),
          _toolButton('Exam Controller Signature', Icons.draw_rounded, () => _addNewElement(DesignerElementType.signature, defaultText: 'دستخط ناظم امتحانات')),
        ] else ...[
          _sectionTitle('📄 Document Tools'),
          const SizedBox(height: 6),
          _toolButton('Insert Smart Data Table', Icons.table_chart_rounded, () => _addResultMarksTable('تفصیلات', 1)),
        ],

        const Divider(height: 16),
        _sectionTitle('Universal Elements (All Cards)'),
        const SizedBox(height: 6),
        _toolButton('Insert Smart Data Table', Icons.table_chart_rounded, () => _addResultMarksTable('جدول', 1)),
        _toolButton('Custom Static Text', Icons.text_fields_rounded, () => _addNewElement(DesignerElementType.text, defaultText: 'نیا متن درج کریں')),
        _toolButton('Divider Line (لکیر)', Icons.horizontal_rule_rounded, () => _addNewElement(DesignerElementType.dividerLine)),
        _toolButton('Shape Box (چوکھٹ)', Icons.crop_square_rounded, () => _addNewElement(DesignerElementType.shape)),

        const Divider(height: 16),
        _sectionTitle('Active Elements Tree (${_currentTemplate.elements.where((e) => e.side == _activeSide).length})'),
        const SizedBox(height: 6),

        ..._currentTemplate.elements.where((e) => e.side == _activeSide).map((el) {
          final isSel = el.id == _selectedElementId;
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: isSel ? const Color(0xFF0F766E).withAlpha(30) : null,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isSel ? const Color(0xFF0F766E) : Colors.transparent),
            ),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(el.type.icon, size: 16, color: isSel ? const Color(0xFF0F766E) : Colors.grey),
              title: Text(el.label.isNotEmpty ? el.label : el.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(el.isVisible ? Icons.visibility : Icons.visibility_off, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () => setState(() => el.isVisible = !el.isVisible),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () => _deleteElement(el.id),
                  ),
                ],
              ),
              onTap: () {
                setState(() {
                  _selectedElementId = el.id;
                  if (el.type == DesignerElementType.table) {
                    _rightPanelTabIndex = 1;
                  } else {
                    _rightPanelTabIndex = 0;
                  }
                });
              },
            ),
          );
        }),
      ],
    );
  }

  // ── Sub-Tab 2: Global Page Setup & Stationary ──
  Widget _buildPageSetupTab(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('🌐 Language & Script Options'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _currentTemplate.cardLanguage,
          decoration: const InputDecoration(labelText: 'Card Language', isDense: true, border: OutlineInputBorder()),
          items: UrduNumberHelper.supportedCardLanguages.map((l) {
            return DropdownMenuItem(value: l['code'], child: Text(l['name']!));
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _currentTemplate.cardLanguage = v);
          },
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Convert Digits to Urdu (۱۲۳۴)', style: TextStyle(fontSize: 11.5)),
          value: _currentTemplate.convertDigits,
          onChanged: (v) => setState(() => _currentTemplate.convertDigits = v),
        ),

        const Divider(height: 16),
        _sectionTitle('📄 Paper & Transparency (Pre-Printed)'),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Transparent Page BG (Pre-Printed Stationary)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          subtitle: const Text('Hides borders & white fill for pre-printed papers', style: TextStyle(fontSize: 9.5, color: Colors.grey)),
          value: _currentTemplate.isTransparentPageBg,
          onChanged: (v) => setState(() => _currentTemplate.isTransparentPageBg = v),
        ),

        const SizedBox(height: 8),
        _sectionTitle('Background Images (Letterhead)'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8)),
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: Text(_activeSide == 'front' ? 'Upload Front' : 'Upload Back', style: const TextStyle(fontSize: 11)),
                onPressed: _pickBackgroundTemplate,
              ),
            ),
            if ((_activeSide == 'front' && _currentTemplate.backgroundImageFrontPath != null) ||
                (_activeSide == 'back' && _currentTemplate.backgroundImageBackPath != null))
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.red, size: 18),
                onPressed: _removeBackgroundTemplate,
              ),
          ],
        ),

        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _colorPickerTile('BG Color 1', _currentTemplate.backgroundColor, (c) {
                setState(() => _currentTemplate.backgroundColor = c);
              }),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _colorPickerTile('BG Color 2', _currentTemplate.backgroundColor2, (c) {
                setState(() => _currentTemplate.backgroundColor2 = c);
              }),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Gradient Background', style: TextStyle(fontSize: 11.5)),
          value: _currentTemplate.isGradient,
          onChanged: (v) => setState(() => _currentTemplate.isGradient = v),
        ),

        const Divider(height: 16),
        _sectionTitle('Card Frame & Borders'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _colorPickerTile('Border Color', _currentTemplate.borderColor, (c) {
                setState(() => _currentTemplate.borderColor = c);
              }),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextFormField(
                key: ValueKey('bw_${_currentTemplate.id}'),
                initialValue: _currentTemplate.borderWidth.toString(),
                decoration: const InputDecoration(labelText: 'Border (mm)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _currentTemplate.borderWidth = double.tryParse(v) ?? 0.0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('br_${_currentTemplate.id}'),
                initialValue: _currentTemplate.borderRadius.toString(),
                decoration: const InputDecoration(labelText: 'Corner Radius', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _currentTemplate.borderRadius = double.tryParse(v) ?? 8.0),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextFormField(
                initialValue: _snapStepMm.toString(),
                decoration: const InputDecoration(labelText: 'Grid Snap (mm)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _snapStepMm = double.tryParse(v) ?? 10.0),
              ),
            ),
          ],
        ),

        const Divider(height: 16),
        _sectionTitle('Issue Dates (Hijri & Gregorian)'),
        const SizedBox(height: 6),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_month_rounded, color: Color(0xFF0F766E)),
          title: Text('${_issueDate.day}/${_issueDate.month}/${_issueDate.year}'),
          subtitle: Text('${_hijriDate.hDay} ${_hijriDate.longMonthName} ${_hijriDate.hYear}ھ', style: const TextStyle(fontFamily: 'Jameel Noori Nastaleeq', fontSize: 11)),
          trailing: OutlinedButton(
            child: const Text('Change Date', style: TextStyle(fontSize: 10)),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _issueDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() {
                  _issueDate = picked;
                  _hijriDate = HijriCalendar.fromDate(picked);
                });
              }
            },
          ),
        ),
      ],
    );
  }

  // ── Sub-Tab 3: Signature Themes & JSON Import/Export ──
  Widget _buildThemesAndJsonTab(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('🎨 1-Click Signature Themes'),
        const SizedBox(height: 8),
        _themeCard('Golden Amber Royal', 'Gold border with dark emerald table', const Color(0xFFD97706), const Color(0xFF0D5C3A)),
        _themeCard('Executive Sapphire Navy', 'Navy blue border with sky blue highlights', const Color(0xFF1E3A8A), const Color(0xFF0284C7)),
        _themeCard('Crimson Ruby Gold', 'Crimson border with rose gold table', const Color(0xFF881337), const Color(0xFFBE123C)),

        const Divider(height: 20),
        _sectionTitle('💾 Template JSON Backup & Restore'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E), padding: const EdgeInsets.symmetric(vertical: 10)),
                icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                label: const Text('Export JSON', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                onPressed: _exportTemplateJson,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), padding: const EdgeInsets.symmetric(vertical: 10)),
                icon: const Icon(Icons.upload_rounded, size: 16, color: Colors.white),
                label: const Text('Import JSON', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                onPressed: _importTemplateJson,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _themeCard(String name, String desc, Color c1, Color c2) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c1.withAlpha(120))),
      child: ListTile(
        leading: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [c1, c2]), shape: BoxShape.circle),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        subtitle: Text(desc, style: const TextStyle(fontSize: 10)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12),
        onTap: () => _applyTheme(name),
      ),
    );
  }

  // ── Table Presets for All Cards ──

  void _addResultMarksTable(String title, int tableGroup) {
    _addNewElement(
      DesignerElementType.table,
      tableCfg: {
        'title': title,
        'tableType': 'marksheet',
        'tableGroup': tableGroup,
        'subjects': [
          {'name': 'القرآن الكريم والتجويد', 'max': 100, 'pass': 33, 'obtained': 95, 'grade': 'ممتاز', 'isAbsent': false},
          {'name': 'الحديث الشريف وأصوله', 'max': 100, 'pass': 33, 'obtained': 88, 'grade': 'جید جداً', 'isAbsent': false},
          {'name': 'الفقه الإسلامي وأصوله', 'max': 100, 'pass': 33, 'obtained': 82, 'grade': 'جید جداً', 'isAbsent': false},
          {'name': 'قواعد اللغة العربية والنحو', 'max': 100, 'pass': 33, 'obtained': 78, 'grade': 'جید', 'isAbsent': false},
          {'name': 'الأدب العربي والإنشاء', 'max': 100, 'pass': 33, 'obtained': 85, 'grade': 'جید جداً', 'isAbsent': false},
          {'name': 'العقائد الإسلامية والتوحيد', 'max': 100, 'pass': 33, 'obtained': 90, 'grade': 'ممتاز', 'isAbsent': false},
        ],
        'columns': [
          {'id': 'col1', 'title': 'نمبر شمار', 'width': 30.0, 'align': 'center', 'visible': true},
          {'id': 'col2', 'title': 'کتاب کا نام / مضمون', 'width': 90.0, 'align': 'right', 'visible': true},
          {'id': 'col3', 'title': 'کل نمبر', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col4', 'title': 'کامیابی', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col5', 'title': 'حاصل نمبر', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col6', 'title': 'کیفیت / گریڈ', 'width': 45.0, 'align': 'center', 'visible': true},
        ],
        'scale': 1.0,
        'headerBg': 0xFF0D5C3A,
        'headerTextColor': 0xFFFFFFFF,
        'rowTextColor': 0xFF000000,
        'gridColor': 0xFFCCCCCC,
        'gridWidth': 1.0,
        'alternateRowColors': true,
        'transparentHeader': false,
        'transparentRows': false,
        'altRowBg': 0xFFF8FAFC,
      },
    );
  }

  void _addStudentAttendanceTable() {
    _addNewElement(
      DesignerElementType.table,
      tableCfg: {
        'title': 'Student Attendance & Record Table',
        'tableType': 'attendance',
        'subjects': [
          {'name': 'ماہ شوال المکرم', 'max': 30, 'pass': 25, 'obtained': 28, 'grade': 'حاضر', 'isAbsent': false},
          {'name': 'ماہ ذی القعدہ', 'max': 30, 'pass': 25, 'obtained': 29, 'grade': 'حاضر', 'isAbsent': false},
          {'name': 'ماہ ذی الحجہ', 'max': 30, 'pass': 25, 'obtained': 27, 'grade': 'حاضر', 'isAbsent': false},
          {'name': 'ماہ محرم الحرام', 'max': 30, 'pass': 25, 'obtained': 30, 'grade': 'ممتاز', 'isAbsent': false},
        ],
        'columns': [
          {'id': 'col1', 'title': 'شمار', 'width': 25.0, 'align': 'center', 'visible': true},
          {'id': 'col2', 'title': 'ماہ / تعلیمی مدت', 'width': 95.0, 'align': 'right', 'visible': true},
          {'id': 'col3', 'title': 'کل ایام', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col4', 'title': 'لازمی', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col5', 'title': 'حاضری', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col6', 'title': 'کیفیت', 'width': 35.0, 'align': 'center', 'visible': true},
        ],
        'scale': 1.0,
        'headerBg': 0xFF0F766E,
        'headerTextColor': 0xFFFFFFFF,
        'rowTextColor': 0xFF000000,
        'gridColor': 0xFFCCCCCC,
        'alternateRowColors': true,
        'transparentHeader': false,
        'transparentRows': false,
        'altRowBg': 0xFFF0FDFA,
      },
    );
  }

  void _addStaffScheduleTable() {
    _addNewElement(
      DesignerElementType.table,
      tableCfg: {
        'title': 'Staff Assigned Schedule Table',
        'tableType': 'staffSchedule',
        'subjects': [
          {'name': 'درجہ اولیٰ (نحو و صرف)', 'max': 1, 'pass': 0, 'obtained': 1, 'grade': 'پیریڈ ۱', 'isAbsent': false},
          {'name': 'درجہ ثانیہ (فقہ و ادب)', 'max': 2, 'pass': 0, 'obtained': 2, 'grade': 'پیریڈ ۲', 'isAbsent': false},
          {'name': 'درجہ ثالثہ (اصول الشاشی)', 'max': 3, 'pass': 0, 'obtained': 3, 'grade': 'پیریڈ ۳', 'isAbsent': false},
          {'name': 'شعبہ حفظ و تجوید', 'max': 4, 'pass': 0, 'obtained': 4, 'grade': 'پیریڈ ۴', 'isAbsent': false},
        ],
        'columns': [
          {'id': 'col1', 'title': 'شمار', 'width': 25.0, 'align': 'center', 'visible': true},
          {'id': 'col2', 'title': 'کلاس / مضمون', 'width': 100.0, 'align': 'right', 'visible': true},
          {'id': 'col3', 'title': 'گھنٹی', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col4', 'title': 'کمرہ', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col5', 'title': 'وقت', 'width': 45.0, 'align': 'center', 'visible': true},
          {'id': 'col6', 'title': 'نوبت', 'width': 35.0, 'align': 'center', 'visible': true},
        ],
        'scale': 1.0,
        'headerBg': 0xFF1E3A8A,
        'headerTextColor': 0xFFFFFFFF,
        'rowTextColor': 0xFF000000,
        'gridColor': 0xFFCCCCCC,
        'alternateRowColors': true,
        'transparentHeader': false,
        'transparentRows': false,
        'altRowBg': 0xFFEFF6FF,
      },
    );
  }

  void _addSanadAcademicTable() {
    _addNewElement(
      DesignerElementType.table,
      tableCfg: {
        'title': 'Sanad Academic Subjects Table',
        'tableType': 'sanadRecord',
        'subjects': [
          {'name': 'حفظ القرآن الکریم کاملاً', 'max': 100, 'pass': 50, 'obtained': 96, 'grade': 'ممتاز', 'isAbsent': false},
          {'name': 'علم التجوید و التدویر', 'max': 100, 'pass': 50, 'obtained': 92, 'grade': 'ممتاز', 'isAbsent': false},
          {'name': 'القراءات السبع المتواترة', 'max': 100, 'pass': 50, 'obtained': 89, 'grade': 'جید جداً', 'isAbsent': false},
          {'name': 'العلوم الدینیۃ و العربیۃ', 'max': 100, 'pass': 50, 'obtained': 94, 'grade': 'ممتاز', 'isAbsent': false},
        ],
        'columns': [
          {'id': 'col1', 'title': 'الرقم', 'width': 25.0, 'align': 'center', 'visible': true},
          {'id': 'col2', 'title': 'المادة المقررة / الفن', 'width': 105.0, 'align': 'right', 'visible': true},
          {'id': 'col3', 'title': 'الدرجة العظمى', 'width': 40.0, 'align': 'center', 'visible': true},
          {'id': 'col4', 'title': 'درجة النجاح', 'width': 40.0, 'align': 'center', 'visible': true},
          {'id': 'col5', 'title': 'الدرجة المحصلة', 'width': 40.0, 'align': 'center', 'visible': true},
          {'id': 'col6', 'title': 'التقدير العام', 'width': 40.0, 'align': 'center', 'visible': true},
        ],
        'scale': 1.0,
        'headerBg': 0xFFD97706,
        'headerTextColor': 0xFFFFFFFF,
        'rowTextColor': 0xFF000000,
        'gridColor': 0xFFD97706,
        'alternateRowColors': true,
        'transparentHeader': false,
        'transparentRows': false,
        'altRowBg': 0xFFFFFBEB,
      },
    );
  }

  void _addAdmitCardScheduleTable() {
    _addNewElement(
      DesignerElementType.table,
      tableCfg: {
        'title': 'Examination Timetable & Seating',
        'tableType': 'examSchedule',
        'subjects': [
          {'name': 'القرآن الکریم و التجوید', 'max': 100, 'pass': 33, 'obtained': 1, 'grade': 'صبح ۹ تا ۱۲', 'isAbsent': false},
          {'name': 'الحدیث الشریف و أصولہ', 'max': 100, 'pass': 33, 'obtained': 2, 'grade': 'صبح ۹ تا ۱۲', 'isAbsent': false},
          {'name': 'الفقہ الإسلامی (الہدایۃ)', 'max': 100, 'pass': 33, 'obtained': 3, 'grade': 'صبح ۹ تا ۱۲', 'isAbsent': false},
          {'name': 'قواعد اللغۃ و النحو', 'max': 100, 'pass': 33, 'obtained': 4, 'grade': 'صبح ۹ تا ۱۲', 'isAbsent': false},
        ],
        'columns': [
          {'id': 'col1', 'title': 'شمار', 'width': 25.0, 'align': 'center', 'visible': true},
          {'id': 'col2', 'title': 'امتحانی پرچہ / کتاب', 'width': 100.0, 'align': 'right', 'visible': true},
          {'id': 'col3', 'title': 'تاریخ', 'width': 45.0, 'align': 'center', 'visible': true},
          {'id': 'col4', 'title': 'دن', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col5', 'title': 'کمرہ / ہال', 'width': 40.0, 'align': 'center', 'visible': true},
          {'id': 'col6', 'title': 'دستخط نگران', 'width': 45.0, 'align': 'center', 'visible': true},
        ],
        'scale': 1.0,
        'headerBg': 0xFF0D5C3A,
        'headerTextColor': 0xFFFFFFFF,
        'rowTextColor': 0xFF000000,
        'gridColor': 0xFFCCCCCC,
        'alternateRowColors': true,
        'transparentHeader': false,
        'transparentRows': false,
        'altRowBg': 0xFFF8FAFC,
      },
    );
  }

  void _addFeeBreakdownTable() {
    _addNewElement(
      DesignerElementType.table,
      tableCfg: {
        'title': 'Fee Breakdown Table',
        'tableType': 'feeReceipt',
        'subjects': [
          {'name': 'تعلیمی فیس (Tuition Fee)', 'max': 1200, 'pass': 0, 'obtained': 1200, 'grade': 'ادا شدہ', 'isAbsent': false},
          {'name': 'خوراک و مطبخ (Mess Fee)', 'max': 2500, 'pass': 0, 'obtained': 2500, 'grade': 'ادا شدہ', 'isAbsent': false},
          {'name': 'دار الاقامہ (Hostel Fee)', 'max': 800, 'pass': 0, 'obtained': 800, 'grade': 'ادا شدہ', 'isAbsent': false},
          {'name': 'کتب و امتحانی فیس (Exam Fee)', 'max': 500, 'pass': 0, 'obtained': 500, 'grade': 'ادا شدہ', 'isAbsent': false},
        ],
        'columns': [
          {'id': 'col1', 'title': 'شمار', 'width': 25.0, 'align': 'center', 'visible': true},
          {'id': 'col2', 'title': 'تفصیل فیس (Fee Head)', 'width': 100.0, 'align': 'right', 'visible': true},
          {'id': 'col3', 'title': 'مقررہ رقم', 'width': 45.0, 'align': 'center', 'visible': true},
          {'id': 'col4', 'title': 'رعایت', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col5', 'title': 'ادا شدہ رقم', 'width': 45.0, 'align': 'center', 'visible': true},
          {'id': 'col6', 'title': 'کیفیت', 'width': 40.0, 'align': 'center', 'visible': true},
        ],
        'scale': 1.0,
        'headerBg': 0xFF0F766E,
        'headerTextColor': 0xFFFFFFFF,
        'rowTextColor': 0xFF000000,
        'gridColor': 0xFFCCCCCC,
        'alternateRowColors': true,
        'transparentHeader': false,
        'transparentRows': false,
        'altRowBg': 0xFFF0FDFA,
      },
    );
  }

  void _addPurchaseItemsTable() {
    _addNewElement(
      DesignerElementType.table,
      tableCfg: {
        'title': 'Invoice Items Table',
        'tableType': 'purchaseBill',
        'subjects': [
          {'name': 'چاول باسمتی اعلیٰ کوالٹی', 'max': 50, 'pass': 0, 'obtained': 4500, 'grade': 'کلو گرام', 'isAbsent': false},
          {'name': 'آٹا چکی تازہ گندم', 'max': 100, 'pass': 0, 'obtained': 3800, 'grade': 'کلو گرام', 'isAbsent': false},
          {'name': 'دال چنا و مونگ', 'max': 30, 'pass': 0, 'obtained': 3600, 'grade': 'کلو گرام', 'isAbsent': false},
          {'name': 'تیل سرسوں خالص', 'max': 20, 'pass': 0, 'obtained': 3200, 'grade': 'لیٹر', 'isAbsent': false},
        ],
        'columns': [
          {'id': 'col1', 'title': 'شمار', 'width': 25.0, 'align': 'center', 'visible': true},
          {'id': 'col2', 'title': 'تفصیل اشیاء (Item Description)', 'width': 100.0, 'align': 'right', 'visible': true},
          {'id': 'col3', 'title': 'تعداد / وزن', 'width': 40.0, 'align': 'center', 'visible': true},
          {'id': 'col4', 'title': 'اکائی', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col5', 'title': 'کل رقم (₹)', 'width': 45.0, 'align': 'center', 'visible': true},
          {'id': 'col6', 'title': 'کیفیت', 'width': 35.0, 'align': 'center', 'visible': true},
        ],
        'scale': 1.0,
        'headerBg': 0xFF1E3A8A,
        'headerTextColor': 0xFFFFFFFF,
        'rowTextColor': 0xFF000000,
        'gridColor': 0xFFCCCCCC,
        'alternateRowColors': true,
        'transparentHeader': false,
        'transparentRows': false,
        'altRowBg': 0xFFEFF6FF,
      },
    );
  }

  void _addLibrarySlotsTable() {
    _addNewElement(
      DesignerElementType.table,
      tableCfg: {
        'title': 'Library Issue Slots Table',
        'tableType': 'librarySlots',
        'subjects': [
          {'name': 'صحیح البخاری جلد اول', 'max': 101, 'pass': 0, 'obtained': 0, 'grade': 'جاری', 'isAbsent': false},
          {'name': 'ہدایہ اولین', 'max': 204, 'pass': 0, 'obtained': 0, 'grade': 'جاری', 'isAbsent': false},
          {'name': 'ریاض الصالحین', 'max': 305, 'pass': 0, 'obtained': 0, 'grade': 'واپس', 'isAbsent': false},
        ],
        'columns': [
          {'id': 'col1', 'title': 'شمار', 'width': 20.0, 'align': 'center', 'visible': true},
          {'id': 'col2', 'title': 'نام کتاب (Book Title)', 'width': 90.0, 'align': 'right', 'visible': true},
          {'id': 'col3', 'title': 'نمبر کتاب', 'width': 35.0, 'align': 'center', 'visible': true},
          {'id': 'col4', 'title': 'تاریخ اجراء', 'width': 40.0, 'align': 'center', 'visible': true},
          {'id': 'col5', 'title': 'تاریخ واپسی', 'width': 40.0, 'align': 'center', 'visible': true},
          {'id': 'col6', 'title': 'دستخط', 'width': 35.0, 'align': 'center', 'visible': true},
        ],
        'scale': 1.0,
        'headerBg': 0xFF7C2D12,
        'headerTextColor': 0xFFFFFFFF,
        'rowTextColor': 0xFF000000,
        'gridColor': 0xFFCCCCCC,
        'alternateRowColors': true,
        'transparentHeader': false,
        'transparentRows': false,
        'altRowBg': 0xFFFFF7ED,
      },
    );
  }

  void _matchTable2WithSizeOfTable1() {
    final tables = _currentTemplate.elements.where((e) => e.type == DesignerElementType.table).toList();
    if (tables.length >= 2) {
      final t1 = tables[0];
      final t2 = tables[1];
      setState(() {
        t2.widthRatio = t1.widthRatio;
        t2.heightRatio = t1.heightRatio;
        t2.xRatio = t1.xRatio;
        t2.yRatio = (t1.yRatio + t1.heightRatio + 0.03).clamp(0.0, 0.90);
        if (t1.tableConfig != null && t2.tableConfig != null) {
          t2.tableConfig!['scale'] = t1.tableConfig!['scale'];
          t2.tableConfig!['headerBg'] = t1.tableConfig!['headerBg'];
          t2.tableConfig!['headerTextColor'] = t1.tableConfig!['headerTextColor'];
          t2.tableConfig!['rowTextColor'] = t1.tableConfig!['rowTextColor'];
          t2.tableConfig!['gridColor'] = t1.tableConfig!['gridColor'];
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Table 2 matched with Table 1 size and styling!'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add both Table 1 and Table 2 first.'), backgroundColor: Colors.orange),
      );
    }
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F766E)));
  }

  Widget _toolButton(String title, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: const Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
              const Icon(Icons.add, size: 13, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorPickerTile(String label, Color color, ValueChanged<Color> onPicked) {
    return InkWell(
      onTap: () async {
        final c = await showDialog<Color>(
          context: context,
          builder: (_) => WindowsStyleColorPickerDialog(initialColor: color, title: label),
        );
        if (c != null) onPicked(c);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 4. Center Canvas
  // ─────────────────────────────────────────────────────────────
  Widget _buildCanvasArea(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;

        final aspect = _currentTemplate.aspectRatio;
        double cw;
        double ch;

        if (screenW / screenH > aspect) {
          ch = (screenH * 0.85) * _zoomScale;
          cw = ch * aspect;
        } else {
          cw = (screenW * 0.85) * _zoomScale;
          ch = cw / aspect;
        }

        return Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: _buildPhysicalCardCanvas(cw, ch, isDark),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhysicalCardCanvas(double cw, double ch, bool isDark) {
    final bgPath = _activeSide == 'front'
        ? _currentTemplate.backgroundImageFrontPath
        : _currentTemplate.backgroundImageBackPath;
    final useBgImg = _activeSide == 'front'
        ? _currentTemplate.useFrontTemplate
        : _currentTemplate.useBackTemplate;

    FileImage? bgImage;
    if (useBgImg && bgPath != null && bgPath.isNotEmpty) {
      final f = File(bgPath);
      if (f.existsSync()) bgImage = FileImage(f);
    }

    final visElements = _currentTemplate.elements
        .where((e) => e.isVisible && (e.side == _activeSide || _currentTemplate.preset == CanvasPreset.a4Portrait || _currentTemplate.preset == CanvasPreset.a4Landscape))
        .toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    final isTrans = _currentTemplate.isTransparentPageBg;

    return Container(
      width: cw,
      height: ch,
      decoration: BoxDecoration(
        color: isTrans ? Colors.transparent : (_currentTemplate.isGradient ? null : _currentTemplate.backgroundColor),
        gradient: (!isTrans && _currentTemplate.isGradient)
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_currentTemplate.backgroundColor, _currentTemplate.backgroundColor2],
              )
            : null,
        borderRadius: BorderRadius.circular(_currentTemplate.borderRadius * (_zoomScale.clamp(0.5, 1.5))),
        border: (!isTrans && _currentTemplate.borderWidth > 0)
            ? Border.all(color: _currentTemplate.borderColor, width: _currentTemplate.borderWidth * _zoomScale)
            : Border.all(color: Colors.grey.shade400.withAlpha(isTrans ? 60 : 255), width: 0.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isTrans ? 10 : 30), blurRadius: 15, offset: const Offset(0, 8)),
        ],
        image: bgImage != null ? DecorationImage(image: bgImage, fit: BoxFit.cover) : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Grid Overlay
          if (_showGrid && !_isPreviewMode)
            Positioned.fill(
              child: CustomPaint(
                painter: _CanvasGridPainter(spacing: 20 * _zoomScale),
              ),
            ),

          // Elements
          ...visElements.map((el) => _buildCanvasElement(el, cw, ch)),
        ],
      ),
    );
  }

  Widget _buildCanvasElement(DesignerElement el, double cw, double ch) {
    final isSel = el.id == _selectedElementId && !_isPreviewMode;
    final elLeft = el.xRatio * cw;
    final elTop = el.yRatio * ch;
    final elWidth = el.widthRatio * cw;
    final elHeight = el.heightRatio * ch;

    Widget content = _renderElementContent(el, elWidth, elHeight);

    return Positioned(
      left: elLeft,
      top: elTop,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedElementId = el.id;
                if (el.type == DesignerElementType.table) {
                  _rightPanelTabIndex = 1;
                } else {
                  _rightPanelTabIndex = 0;
                }
              });
            },
            onPanUpdate: _isPreviewMode
                ? null
                : (d) {
                    double newX = el.xRatio + (d.delta.dx / cw);
                    double newY = el.yRatio + (d.delta.dy / ch);
                    if (_snapToGrid) {
                      final stepX = _snapStepMm / _currentTemplate.widthMm;
                      final stepY = _snapStepMm / _currentTemplate.heightMm;
                      newX = (newX / stepX).round() * stepX;
                      newY = (newY / stepY).round() * stepY;
                    }
                    setState(() {
                      el.xRatio = newX.clamp(0.0, 0.95);
                      el.yRatio = newY.clamp(0.0, 0.95);
                      _selectedElementId = el.id;
                    });
                  },
            child: Container(
              width: elWidth,
              height: elHeight,
              decoration: BoxDecoration(
                border: isSel
                    ? Border.all(color: const Color(0xFF0F766E), width: 1.5)
                    : null,
              ),
              child: content,
            ),
          ),

          if (isSel) ...[
            // Resize Handle
            Positioned(
              right: -8,
              bottom: -8,
              child: GestureDetector(
                onPanUpdate: (d) {
                  final newW = (el.widthRatio + d.delta.dx / cw).clamp(0.05, 1.0);
                  final newH = (el.heightRatio + d.delta.dy / ch).clamp(0.02, 1.0);
                  setState(() {
                    el.widthRatio = newW;
                    el.heightRatio = newH;
                  });
                },
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),

            // Quick floating action pill
            Positioned(
              top: -28,
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _pillBtn(Icons.copy_rounded, () => _duplicateElement(el)),
                    _pillBtn(Icons.fit_screen_rounded, () => _autoFitElement(el)),
                    _pillBtn(Icons.arrow_upward_rounded, () => _reorderElement(el, true)),
                    _pillBtn(Icons.arrow_downward_rounded, () => _reorderElement(el, false)),
                    _pillBtn(Icons.delete_outline, () => _deleteElement(el.id), isDestructive: true),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pillBtn(IconData icon, VoidCallback onTap, {bool isDestructive = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 14, color: isDestructive ? Colors.redAccent : Colors.white),
      ),
    );
  }

  Widget _renderElementContent(DesignerElement el, double elWidth, double elHeight) {
    switch (el.type) {
      case DesignerElementType.text:
      case DesignerElementType.token:
        String str = el.text;
        if (el.tokenKey != null && el.tokenKey!.isNotEmpty) {
          str = _currentTokens[el.tokenKey!] ?? SampleDocumentData.resolveTokens(el.tokenKey!);
        } else {
          str = SampleDocumentData.resolveTokens(str);
        }
        if (el.showTitlePrefix && el.titlePrefix.isNotEmpty) {
          str = '${el.titlePrefix} $str';
        }
        if (_currentTemplate.convertDigits && (el.tokenKey == null || (!el.tokenKey!.contains('gr_no') && !el.tokenKey!.contains('barcode')))) {
          str = UrduNumberHelper.convertDigits(str, _currentTemplate.cardLanguage);
        }

        final isUrdu = el.fontFamily.contains('Jameel') || el.fontFamily.contains('Amiri') || el.fontFamily.contains('Gulzar') || el.fontFamily.contains('Nastaliq');
        return Container(
          width: elWidth,
          height: elHeight,
          alignment: el.textAlign == TextAlign.right
              ? Alignment.centerRight
              : (el.textAlign == TextAlign.left ? Alignment.centerLeft : Alignment.center),
          decoration: el.backgroundColor != null
              ? BoxDecoration(
                  color: el.backgroundColor,
                  borderRadius: BorderRadius.circular(el.borderRadius),
                  border: el.borderWidth > 0 ? Border.all(color: el.borderColor ?? Colors.black, width: el.borderWidth) : null,
                )
              : null,
          child: Text(
            str,
            textAlign: el.textAlign,
            textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
            style: TextStyle(
              fontFamily: el.fontFamily,
              fontSize: el.fontSize * _zoomScale,
              fontWeight: el.fontWeight,
              fontStyle: el.fontStyle,
              decoration: el.isUnderline ? TextDecoration.underline : null,
              color: el.color,
            ),
          ),
        );

      case DesignerElementType.photo:
        final s = _currentStudent;
        ImageProvider? img;
        if (el.imagePath != null && el.imagePath!.isNotEmpty) {
          final f = File(el.imagePath!);
          if (f.existsSync()) img = FileImage(f);
        } else if (s?.photoUrl != null && s!.photoUrl!.isNotEmpty) {
          final f = File(s.photoUrl!);
          if (f.existsSync()) img = FileImage(f);
        }
        return Container(
          width: elWidth,
          height: elHeight,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            shape: el.isRoundPhoto ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: el.isRoundPhoto ? null : BorderRadius.circular(el.borderRadius),
            border: Border.all(
              color: el.borderColor ?? const Color(0xFF0F766E),
              width: (el.borderWidth > 0 ? el.borderWidth : 1.5) * _zoomScale,
            ),
            image: img != null ? DecorationImage(image: img, fit: BoxFit.cover) : null,
          ),
          child: img == null
              ? Center(
                  child: Icon(Icons.person, size: elHeight * 0.5, color: Colors.grey.shade500),
                )
              : null,
        );

      case DesignerElementType.qrCode:
        final qrPayload = _currentTokens['{{student.gr_no}}'] != null
            ? 'GR:${_currentTokens['{{student.gr_no}}']}\nName:${_currentTokens['{{student.name}}'] ?? ''}'
            : (el.text.isNotEmpty ? el.text : 'MADARSA_VERIFICATION');
        return Center(
          child: QrImageView(
            data: qrPayload,
            version: QrVersions.auto,
            size: min(elWidth, elHeight),
            eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: el.color),
            dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: el.color),
          ),
        );

      case DesignerElementType.barcode:
        return Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    24,
                    (i) => Container(
                      width: (i % 3 == 0 ? 2.5 : 1.2) * _zoomScale,
                      height: (elHeight * 0.6),
                      margin: const EdgeInsets.symmetric(horizontal: 0.8),
                      color: Colors.black,
                    ),
                  ),
                ),
                Text(
                  _currentTokens['{{student.gr_no}}'] ?? '1045268',
                  style: TextStyle(fontSize: 8 * _zoomScale, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
              ],
            ),
          ),
        );

      case DesignerElementType.table:
        return _renderTableOnCanvas(el, elWidth, elHeight);

      case DesignerElementType.gradingScale:
        return _renderGradingScaleOnCanvas(el, elWidth, elHeight);

      case DesignerElementType.signature:
      case DesignerElementType.stamp:
        ImageProvider? img;
        if (el.imagePath != null && el.imagePath!.isNotEmpty) {
          final f = File(el.imagePath!);
          if (f.existsSync()) img = FileImage(f);
        }
        if (img != null) {
          return Image(image: img, fit: BoxFit.contain);
        }
        return Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: el.color.withAlpha(120), style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            el.type == DesignerElementType.signature ? '✍️ Authorized Signature' : '🏛️ Official Stamp / Seal',
            style: TextStyle(fontSize: 9 * _zoomScale, color: el.color, fontWeight: FontWeight.bold),
          ),
        );

      case DesignerElementType.dividerLine:
        return Center(
          child: Container(
            height: (el.borderWidth > 0 ? el.borderWidth : 1.5) * _zoomScale,
            color: el.color,
          ),
        );

      case DesignerElementType.shape:
      case DesignerElementType.logo:
        return Container(
          decoration: BoxDecoration(
            color: el.backgroundColor,
            borderRadius: BorderRadius.circular(el.isCircular ? elWidth / 2 : el.borderRadius),
            border: el.borderWidth > 0 ? Border.all(color: el.borderColor ?? Colors.black, width: el.borderWidth) : null,
          ),
        );
    }
  }

  Widget _renderTableOnCanvas(DesignerElement el, double elWidth, double elHeight) {
    final cfg = el.tableConfig ?? {};
    final subjects = List<Map<String, dynamic>>.from(cfg['subjects'] as List<dynamic>? ?? []);
    final cols = List<Map<String, dynamic>>.from(cfg['columns'] as List<dynamic>? ?? []);
    final isTransHdr = cfg['transparentHeader'] == true;
    final isTransRows = cfg['transparentRows'] == true;
    final headerBg = isTransHdr ? Colors.transparent : Color(cfg['headerBg'] as int? ?? 0xFF0D5C3A);
    final headerTextColor = isTransHdr ? Colors.black87 : Color(cfg['headerTextColor'] as int? ?? 0xFFFFFFFF);
    final rowTextColor = Color(cfg['rowTextColor'] as int? ?? 0xFF000000);
    final gridColor = Color(cfg['gridColor'] as int? ?? 0xFFCCCCCC);
    final gridWidth = (cfg['gridWidth'] as num?)?.toDouble() ?? 0.8;
    final altRowBg = (isTransRows || cfg['alternateRowColors'] == false) ? Colors.transparent : Color(cfg['altRowBg'] as int? ?? 0xFFF8FAFC);
    final tableScale = (cfg['scale'] as num?)?.toDouble() ?? 1.0;

    final visibleCols = cols.isEmpty
        ? [
            {'id': 'col1', 'title': 'نمبر شمار', 'width': 30.0, 'align': 'center', 'visible': true},
            {'id': 'col2', 'title': 'کتاب کا نام / مضمون', 'width': 90.0, 'align': 'right', 'visible': true},
            {'id': 'col3', 'title': 'کل نمبر', 'width': 35.0, 'align': 'center', 'visible': true},
            {'id': 'col4', 'title': 'کامیابی', 'width': 35.0, 'align': 'center', 'visible': true},
            {'id': 'col5', 'title': 'حاصل نمبر', 'width': 35.0, 'align': 'center', 'visible': true},
            {'id': 'col6', 'title': 'کیفیت / گریڈ', 'width': 45.0, 'align': 'center', 'visible': true},
          ]
        : cols.where((c) => c['visible'] != false).toList();

    return Transform.scale(
      scale: tableScale,
      alignment: Alignment.topCenter,
      child: Table(
        border: TableBorder.all(color: gridColor, width: gridWidth),
        children: [
          TableRow(
            decoration: BoxDecoration(color: headerBg),
            children: visibleCols.map((c) {
              return _th(c['title']?.toString() ?? '', headerTextColor);
            }).toList(),
          ),
          ...List.generate(subjects.length, (idx) {
            final s = subjects[idx];
            final isAlt = idx % 2 == 1;
            final isAbsent = s['isAbsent'] == true;
            final maxM = (s['max'] as num?)?.toDouble() ?? 100.0;
            final obtM = (s['obtained'] as num?)?.toDouble() ?? 0.0;
            final passM = (s['pass'] as num?)?.toDouble() ?? 33.0;
            final isFail = !isAbsent && passM > 0 && obtM < passM && _enableConditionalColors;

            return TableRow(
              decoration: BoxDecoration(color: isAlt ? altRowBg : (isTransRows ? Colors.transparent : Colors.white)),
              children: visibleCols.map((c) {
                final id = c['id'];
                if (id == 'col1') return _td('${idx + 1}', rowTextColor);
                if (id == 'col2') return _td(s['name']?.toString() ?? '', rowTextColor, align: TextAlign.right);
                if (id == 'col3') return _td('${maxM.toInt()}', rowTextColor);
                if (id == 'col4') return _td('${passM.toInt()}', rowTextColor);
                if (id == 'col5') return _td(isAbsent ? 'غائب' : '${obtM.toInt()}', (isAbsent || isFail) ? Colors.red : rowTextColor, isBold: true);
                if (id == 'col6') return _td(s['grade']?.toString() ?? '', (isAbsent || isFail) ? Colors.red : rowTextColor, isBold: true);
                return _td(s[id]?.toString() ?? '', rowTextColor);
              }).toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _renderGradingScaleOnCanvas(DesignerElement el, double elWidth, double elHeight) {
    final rules = [
      ('ممتاز (Distinction)', '${_distinctionThreshold.toInt()}% – 100%'),
      ('جید جداً (First Class)', '${_highMarkThreshold.toInt()}% – ${(_distinctionThreshold - 1).toInt()}%'),
      ('جید (Second Class)', '${_averageMarkThreshold.toInt()}% – ${(_highMarkThreshold - 1).toInt()}%'),
      ('مقبول (Pass)', '${_passMarkThreshold.toInt()}% – ${(_averageMarkThreshold - 1).toInt()}%'),
      ('راسب (Fail)', '< ${_passMarkThreshold.toInt()}%'),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: el.color, width: 1.0),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2),
            color: el.color,
            child: Text(
              'پیمانہ درجات (Grading Scale)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 8.5 * _zoomScale, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Jameel Noori Nastaleeq'),
            ),
          ),
          const SizedBox(height: 2),
          ...rules.map((r) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(r.$1, style: TextStyle(fontSize: 7.5 * _zoomScale, fontFamily: 'Jameel Noori Nastaleeq', fontWeight: FontWeight.w600)),
                  Text(r.$2, style: TextStyle(fontSize: 7.5 * _zoomScale, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _th(String text, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3 * _zoomScale, horizontal: 2),
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 8.5 * _zoomScale, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _td(String text, Color color, {TextAlign align = TextAlign.center, bool isBold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2.5 * _zoomScale, horizontal: 2),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 8.5 * _zoomScale,
          color: color,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontFamily: 'Jameel Noori Nastaleeq',
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 5. Right Panel with Tabs: Field Inspector | Table Studio
  // ─────────────────────────────────────────────────────────────
  Widget _buildRightPanelWithTabs(bool isDark) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(left: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _rightPanelTabIndex = 0),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _rightPanelTabIndex == 0 ? const Color(0xFF0F766E) : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.tune_rounded, size: 14, color: _rightPanelTabIndex == 0 ? const Color(0xFF0F766E) : Colors.grey),
                          const SizedBox(width: 4),
                          Text('Properties', style: TextStyle(fontSize: 11.5, fontWeight: _rightPanelTabIndex == 0 ? FontWeight.bold : FontWeight.normal, color: _rightPanelTabIndex == 0 ? const Color(0xFF0F766E) : null)),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _rightPanelTabIndex = 1),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _rightPanelTabIndex == 1 ? const Color(0xFF0F766E) : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.table_chart_rounded, size: 14, color: _rightPanelTabIndex == 1 ? const Color(0xFF0F766E) : Colors.grey),
                          const SizedBox(width: 4),
                          Text('Table Studio', style: TextStyle(fontSize: 11.5, fontWeight: _rightPanelTabIndex == 1 ? FontWeight.bold : FontWeight.normal, color: _rightPanelTabIndex == 1 ? const Color(0xFF0F766E) : null)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _rightPanelTabIndex == 1
                ? _buildTableStudioFullTab(isDark)
                : _buildGeneralInspectorFullTab(isDark),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Comprehensive Field Inspector (Text, Font, Size Slider, Formatting) ──
  Widget _buildGeneralInspectorFullTab(bool isDark) {
    final el = _selectedElement;

    if (el == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app_rounded, size: 36, color: Colors.grey.shade400),
              const SizedBox(height: 10),
              Text(
                'Select any element on canvas\nto customize font size, typography, alignment & colors',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Element Properties', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F766E))),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => setState(() => _selectedElementId = null),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Text Content
        TextFormField(
          key: ValueKey('lbl_${el.id}'),
          initialValue: el.text,
          decoration: const InputDecoration(labelText: 'Display Text / Content', isDense: true, border: OutlineInputBorder()),
          onChanged: (v) => setState(() => el.text = v),
        ),
        const SizedBox(height: 8),

        // Show Prefix toggle
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Show Label Prefix', style: TextStyle(fontSize: 11.5)),
          value: el.showTitlePrefix,
          onChanged: (v) => setState(() => el.showTitlePrefix = v),
        ),
        if (el.showTitlePrefix) ...[
          TextFormField(
            key: ValueKey('pfx_${el.id}'),
            initialValue: el.titlePrefix,
            decoration: const InputDecoration(labelText: 'Prefix Text (e.g. GR No:)', isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => setState(() => el.titlePrefix = v),
          ),
          const SizedBox(height: 8),
        ],

        // Typography Font Dropdown
        SearchableFontDropdown(
          label: 'Typography Font',
          currentFont: el.fontFamily,
          onSelected: (f) => setState(() => el.fontFamily = f),
        ),
        const SizedBox(height: 10),

        // ── Font Size Slider & Number Input ──
        _sectionTitle('Font Size (pt)'),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: el.fontSize.clamp(6.0, 48.0),
                min: 6.0,
                max: 48.0,
                divisions: 42,
                label: '${el.fontSize.toInt()} pt',
                onChanged: (v) => setState(() => el.fontSize = v),
              ),
            ),
            SizedBox(
              width: 50,
              child: TextFormField(
                key: ValueKey('fs_num_${el.id}_${el.fontSize.toInt()}'),
                initialValue: el.fontSize.toInt().toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
                onChanged: (v) {
                  final num = double.tryParse(v);
                  if (num != null) setState(() => el.fontSize = num.clamp(6.0, 72.0));
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Formatting Buttons: Bold, Italic, Underline
        Row(
          children: [
            const Text('Style: ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
            IconButton(
              icon: Icon(Icons.format_bold, color: el.fontWeight == FontWeight.bold ? const Color(0xFF0F766E) : Colors.grey),
              onPressed: () => setState(() => el.fontWeight = el.fontWeight == FontWeight.bold ? FontWeight.normal : FontWeight.bold),
            ),
            IconButton(
              icon: Icon(Icons.format_italic, color: el.fontStyle == FontStyle.italic ? const Color(0xFF0F766E) : Colors.grey),
              onPressed: () => setState(() => el.fontStyle = el.fontStyle == FontStyle.italic ? FontStyle.normal : FontStyle.italic),
            ),
            IconButton(
              icon: Icon(Icons.format_underlined, color: el.isUnderline ? const Color(0xFF0F766E) : Colors.grey),
              onPressed: () => setState(() => el.isUnderline = !el.isUnderline),
            ),
          ],
        ),

        // Alignment Buttons
        Row(
          children: [
            const Text('Align: ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
            IconButton(
              icon: Icon(Icons.format_align_left, color: el.textAlign == TextAlign.left ? const Color(0xFF0F766E) : Colors.grey),
              onPressed: () => setState(() => el.textAlign = TextAlign.left),
            ),
            IconButton(
              icon: Icon(Icons.format_align_center, color: el.textAlign == TextAlign.center ? const Color(0xFF0F766E) : Colors.grey),
              onPressed: () => setState(() => el.textAlign = TextAlign.center),
            ),
            IconButton(
              icon: Icon(Icons.format_align_right, color: el.textAlign == TextAlign.right ? const Color(0xFF0F766E) : Colors.grey),
              onPressed: () => setState(() => el.textAlign = TextAlign.right),
            ),
            IconButton(
              icon: Icon(Icons.format_align_justify, color: el.textAlign == TextAlign.justify ? const Color(0xFF0F766E) : Colors.grey),
              onPressed: () => setState(() => el.textAlign = TextAlign.justify),
            ),
          ],
        ),

        const Divider(height: 16),
        _sectionTitle('Colors & Container'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _colorPickerTile('Text Color', el.color, (c) => setState(() => el.color = c))),
            const SizedBox(width: 6),
            Expanded(child: _colorPickerTile('BG Color', el.backgroundColor ?? Colors.transparent, (c) => setState(() => el.backgroundColor = c))),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _colorPickerTile('Border Color', el.borderColor ?? Colors.black, (c) => setState(() => el.borderColor = c))),
            const SizedBox(width: 6),
            Expanded(
              child: TextFormField(
                key: ValueKey('el_bw_${el.id}'),
                initialValue: el.borderWidth.toString(),
                decoration: const InputDecoration(labelText: 'Border (mm)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => el.borderWidth = double.tryParse(v) ?? 0.0),
              ),
            ),
          ],
        ),

        const Divider(height: 16),
        _sectionTitle('Position & Auto-Fit'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('x_${el.id}'),
                initialValue: (el.xRatio * 100).toInt().toString(),
                decoration: const InputDecoration(labelText: 'X (%)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => el.xRatio = (double.tryParse(v) ?? 0) / 100),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: ValueKey('y_${el.id}'),
                initialValue: (el.yRatio * 100).toInt().toString(),
                decoration: const InputDecoration(labelText: 'Y (%)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => el.yRatio = (double.tryParse(v) ?? 0) / 100),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('w_${el.id}'),
                initialValue: (el.widthRatio * 100).toInt().toString(),
                decoration: const InputDecoration(labelText: 'Width (%)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => el.widthRatio = (double.tryParse(v) ?? 10) / 100),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: ValueKey('h_${el.id}'),
                initialValue: (el.heightRatio * 100).toInt().toString(),
                decoration: const InputDecoration(labelText: 'Height (%)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => el.heightRatio = (double.tryParse(v) ?? 10) / 100),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.fit_screen_rounded, size: 16),
          label: const Text('Auto-Fit Box to Text', style: TextStyle(fontSize: 11.5)),
          onPressed: () => _autoFitElement(el),
        ),

        // Photo Controls
        if (el.type == DesignerElementType.photo) ...[
          const Divider(height: 16),
          _sectionTitle('Photo Options'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Circular Photo', style: TextStyle(fontSize: 11.5)),
            value: el.isRoundPhoto,
            onChanged: (v) => setState(() => el.isRoundPhoto = v),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.photo, size: 14),
            label: const Text('Upload Photo', style: TextStyle(fontSize: 11)),
            onPressed: () async {
              final res = await FilePicker.platform.pickFiles(type: FileType.image);
              if (res != null && res.files.single.path != null) {
                setState(() => el.imagePath = res.files.single.path);
              }
            },
          ),
        ],

        // Signature & Seal Controls
        if (el.type == DesignerElementType.signature || el.type == DesignerElementType.stamp) ...[
          const Divider(height: 16),
          _sectionTitle('Upload Signature / Seal'),
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file_rounded, size: 14),
            label: Text(el.imagePath != null ? 'Change Image' : 'Upload PNG Image', style: const TextStyle(fontSize: 11)),
            onPressed: () async {
              final res = await FilePicker.platform.pickFiles(type: FileType.image);
              if (res != null && res.files.single.path != null) {
                setState(() => el.imagePath = res.files.single.path);
              }
            },
          ),
        ],
      ],
    );
  }

  // ── Tab 2: The Complete Table Studio (Universal Across ALL Cards) ──
  Widget _buildTableStudioFullTab(bool isDark) {
    final el = _activeTableElement;

    if (el == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.table_chart_rounded, size: 40, color: const Color(0xFF0F766E)),
              const SizedBox(height: 10),
              const Text('Add Table to Design', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              const Text('Choose table template for this document:', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 12),
              _addTableOptionBtn('📊 Exam Marksheet Table', () => _addResultMarksTable('سالانہ امتحان', 1)),
              _addTableOptionBtn('🧾 Fee Breakdown Table', _addFeeBreakdownTable),
              _addTableOptionBtn('🛒 Purchase & Sales Bill Table', _addPurchaseItemsTable),
              _addTableOptionBtn('📚 Library Issue Slots Table', _addLibrarySlotsTable),
              _addTableOptionBtn('🎫 Exam Timetable Table', _addAdmitCardScheduleTable),
              _addTableOptionBtn('🪪 Student Attendance / Session Table', _addStudentAttendanceTable),
              _addTableOptionBtn('👔 Staff Assigned Schedule Table', _addStaffScheduleTable),
              _addTableOptionBtn('📜 Sanad Academic Subjects Table', _addSanadAcademicTable),
            ],
          ),
        ),
      );
    }

    final cfg = el.tableConfig ?? {};
    final subjects = List<Map<String, dynamic>>.from(cfg['subjects'] as List<dynamic>? ?? []);
    final cols = List<Map<String, dynamic>>.from(cfg['columns'] as List<dynamic>? ?? []);
    double scale = (cfg['scale'] as num?)?.toDouble() ?? 1.0;
    Color headerBg = Color(cfg['headerBg'] as int? ?? 0xFF0D5C3A);
    Color headerTextColor = Color(cfg['headerTextColor'] as int? ?? 0xFFFFFFFF);
    Color rowTextColor = Color(cfg['rowTextColor'] as int? ?? 0xFF000000);
    Color gridColor = Color(cfg['gridColor'] as int? ?? 0xFFCCCCCC);
    double gridWidth = (cfg['gridWidth'] as num?)?.toDouble() ?? 0.8;
    bool altRows = cfg['alternateRowColors'] as bool? ?? true;
    bool isTransHdr = cfg['transparentHeader'] as bool? ?? false;
    bool isTransRows = cfg['transparentRows'] as bool? ?? false;

    final totalMax = subjects.fold(0.0, (sum, s) => sum + ((s['max'] as num?)?.toDouble() ?? 0.0));
    final totalObtained = subjects.fold(0.0, (sum, s) => sum + ((s['isAbsent'] == true ? 0.0 : (s['obtained'] as num?)?.toDouble() ?? 0.0)));
    final pct = totalMax > 0 ? (totalObtained / totalMax) * 100.0 : 0.0;
    final isPass = pct >= _passMarkThreshold;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── 1. Two Tables Support ──
        _sectionTitle('📊 Two Tables Support (دو جداول)'),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Enable 2 Tables (دو جداول)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          value: _enableSecondTable,
          onChanged: (v) {
            setState(() {
              _enableSecondTable = v;
              if (v && !_currentTemplate.elements.any((e) => e.type == DesignerElementType.table && e.tableConfig?['tableGroup'] == 2)) {
                _addResultMarksTable('ششماہی امتحان', 2);
              }
            });
          },
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                icon: const Icon(Icons.add_chart_rounded, size: 14),
                label: const Text('Add Table 1', style: TextStyle(fontSize: 10.5)),
                onPressed: () => _addResultMarksTable('سالانہ امتحان', 1),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
                icon: const Icon(Icons.post_add_rounded, size: 14),
                label: const Text('Add Table 2', style: TextStyle(fontSize: 10.5)),
                onPressed: () => _addResultMarksTable('ششماہی امتحان', 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6)),
          icon: const Icon(Icons.sync_alt_rounded, size: 14, color: Color(0xFF0F766E)),
          label: const Text('🔗 Match Table 2 Size with Table 1', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
          onPressed: _matchTable2WithSizeOfTable1,
        ),
        const SizedBox(height: 6),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          icon: const Icon(Icons.edit_calendar_rounded, size: 15, color: Colors.white),
          label: const Text('Open Deep Table Dialog', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => DesignerTableDialog(
                initialConfig: el.tableConfig ?? {},
                onSave: (updated) => setState(() => el.tableConfig = updated),
              ),
            );
          },
        ),

        const Divider(height: 16),

        // ── 2. Table Layout Modes ──
        _sectionTitle('🔗 Table Layout Modes'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTableGrouped ? const Color(0xFF0F766E) : Colors.grey.shade200,
                  foregroundColor: _isTableGrouped ? Colors.white : Colors.black87,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                icon: const Icon(Icons.link_rounded, size: 15),
                label: const Text('Grouped Table', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                onPressed: () => setState(() => _isTableGrouped = true),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: !_isTableGrouped ? const Color(0xFF0284C7) : Colors.grey.shade200,
                  foregroundColor: !_isTableGrouped ? Colors.white : Colors.black87,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                icon: const Icon(Icons.link_off_rounded, size: 15),
                label: const Text('Ungroup Columns', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                onPressed: () => setState(() => _isTableGrouped = false),
              ),
            ),
          ],
        ),

        const Divider(height: 16),

        // ── 3. Table Scale Slider (50% to 150%) ──
        _sectionTitle('🔍 Table Scale Slider (50% – 150%)'),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: scale,
                min: 0.5,
                max: 1.5,
                divisions: 20,
                label: '${(scale * 100).toInt()}%',
                onChanged: (v) {
                  setState(() {
                    cfg['scale'] = v;
                    el.tableConfig = cfg;
                  });
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF0F766E), borderRadius: BorderRadius.circular(4)),
              child: Text('${(scale * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
            ),
          ],
        ),

        const Divider(height: 16),

        // ── 4. Columns Customization (6 Columns) ──
        _sectionTitle('📐 Columns Customization (6 Columns)'),
        const SizedBox(height: 6),
        ...cols.map((c) {
          final isVis = c['visible'] != false;
          final title = c['title']?.toString() ?? '';
          final double w = (c['width'] as num?)?.toDouble() ?? 30.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
            child: Column(
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: isVis,
                      activeColor: const Color(0xFF0F766E),
                      onChanged: (v) {
                        setState(() {
                          c['visible'] = v ?? true;
                          cfg['columns'] = cols;
                          el.tableConfig = cfg;
                        });
                      },
                    ),
                    Expanded(
                      child: TextFormField(
                        initialValue: title,
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
                        onChanged: (v) {
                          c['title'] = v;
                          cfg['columns'] = cols;
                          el.tableConfig = cfg;
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Width: ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Expanded(
                      child: Slider(
                        value: w.clamp(15.0, 150.0),
                        min: 15.0,
                        max: 150.0,
                        onChanged: (v) {
                          setState(() {
                            c['width'] = v;
                            cfg['columns'] = cols;
                            el.tableConfig = cfg;
                          });
                        },
                      ),
                    ),
                    Text('${w.toInt()}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          );
        }),

        const Divider(height: 16),

        // ── 5. Subject Rows Management ──
        _sectionTitle('📚 Rows Management (${subjects.length})'),
        const SizedBox(height: 6),

        ...List.generate(subjects.length, (idx) {
          final s = subjects[idx];
          final isAbsent = s['isAbsent'] == true;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('#${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextFormField(
                        initialValue: s['name']?.toString() ?? '',
                        decoration: const InputDecoration(labelText: 'Item / Subject Name', isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                        onChanged: (v) {
                          s['name'] = v;
                          cfg['subjects'] = subjects;
                          el.tableConfig = cfg;
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          subjects.removeAt(idx);
                          cfg['subjects'] = subjects;
                          el.tableConfig = cfg;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    SizedBox(
                      width: 55,
                      child: TextFormField(
                        initialValue: s['max']?.toString() ?? '100',
                        decoration: const InputDecoration(labelText: 'Max/Qty', isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                        onChanged: (v) {
                          s['max'] = double.tryParse(v) ?? 100;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 55,
                      child: TextFormField(
                        initialValue: s['pass']?.toString() ?? '33',
                        decoration: const InputDecoration(labelText: 'Pass', isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                        onChanged: (v) {
                          s['pass'] = double.tryParse(v) ?? 33;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 60,
                      child: TextFormField(
                        initialValue: s['obtained']?.toString() ?? '0',
                        decoration: const InputDecoration(labelText: 'Obt/Amt', isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                        onChanged: (v) {
                          s['obtained'] = double.tryParse(v) ?? 0;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Checkbox(
                      value: isAbsent,
                      activeColor: Colors.red,
                      onChanged: (v) {
                        setState(() {
                          s['isAbsent'] = v ?? false;
                          cfg['subjects'] = subjects;
                          el.tableConfig = cfg;
                        });
                      },
                    ),
                    const Text('Absent', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          );
        }),

        OutlinedButton.icon(
          icon: const Icon(Icons.add, size: 14),
          label: const Text('➕ Add Row', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          onPressed: () {
            setState(() {
              subjects.add({
                'name': 'نیا اندراج ${subjects.length + 1}',
                'max': 100,
                'pass': 33,
                'obtained': 75,
                'grade': 'جید',
                'isAbsent': false,
              });
              cfg['subjects'] = subjects;
              el.tableConfig = cfg;
            });
          },
        ),

        const Divider(height: 16),

        // ── 6. Table Colors & Styling ──
        _sectionTitle('🎨 Table Colors & Styling'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _colorPickerTile('Header BG', headerBg, (c) {
              setState(() {
                cfg['headerBg'] = c.toARGB32();
                el.tableConfig = cfg;
              });
            }),
            _colorPickerTile('Header Text', headerTextColor, (c) {
              setState(() {
                cfg['headerTextColor'] = c.toARGB32();
                el.tableConfig = cfg;
              });
            }),
            _colorPickerTile('Row Text', rowTextColor, (c) {
              setState(() {
                cfg['rowTextColor'] = c.toARGB32();
                el.tableConfig = cfg;
              });
            }),
            _colorPickerTile('Grid Border', gridColor, (c) {
              setState(() {
                cfg['gridColor'] = c.toARGB32();
                el.tableConfig = cfg;
              });
            }),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Border Width: ', style: TextStyle(fontSize: 11)),
            Expanded(
              child: Slider(
                value: gridWidth.clamp(0.0, 3.0),
                min: 0.0,
                max: 3.0,
                divisions: 30,
                onChanged: (v) {
                  setState(() {
                    cfg['gridWidth'] = v;
                    el.tableConfig = cfg;
                  });
                },
              ),
            ),
            Text('${gridWidth.toStringAsFixed(1)}mm', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
          ],
        ),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Alternate Row Colors', style: TextStyle(fontSize: 11.5)),
          value: altRows,
          onChanged: (v) {
            setState(() {
              cfg['alternateRowColors'] = v;
              el.tableConfig = cfg;
            });
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Transparent Table Header (Pre-Printed)', style: TextStyle(fontSize: 11.5)),
          value: isTransHdr,
          onChanged: (v) {
            setState(() {
              cfg['transparentHeader'] = v;
              el.tableConfig = cfg;
            });
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Transparent Table Rows (Pre-Printed)', style: TextStyle(fontSize: 11.5)),
          value: isTransRows,
          onChanged: (v) {
            setState(() {
              cfg['transparentRows'] = v;
              el.tableConfig = cfg;
            });
          },
        ),

        const Divider(height: 16),

        // ── 7. Dynamic Grading Rules & Conditional Colors ──
        _sectionTitle('🏆 Dynamic Grading Rules & Fail Colors'),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Conditional Fail Color (Red for Fail)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.red)),
          value: _enableConditionalColors,
          onChanged: (v) => setState(() => _enableConditionalColors = v),
        ),

        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _distinctionThreshold.toInt().toString(),
                decoration: const InputDecoration(labelText: 'ممتاز (>= %)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _distinctionThreshold = double.tryParse(v) ?? 90.0),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextFormField(
                initialValue: _highMarkThreshold.toInt().toString(),
                decoration: const InputDecoration(labelText: 'جید جداً (>= %)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _highMarkThreshold = double.tryParse(v) ?? 75.0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: _averageMarkThreshold.toInt().toString(),
                decoration: const InputDecoration(labelText: 'جید (>= %)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _averageMarkThreshold = double.tryParse(v) ?? 60.0),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextFormField(
                initialValue: _passMarkThreshold.toInt().toString(),
                decoration: const InputDecoration(labelText: 'مقبول (Pass %)', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _passMarkThreshold = double.tryParse(v) ?? 33.0),
              ),
            ),
          ],
        ),

        const Divider(height: 16),

        // ── 8. Auto Summary & Total Row ──
        _sectionTitle('📈 Auto Summary & Total Row'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0D5C3A).withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF0D5C3A).withAlpha(50)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Max/Qty: ${totalMax.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  Text('Obtained/Amt: ${totalObtained.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF0D5C3A))),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ratio: ${pct.toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF0D5C3A)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isPass ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(isPass ? 'STATUS: OK' : 'STATUS: REVIEW', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _addTableOptionBtn(String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: onTap,
          child: Text(title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class _CanvasGridPainter extends CustomPainter {
  final double spacing;
  _CanvasGridPainter({required this.spacing});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.grey.shade400.withAlpha(70)
      ..strokeWidth = 0.5;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasGridPainter old) => old.spacing != spacing;
}
