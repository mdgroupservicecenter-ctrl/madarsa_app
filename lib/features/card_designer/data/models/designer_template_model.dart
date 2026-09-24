import 'package:flutter/material.dart';

/// Supported types of documents that can be designed
enum DocumentType {
  studentIdCard,
  staffIdCard,
  resultCard,
  certificate,
  feeReceipt,
  purchaseBill,
  libraryCard,
  admitCard,
  custom;

  String get labelEn {
    switch (this) {
      case DocumentType.studentIdCard:
        return 'Student ID Card';
      case DocumentType.staffIdCard:
        return 'Staff ID Card';
      case DocumentType.resultCard:
        return 'Result Card / Marksheet';
      case DocumentType.certificate:
        return 'Certificate / Sanad';
      case DocumentType.feeReceipt:
        return 'Fee Receipt';
      case DocumentType.purchaseBill:
        return 'Sale / Purchase Bill';
      case DocumentType.libraryCard:
        return 'Library Card / Ticket';
      case DocumentType.admitCard:
        return 'Exam Admit Card';
      case DocumentType.custom:
        return 'Custom Document';
    }
  }

  String get labelUr {
    switch (this) {
      case DocumentType.studentIdCard:
        return 'طالب علم شناختی کارڈ';
      case DocumentType.staffIdCard:
        return 'ملازم شناختی کارڈ';
      case DocumentType.resultCard:
        return 'نتیجہ کارڈ / کشف الدرجات';
      case DocumentType.certificate:
        return 'اسناد و سرٹیفکیٹس';
      case DocumentType.feeReceipt:
        return 'فیس رسید';
      case DocumentType.purchaseBill:
        return 'خرید و فروخت بل';
      case DocumentType.libraryCard:
        return 'لائبریری کارڈ / ٹکٹ';
      case DocumentType.admitCard:
        return 'امتحانی داخلہ کارڈ';
      case DocumentType.custom:
        return 'کسٹم دستاویز';
    }
  }

  IconData get icon {
    switch (this) {
      case DocumentType.studentIdCard:
        return Icons.badge_rounded;
      case DocumentType.staffIdCard:
        return Icons.contact_mail_rounded;
      case DocumentType.resultCard:
        return Icons.assessment_rounded;
      case DocumentType.certificate:
        return Icons.workspace_premium_rounded;
      case DocumentType.feeReceipt:
        return Icons.receipt_long_rounded;
      case DocumentType.purchaseBill:
        return Icons.point_of_sale_rounded;
      case DocumentType.libraryCard:
        return Icons.local_library_rounded;
      case DocumentType.admitCard:
        return Icons.assignment_ind_rounded;
      case DocumentType.custom:
        return Icons.dashboard_customize_rounded;
    }
  }
}

/// Canvas size presets with standard physical dimensions in millimeters
enum CanvasPreset {
  cr80Vertical(54.0, 85.6, 'ID Card (Vertical / Portrait)'),
  cr80Horizontal(85.6, 54.0, 'ID Card (Horizontal / Landscape)'),
  a4Portrait(210.0, 297.0, 'A4 Marksheet / Bill (Portrait)'),
  a4Landscape(297.0, 210.0, 'A4 Sanad / Certificate (Landscape)'),
  a5Portrait(148.0, 210.0, 'A5 Receipt / Voucher (Portrait)'),
  a5Landscape(210.0, 148.0, 'A5 Half Page (Landscape)'),
  a7Vertical(74.0, 105.0, 'A7 Library Ticket (Vertical)'),
  posReceipt80(80.0, 150.0, 'POS Receipt (80mm Thermal)'),
  custom(100.0, 100.0, 'Custom Dimensions');

  final double widthMm;
  final double heightMm;
  final String label;

  const CanvasPreset(this.widthMm, this.heightMm, this.label);

  double get aspectRatio => widthMm / heightMm;
}

/// Types of elements placeable on the canvas
enum DesignerElementType {
  text,
  token,
  photo,
  logo,
  qrCode,
  barcode,
  table,
  dividerLine,
  shape,
  signature,
  stamp,
  gradingScale;

  String get label {
    switch (this) {
      case DesignerElementType.text:
        return 'Static Text';
      case DesignerElementType.token:
        return 'Data Field';
      case DesignerElementType.photo:
        return 'Student/Staff Photo';
      case DesignerElementType.logo:
        return 'Institution Logo';
      case DesignerElementType.qrCode:
        return 'QR Code';
      case DesignerElementType.barcode:
        return 'Barcode';
      case DesignerElementType.table:
        return 'Marks & Subjects Table';
      case DesignerElementType.dividerLine:
        return 'Line / Divider';
      case DesignerElementType.shape:
        return 'Shape / Box';
      case DesignerElementType.signature:
        return 'Authorized Signature';
      case DesignerElementType.stamp:
        return 'Official Stamp / Seal';
      case DesignerElementType.gradingScale:
        return 'Grading Scale Box (پیمانہ درجات)';
    }
  }

  IconData get icon {
    switch (this) {
      case DesignerElementType.text:
        return Icons.text_fields_rounded;
      case DesignerElementType.token:
        return Icons.data_object_rounded;
      case DesignerElementType.photo:
        return Icons.account_box_rounded;
      case DesignerElementType.logo:
        return Icons.spa_rounded;
      case DesignerElementType.qrCode:
        return Icons.qr_code_rounded;
      case DesignerElementType.barcode:
        return Icons.view_column_rounded;
      case DesignerElementType.table:
        return Icons.table_chart_rounded;
      case DesignerElementType.dividerLine:
        return Icons.horizontal_rule_rounded;
      case DesignerElementType.shape:
        return Icons.crop_square_rounded;
      case DesignerElementType.signature:
        return Icons.draw_rounded;
      case DesignerElementType.stamp:
        return Icons.verified_rounded;
      case DesignerElementType.gradingScale:
        return Icons.auto_graph_rounded;
    }
  }
}

/// A single element positioned on the design canvas
class DesignerElement {
  final String id;
  DesignerElementType type;
  String side; // 'front' or 'back'

  // Normalized relative positioning (0.0 to 1.0)
  double xRatio;
  double yRatio;
  double widthRatio;
  double heightRatio;

  // Content
  String label;
  String text;
  String? tokenKey; // e.g., '{{student.name}}', '{{student.gr_no}}'
  String titlePrefix;
  bool showTitlePrefix;
  bool isCombinedName;
  bool isCombinedAddress;
  bool isRoundPhoto;
  String? imagePath;
  String barcodeType; // 'code128', 'ean13', 'qr'

  // Typography
  double fontSize;
  String fontFamily;
  FontWeight fontWeight;
  FontStyle fontStyle;
  Color color;
  TextAlign textAlign;
  bool isUrduRtl;
  bool isUnderline;

  // Styling & Container
  Color? backgroundColor;
  Color? borderColor;
  double borderWidth;
  double borderRadius;
  double opacity;
  bool isCircular;

  // Table Configuration (for Marksheet subjects, invoices, receipts)
  Map<String, dynamic>? tableConfig;

  // Shape Configuration
  String? shapeType; // 'rectangle', 'circle', 'divider'

  // Layer order
  int zIndex;
  bool isVisible;

  DesignerElement({
    required this.id,
    required this.type,
    this.side = 'front',
    required this.xRatio,
    required this.yRatio,
    required this.widthRatio,
    required this.heightRatio,
    this.label = '',
    this.text = '',
    this.tokenKey,
    this.titlePrefix = '',
    this.showTitlePrefix = false,
    this.isCombinedName = false,
    this.isCombinedAddress = false,
    this.isRoundPhoto = false,
    this.imagePath,
    this.barcodeType = 'code128',
    this.fontSize = 14.0,
    this.fontFamily = 'Jameel Noori Nastaleeq',
    this.fontWeight = FontWeight.normal,
    this.fontStyle = FontStyle.normal,
    this.color = Colors.black,
    this.textAlign = TextAlign.center,
    this.isUrduRtl = true,
    this.isUnderline = false,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 0.0,
    this.borderRadius = 0.0,
    this.opacity = 1.0,
    this.isCircular = false,
    this.tableConfig,
    this.shapeType,
    this.zIndex = 0,
    this.isVisible = true,
  });

  DesignerElement copyWith({
    String? id,
    DesignerElementType? type,
    String? side,
    double? xRatio,
    double? yRatio,
    double? widthRatio,
    double? heightRatio,
    String? label,
    String? text,
    String? tokenKey,
    String? titlePrefix,
    bool? showTitlePrefix,
    bool? isCombinedName,
    bool? isCombinedAddress,
    bool? isRoundPhoto,
    String? imagePath,
    String? barcodeType,
    double? fontSize,
    String? fontFamily,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    Color? color,
    TextAlign? textAlign,
    bool? isUrduRtl,
    bool? isUnderline,
    Color? backgroundColor,
    Color? borderColor,
    double? borderWidth,
    double? borderRadius,
    double? opacity,
    bool? isCircular,
    Map<String, dynamic>? tableConfig,
    String? shapeType,
    int? zIndex,
    bool? isVisible,
  }) {
    return DesignerElement(
      id: id ?? this.id,
      type: type ?? this.type,
      side: side ?? this.side,
      xRatio: xRatio ?? this.xRatio,
      yRatio: yRatio ?? this.yRatio,
      widthRatio: widthRatio ?? this.widthRatio,
      heightRatio: heightRatio ?? this.heightRatio,
      label: label ?? this.label,
      text: text ?? this.text,
      tokenKey: tokenKey ?? this.tokenKey,
      titlePrefix: titlePrefix ?? this.titlePrefix,
      showTitlePrefix: showTitlePrefix ?? this.showTitlePrefix,
      isCombinedName: isCombinedName ?? this.isCombinedName,
      isCombinedAddress: isCombinedAddress ?? this.isCombinedAddress,
      isRoundPhoto: isRoundPhoto ?? this.isRoundPhoto,
      imagePath: imagePath ?? this.imagePath,
      barcodeType: barcodeType ?? this.barcodeType,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      color: color ?? this.color,
      textAlign: textAlign ?? this.textAlign,
      isUrduRtl: isUrduRtl ?? this.isUrduRtl,
      isUnderline: isUnderline ?? this.isUnderline,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      borderRadius: borderRadius ?? this.borderRadius,
      opacity: opacity ?? this.opacity,
      isCircular: isCircular ?? this.isCircular,
      tableConfig: tableConfig ?? this.tableConfig,
      shapeType: shapeType ?? this.shapeType,
      zIndex: zIndex ?? this.zIndex,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'side': side,
      'xRatio': xRatio,
      'yRatio': yRatio,
      'widthRatio': widthRatio,
      'heightRatio': heightRatio,
      'label': label,
      'text': text,
      'tokenKey': tokenKey,
      'titlePrefix': titlePrefix,
      'showTitlePrefix': showTitlePrefix,
      'isCombinedName': isCombinedName,
      'isCombinedAddress': isCombinedAddress,
      'isRoundPhoto': isRoundPhoto,
      'imagePath': imagePath,
      'barcodeType': barcodeType,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'fontWeight': fontWeight.value,
      'fontStyle': fontStyle.name,
      'color': color.toARGB32(),
      'textAlign': textAlign.name,
      'isUrduRtl': isUrduRtl,
      'isUnderline': isUnderline,
      'backgroundColor': backgroundColor?.toARGB32(),
      'borderColor': borderColor?.toARGB32(),
      'borderWidth': borderWidth,
      'borderRadius': borderRadius,
      'opacity': opacity,
      'isCircular': isCircular,
      'tableConfig': tableConfig,
      'shapeType': shapeType,
      'zIndex': zIndex,
      'isVisible': isVisible,
    };
  }

  factory DesignerElement.fromJson(Map<String, dynamic> json) {
    final fwVal = json['fontWeight'] as int? ?? 400;
    final parsedFw = FontWeight.values.firstWhere(
      (w) => w.value == fwVal,
      orElse: () => FontWeight.normal,
    );
    return DesignerElement(
      id: json['id'] as String,
      type: DesignerElementType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DesignerElementType.text,
      ),
      side: json['side'] as String? ?? 'front',
      xRatio: (json['xRatio'] as num).toDouble(),
      yRatio: (json['yRatio'] as num).toDouble(),
      widthRatio: (json['widthRatio'] as num).toDouble(),
      heightRatio: (json['heightRatio'] as num).toDouble(),
      label: json['label'] as String? ?? '',
      text: json['text'] as String? ?? '',
      tokenKey: json['tokenKey'] as String?,
      titlePrefix: json['titlePrefix'] as String? ?? '',
      showTitlePrefix: json['showTitlePrefix'] as bool? ?? false,
      isCombinedName: json['isCombinedName'] as bool? ?? false,
      isCombinedAddress: json['isCombinedAddress'] as bool? ?? false,
      isRoundPhoto: json['isRoundPhoto'] as bool? ?? false,
      imagePath: json['imagePath'] as String?,
      barcodeType: json['barcodeType'] as String? ?? 'code128',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      fontFamily: json['fontFamily'] as String? ?? 'Jameel Noori Nastaleeq',
      fontWeight: parsedFw,
      fontStyle: FontStyle.values.firstWhere(
        (e) => e.name == json['fontStyle'],
        orElse: () => FontStyle.normal,
      ),
      color: Color(json['color'] as int? ?? 0xFF000000),
      textAlign: TextAlign.values.firstWhere(
        (e) => e.name == json['textAlign'],
        orElse: () => TextAlign.center,
      ),
      isUrduRtl: json['isUrduRtl'] as bool? ?? true,
      isUnderline: json['isUnderline'] as bool? ?? false,
      backgroundColor: json['backgroundColor'] != null
          ? Color(json['backgroundColor'] as int)
          : null,
      borderColor: json['borderColor'] != null
          ? Color(json['borderColor'] as int)
          : null,
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 0.0,
      borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      isCircular: json['isCircular'] as bool? ?? false,
      tableConfig: json['tableConfig'] != null
          ? Map<String, dynamic>.from(json['tableConfig'] as Map)
          : null,
      shapeType: json['shapeType'] as String?,
      zIndex: json['zIndex'] as int? ?? 0,
      isVisible: json['isVisible'] as bool? ?? true,
    );
  }
}

/// A complete multi-element design template
class DesignerTemplate {
  final String id;
  String name;
  DocumentType documentType;
  CanvasPreset preset;
  double widthMm;
  double heightMm;
  Color backgroundColor;
  Color backgroundColor2;
  bool isGradient;
  Color borderColor;
  double borderWidth;
  double borderRadius;
  String? backgroundImageFrontPath;
  String? backgroundImageBackPath;
  bool useFrontTemplate;
  bool useBackTemplate;
  String cardLanguage; // 'ur' or 'en'
  bool isTransparentPageBg;
  bool convertDigits;
  bool enableSecondTable;
  List<DesignerElement> elements;
  Map<String, dynamic>? gradingScaleRules;
  DateTime createdAt;
  DateTime updatedAt;

  DesignerTemplate({
    required this.id,
    required this.name,
    required this.documentType,
    this.preset = CanvasPreset.cr80Vertical,
    double? widthMm,
    double? heightMm,
    this.backgroundColor = Colors.white,
    this.backgroundColor2 = const Color(0xFF063A2A),
    this.isGradient = false,
    this.borderColor = const Color(0xFFFFD700),
    this.borderWidth = 0.0,
    this.borderRadius = 8.0,
    this.backgroundImageFrontPath,
    this.backgroundImageBackPath,
    this.useFrontTemplate = false,
    this.useBackTemplate = false,
    this.cardLanguage = 'ur',
    this.isTransparentPageBg = false,
    this.convertDigits = true,
    this.enableSecondTable = false,
    List<DesignerElement>? elements,
    this.gradingScaleRules,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : widthMm = widthMm ?? preset.widthMm,
        heightMm = heightMm ?? preset.heightMm,
        elements = elements ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  double get aspectRatio => widthMm / heightMm;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'documentType': documentType.name,
      'preset': preset.name,
      'widthMm': widthMm,
      'heightMm': heightMm,
      'backgroundColor': backgroundColor.toARGB32(),
      'backgroundColor2': backgroundColor2.toARGB32(),
      'isGradient': isGradient,
      'borderColor': borderColor.toARGB32(),
      'borderWidth': borderWidth,
      'borderRadius': borderRadius,
      'backgroundImageFrontPath': backgroundImageFrontPath,
      'backgroundImageBackPath': backgroundImageBackPath,
      'useFrontTemplate': useFrontTemplate,
      'useBackTemplate': useBackTemplate,
      'cardLanguage': cardLanguage,
      'isTransparentPageBg': isTransparentPageBg,
      'convertDigits': convertDigits,
      'enableSecondTable': enableSecondTable,
      'elements': elements.map((e) => e.toJson()).toList(),
      'gradingScaleRules': gradingScaleRules,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DesignerTemplate.fromJson(Map<String, dynamic> json) {
    return DesignerTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      documentType: DocumentType.values.firstWhere(
        (e) => e.name == json['documentType'],
        orElse: () => DocumentType.custom,
      ),
      preset: CanvasPreset.values.firstWhere(
        (e) => e.name == json['preset'],
        orElse: () => CanvasPreset.cr80Vertical,
      ),
      widthMm: (json['widthMm'] as num).toDouble(),
      heightMm: (json['heightMm'] as num).toDouble(),
      backgroundColor: Color(json['backgroundColor'] as int? ?? 0xFFFFFFFF),
      backgroundColor2: Color(json['backgroundColor2'] as int? ?? 0xFF063A2A),
      isGradient: json['isGradient'] as bool? ?? false,
      borderColor: Color(json['borderColor'] as int? ?? 0xFFFFD700),
      borderWidth: (json['borderWidth'] as num?)?.toDouble() ?? 0.0,
      borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 8.0,
      backgroundImageFrontPath: json['backgroundImageFrontPath'] as String? ?? json['backgroundImagePath'] as String?,
      backgroundImageBackPath: json['backgroundImageBackPath'] as String?,
      useFrontTemplate: json['useFrontTemplate'] as bool? ?? false,
      useBackTemplate: json['useBackTemplate'] as bool? ?? false,
      cardLanguage: json['cardLanguage'] as String? ?? 'ur',
      isTransparentPageBg: json['isTransparentPageBg'] as bool? ?? false,
      convertDigits: json['convertDigits'] as bool? ?? true,
      enableSecondTable: json['enableSecondTable'] as bool? ?? false,
      elements: (json['elements'] as List<dynamic>? ?? [])
          .map((e) => DesignerElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      gradingScaleRules: json['gradingScaleRules'] != null
          ? Map<String, dynamic>.from(json['gradingScaleRules'] as Map)
          : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  DesignerTemplate copyWith({
    String? id,
    String? name,
    DocumentType? documentType,
    CanvasPreset? preset,
    double? widthMm,
    double? heightMm,
    Color? backgroundColor,
    Color? backgroundColor2,
    bool? isGradient,
    Color? borderColor,
    double? borderWidth,
    double? borderRadius,
    String? backgroundImageFrontPath,
    String? backgroundImageBackPath,
    bool? useFrontTemplate,
    bool? useBackTemplate,
    String? cardLanguage,
    bool? isTransparentPageBg,
    bool? convertDigits,
    bool? enableSecondTable,
    List<DesignerElement>? elements,
    Map<String, dynamic>? gradingScaleRules,
    DateTime? updatedAt,
  }) {
    return DesignerTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      documentType: documentType ?? this.documentType,
      preset: preset ?? this.preset,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundColor2: backgroundColor2 ?? this.backgroundColor2,
      isGradient: isGradient ?? this.isGradient,
      borderColor: borderColor ?? this.borderColor,
      borderWidth: borderWidth ?? this.borderWidth,
      borderRadius: borderRadius ?? this.borderRadius,
      backgroundImageFrontPath: backgroundImageFrontPath ?? this.backgroundImageFrontPath,
      backgroundImageBackPath: backgroundImageBackPath ?? this.backgroundImageBackPath,
      useFrontTemplate: useFrontTemplate ?? this.useFrontTemplate,
      useBackTemplate: useBackTemplate ?? this.useBackTemplate,
      cardLanguage: cardLanguage ?? this.cardLanguage,
      isTransparentPageBg: isTransparentPageBg ?? this.isTransparentPageBg,
      convertDigits: convertDigits ?? this.convertDigits,
      enableSecondTable: enableSecondTable ?? this.enableSecondTable,
      elements: elements ?? List.from(this.elements),
      gradingScaleRules: gradingScaleRules ?? this.gradingScaleRules,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}
