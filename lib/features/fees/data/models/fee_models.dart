class StudentFeeHeadItem {
  final String? feeTypeId;
  final String feeTypeName;
  final double amount;
  final double? originalAmount;
  final double? discountAmount;
  final String? discountTag;
  final String billingType; // 'one_time', 'monthly', 'yearly', 'custom'
  final int monthsCount;
  final List<String> monthsList;
  final double totalExpected;
  final double totalPaid;
  final double totalPending;

  StudentFeeHeadItem({
    this.feeTypeId,
    required this.feeTypeName,
    required this.amount,
    this.originalAmount,
    this.discountAmount = 0.0,
    this.discountTag,
    this.billingType = 'monthly',
    this.monthsCount = 12,
    this.monthsList = const [],
    required this.totalExpected,
    required this.totalPaid,
    required this.totalPending,
  });

  bool isDueInMonth(String monthName) {
    if (monthsList.isEmpty) {
      if (billingType == 'monthly') return true;
      return false;
    }
    final target = monthName.toLowerCase().trim();
    return monthsList.any((m) {
      final clean = m.toLowerCase().trim();
      return clean == target ||
          (clean.length >= 3 && target.length >= 3 && clean.substring(0, 3) == target.substring(0, 3));
    });
  }

  String get monthsDisplay {
    if (monthsList.isEmpty) {
      return billingType == 'monthly' ? 'All Months' : '$monthsCount Mo';
    }
    if (monthsList.length == 12) return 'All Months';
    return monthsList.map((m) => m.length > 3 ? m.substring(0, 3) : m).join(', ');
  }

  Map<String, dynamic> toJson() => {
    'fee_type_id': feeTypeId,
    'fee_type_name': feeTypeName,
    'amount': amount,
    'original_amount': originalAmount ?? amount,
    'discount_amount': discountAmount ?? 0.0,
    'discount_tag': discountTag,
    'billing_type': billingType,
    'months_count': monthsCount,
    'months_list': monthsList,
    'total_expected': totalExpected,
    'total_paid': totalPaid,
    'total_pending': totalPending,
  };

  factory StudentFeeHeadItem.fromJson(Map<String, dynamic> json) {
    final amt = (json['amount'] ?? 0).toDouble();
    final origAmt = (json['original_amount'] as num?)?.toDouble() ?? amt;
    final discAmt = (json['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final discTag = json['discount_tag']?.toString();
    final billing = json['billing_type'] ?? 'monthly';
    final months = (json['months_count'] != null)
        ? (json['months_count'] as num).toInt()
        : (billing == 'monthly' ? 12 : 1);
    final rawMonths = json['months_list'] ?? json['specific_months'];
    List<String> monthsList = [];
    if (rawMonths is List) {
      monthsList = rawMonths.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    double expected = (json['total_expected'] != null)
        ? (json['total_expected'] as num).toDouble()
        : (billing == 'monthly' ? amt * months : amt);
    double paid = (json['total_paid'] ?? 0).toDouble();
    double pending = (json['total_pending'] != null)
        ? (json['total_pending'] as num).toDouble()
        : (expected - paid).clamp(0.0, double.infinity);

    return StudentFeeHeadItem(
      feeTypeId: json['fee_type_id']?.toString(),
      feeTypeName: json['fee_type_name'] ?? json['fee_type'] ?? 'Fee',
      amount: amt,
      originalAmount: origAmt,
      discountAmount: discAmt,
      discountTag: discTag,
      billingType: billing,
      monthsCount: months,
      monthsList: monthsList,
      totalExpected: expected,
      totalPaid: paid,
      totalPending: pending,
    );
  }
}

class StudentFeeSummary {
  final String id;
  final String? grNo;
  final String fullName;
  final String? fatherName;
  final String? surname;
  final String? className;
  final double monthlyFees;
  final double totalExpected;
  final double totalPaid;
  final double totalPending;
  final String? mobileNo;
  final double? admissionFee;
  final double? bookFee;
  final double? contributorAmount;
  final double totalDiscount;
  final List<StudentFeeHeadItem> feeHeads;

  StudentFeeSummary({
    required this.id,
    this.grNo,
    required this.fullName,
    this.fatherName,
    this.surname,
    this.className,
    required this.monthlyFees,
    required this.totalExpected,
    required this.totalPaid,
    required this.totalPending,
    this.mobileNo,
    this.admissionFee,
    this.bookFee,
    this.contributorAmount,
    this.totalDiscount = 0.0,
    this.feeHeads = const [],
  });

  /// Full combined name: fullName + fatherName + surname
  String get displayName {
    final parts = <String>[
      fullName.trim(),
      if (fatherName != null && fatherName!.trim().isNotEmpty) fatherName!.trim(),
      if (surname != null && surname!.trim().isNotEmpty) surname!.trim(),
    ];
    final res = parts.join(' ').trim();
    return res.isNotEmpty ? res : fullName;
  }

  /// All configured fee types for this student as comma-separated string
  String get feeTypesDisplay {
    if (feeHeads.isEmpty) return 'Tuition Fee';
    return feeHeads.map((h) => h.feeTypeName).toSet().join(', ');
  }

  /// Fee types that have pending balance
  String get pendingFeeTypesDisplay {
    final pendingHeads = feeHeads.where((h) => h.totalPending > 0).toList();
    if (pendingHeads.isEmpty) return feeTypesDisplay;
    return pendingHeads.map((h) => h.feeTypeName).toSet().join(', ');
  }

  factory StudentFeeSummary.fromJson(Map<String, dynamic> json) {
    final rawHeads = (json['fee_heads'] ?? json['fee_breakdown']) as List?;
    final heads = rawHeads != null
        ? rawHeads.map((h) => StudentFeeHeadItem.fromJson(h as Map<String, dynamic>)).toList()
        : <StudentFeeHeadItem>[];

    double totalDisc = (json['contributor_amount'] as num?)?.toDouble() ?? 0.0;
    if (totalDisc <= 0 && heads.isNotEmpty) {
      totalDisc = heads.fold<double>(0.0, (sum, h) => sum + (h.discountAmount ?? 0.0));
    }

    return StudentFeeSummary(
      id: json['id'] ?? '',
      grNo: json['gr_no'],
      fullName: json['full_name'] ?? '',
      fatherName: json['father_name']?.toString(),
      surname: json['surname']?.toString(),
      className: json['class_name'],
      monthlyFees: (json['monthly_fees'] ?? 0).toDouble(),
      totalExpected: (json['total_expected'] ?? 0).toDouble(),
      totalPaid: (json['total_paid'] ?? 0).toDouble(),
      totalPending: (json['total_pending'] ?? 0).toDouble(),
      mobileNo: json['mobile_no'],
      admissionFee: (json['admission_fee'] as num?)?.toDouble(),
      bookFee: (json['book_fee'] as num?)?.toDouble(),
      contributorAmount: (json['contributor_amount'] as num?)?.toDouble(),
      totalDiscount: totalDisc,
      feeHeads: heads,
    );
  }
}

class FeePayment {
  final String id;
  final String studentId;
  final double amount;
  final String? paymentDate;
  final String feeType;
  final String status;
  final String? receiptNo;
  final String? remarks;
  final String? createdAt;

  FeePayment({
    required this.id,
    required this.studentId,
    required this.amount,
    this.paymentDate,
    required this.feeType,
    required this.status,
    this.receiptNo,
    this.remarks,
    this.createdAt,
  });

  factory FeePayment.fromJson(Map<String, dynamic> json) {
    return FeePayment(
      id: json['id']?.toString() ?? '',
      studentId: json['student_id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paymentDate: json['payment_date']?.toString(),
      feeType: json['fee_type']?.toString() ?? 'Tuition Fee',
      status: json['status']?.toString() ?? 'Paid',
      receiptNo: json['receipt_no']?.toString(),
      remarks: json['remarks']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'student_id': studentId,
    'amount': amount,
    'payment_date': paymentDate,
    'fee_type': feeType,
    'status': status,
    'receipt_no': receiptNo,
    'remarks': remarks,
    'created_at': createdAt,
  };
}

class Donation {
  final String id;
  final String? receiptNo;
  final String? donorName;
  final String? donorPhone;
  final String? village;
  final String? taluka;
  final String? district;
  final String? state;
  final String? country;
  final String? pinCode;
  final double amount;
  final String donationType;
  final String paymentMethod;
  final String? paymentDate;
  final String? createdAt;

  Donation({
    required this.id,
    this.receiptNo,
    this.donorName,
    this.donorPhone,
    this.village,
    this.taluka,
    this.district,
    this.state,
    this.country,
    this.pinCode,
    required this.amount,
    required this.donationType,
    required this.paymentMethod,
    this.paymentDate,
    this.createdAt,
  });

  String get displayReceiptNo {
    if (receiptNo != null && receiptNo!.trim().isNotEmpty) {
      return receiptNo!.trim();
    }
    return 'DN-${id.length > 5 ? id.substring(0, 5).toUpperCase() : id.toUpperCase()}';
  }

  String get fullLocation {
    final parts = [village, taluka, district, state, country]
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim())
        .toList();
    if (parts.isEmpty) return '-';
    return parts.join(', ');
  }

  factory Donation.fromJson(Map<String, dynamic> json) {
    return Donation(
      id: json['id']?.toString() ?? '',
      receiptNo: json['receipt_no']?.toString(),
      donorName: json['donor_name']?.toString(),
      donorPhone: json['donor_phone']?.toString(),
      village: json['village']?.toString(),
      taluka: json['taluka']?.toString(),
      district: json['district']?.toString(),
      state: json['state']?.toString(),
      country: json['country']?.toString() ?? 'India',
      pinCode: json['pin_code']?.toString(),
      amount: (json['amount'] ?? 0).toDouble(),
      donationType: json['donation_type']?.toString() ?? '',
      paymentMethod: json['payment_method']?.toString() ?? 'Cash',
      paymentDate: json['payment_date']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

class DonationType {
  final String id;
  final String name;

  DonationType({
    required this.id,
    required this.name,
  });

  factory DonationType.fromJson(Map<String, dynamic> json) {
    return DonationType(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
    );
  }
}

class FeeType {
  final String id;
  final String name;
  final String billingType; // 'one_time', 'monthly', 'yearly', 'custom'
  final int defaultMonths;
  final double defaultAmount;
  final List<String> monthsList;

  FeeType({
    required this.id,
    required this.name,
    this.billingType = 'monthly',
    this.defaultMonths = 12,
    this.defaultAmount = 0.0,
    this.monthsList = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'billing_type': billingType,
    'default_months': defaultMonths,
    'default_amount': defaultAmount,
    'months_list': monthsList,
  };

  factory FeeType.fromJson(Map<String, dynamic> json) {
    final rawName = (json['name'] ?? '').toString();
    final lower = rawName.toLowerCase();
    String defaultBilling = 'monthly';
    int defMonths = 12;
    if (lower.contains('admission') || lower.contains('registration') || lower.contains('dakhila')) {
      defaultBilling = 'one_time';
      defMonths = 1;
    } else if (lower.contains('book') || lower.contains('kitab') || lower.contains('nisab') || lower.contains('annual')) {
      defaultBilling = 'yearly';
      defMonths = 1;
    }

    final rawMonths = json['months_list'] ?? json['specific_months'];
    List<String> parsedMonths = [];
    if (rawMonths is List) {
      parsedMonths = rawMonths.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }

    return FeeType(
      id: json['id'] ?? '',
      name: rawName,
      billingType: json['billing_type'] ?? defaultBilling,
      defaultMonths: (json['default_months'] as num?)?.toInt() ?? defMonths,
      defaultAmount: (json['default_amount'] as num?)?.toDouble() ?? 0.0,
      monthsList: parsedMonths,
    );
  }
}

class DonorSummary {
  final String donorKey;
  final String donorName;
  final String? donorPhone;
  final String? village;
  final String? taluka;
  final String? district;
  final String? state;
  final String? country;
  final String? pinCode;
  final double totalDonated;
  final int totalCount;
  final Donation latestDonation;
  final List<Donation> donations;

  DonorSummary({
    required this.donorKey,
    required this.donorName,
    this.donorPhone,
    this.village,
    this.taluka,
    this.district,
    this.state,
    this.country,
    this.pinCode,
    required this.totalDonated,
    required this.totalCount,
    required this.latestDonation,
    required this.donations,
  });

  String get displayPhone => donorPhone?.trim().isNotEmpty == true ? donorPhone!.trim() : '-';

  String get fullLocation {
    final parts = [village, taluka, district, state]
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim())
        .toList();
    if (parts.isEmpty) return '-';
    return parts.join(', ');
  }

  static List<DonorSummary> groupDonationsByDonor(List<Donation> rawDonations) {
    final Map<String, List<Donation>> grouped = {};
    for (final d in rawDonations) {
      final name = (d.donorName ?? 'Anonymous').trim();
      final key = name.toLowerCase();
      grouped.putIfAbsent(key, () => []).add(d);
    }

    final List<DonorSummary> summaries = [];
    grouped.forEach((key, list) {
      // Sort donations newest first
      list.sort((a, b) {
        final da = a.paymentDate != null ? DateTime.tryParse(a.paymentDate!) : null;
        final db = b.paymentDate != null ? DateTime.tryParse(b.paymentDate!) : null;
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });

      final latest = list.first;
      final total = list.fold<double>(0.0, (sum, d) => sum + d.amount);

      // Best available contact / address info from list if latest is empty
      String? phone = latest.donorPhone;
      String? village = latest.village;
      String? taluka = latest.taluka;
      String? district = latest.district;
      String? state = latest.state;
      String? country = latest.country;
      String? pinCode = latest.pinCode;

      for (final d in list) {
        if ((phone == null || phone.isEmpty) && d.donorPhone != null && d.donorPhone!.isNotEmpty) phone = d.donorPhone;
        if ((village == null || village.isEmpty) && d.village != null && d.village!.isNotEmpty) village = d.village;
        if ((taluka == null || taluka.isEmpty) && d.taluka != null && d.taluka!.isNotEmpty) taluka = d.taluka;
        if ((district == null || district.isEmpty) && d.district != null && d.district!.isNotEmpty) district = d.district;
        if ((state == null || state.isEmpty) && d.state != null && d.state!.isNotEmpty) state = d.state;
        if ((country == null || country.isEmpty) && d.country != null && d.country!.isNotEmpty) country = d.country;
        if ((pinCode == null || pinCode.isEmpty) && d.pinCode != null && d.pinCode!.isNotEmpty) pinCode = d.pinCode;
      }

      summaries.add(DonorSummary(
        donorKey: key,
        donorName: latest.donorName?.trim().isNotEmpty == true ? latest.donorName!.trim() : 'Anonymous',
        donorPhone: phone,
        village: village,
        taluka: taluka,
        district: district,
        state: state,
        country: country ?? 'India',
        pinCode: pinCode,
        totalDonated: total,
        totalCount: list.length,
        latestDonation: latest,
        donations: list,
      ));
    });

    return summaries;
  }
}
