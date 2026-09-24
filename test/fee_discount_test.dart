import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/services/fee_condition_settings.dart';
import 'package:madarsa_app/features/fees/data/models/fee_models.dart';

void main() {
  group('Fee Condition Settings Discount Tests', () {
    final fields = [
      FeeConditionFieldConfig(
        id: 'monthly_fees',
        label: 'Monthly Fees (₹)',
        fieldType: 'number',
        mathAction: 'add',
      ),
      FeeConditionFieldConfig(
        id: 'admission_fee',
        label: 'Admission Fee (₹)',
        fieldType: 'number',
        mathAction: 'add',
      ),
      FeeConditionFieldConfig(
        id: 'discount_1',
        label: 'Staff Discount',
        fieldType: 'number',
        mathAction: 'discount',
        targetFeeField: 'all',
      ),
    ];

    test('calculates percentage discount on specific targeted fee (monthly fees)', () {
      final rawValues = {
        'monthly_fees': '1000',
        'admission_fee': '500',
        'discount_1': '70%',
      };
      // Student form targets Monthly Fees specifically
      final targets = {
        'discount_1': 'monthly_fees',
      };

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fields,
        rawFieldValues: rawValues,
        fieldTargets: targets,
      );

      // Monthly Fees = 1000, Admission = 500. Gross = 1500.
      // 70% of 1000 = 700.
      // Net = 1500 - 700 = 800.
      expect(result.grossTotal, 1500.0);
      expect(result.fieldDeductions['discount_1'], 700.0);
      expect(result.totalDeductions, 700.0);
      expect(result.netTotal, 800.0);
    });

    test('calculates percentage discount on All Fees (Total)', () {
      final rawValues = {
        'monthly_fees': '1000',
        'admission_fee': '500',
        'discount_1': '70%',
      };
      // Student form targets All Fees
      final targets = {
        'discount_1': 'all',
      };

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fields,
        rawFieldValues: rawValues,
        fieldTargets: targets,
      );

      // Gross = 1500. 70% of 1500 = 1050. Net = 450.
      expect(result.grossTotal, 1500.0);
      expect(result.fieldDeductions['discount_1'], 1050.0);
      expect(result.totalDeductions, 1050.0);
      expect(result.netTotal, 450.0);
    });

    test('calculates flat amount discount', () {
      final rawValues = {
        'monthly_fees': '1000',
        'admission_fee': '500',
        'discount_1': '300',
      };
      final targets = {
        'discount_1': 'monthly_fees',
      };

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fields,
        rawFieldValues: rawValues,
        fieldTargets: targets,
      );

      // Gross = 1500, Flat deduction = 300, Net = 1200.
      expect(result.grossTotal, 1500.0);
      expect(result.fieldDeductions['discount_1'], 300.0);
      expect(result.totalDeductions, 300.0);
      expect(result.netTotal, 1200.0);
    });

    test('calculates discount on admission fee target with fallback parameter', () {
      final rawValues = {
        'discount_1': '50%',
      };
      final targets = {
        'discount_1': 'admission_fee',
      };

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fields,
        rawFieldValues: rawValues,
        fieldTargets: targets,
        fallbackMonthlyFee: 1000.0,
        fallbackAdmissionFee: 600.0,
      );

      // Gross = 1000 + 600 = 1600. 50% of 600 (admission) = 300. Net = 1300.
      expect(result.grossTotal, 1600.0);
      expect(result.fieldDeductions['discount_1'], 300.0);
      expect(result.netTotal, 1300.0);
    });

    test('empty discount field results in strictly 0 deduction even if fallbackContributorAmount is 100', () {
      final rawValues = {
        'monthly_fees': '1200',
        'admission_fee': '100',
        'discount_1': '',
      };
      final targets = {
        'discount_1': 'all',
      };

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fields,
        rawFieldValues: rawValues,
        fieldTargets: targets,
        fallbackContributorAmount: 100.0,
      );

      // Condition has deduction fields, but user left discount empty => discount must be strictly 0!
      expect(result.grossTotal, 1300.0);
      expect(result.totalDeductions, 0.0);
      expect(result.netTotal, 1300.0);
      expect(result.fieldDeductions.isEmpty, true);
    });

    test('calculates percentage discount using fieldDiscountModes with pure numeric input (e.g. 5 without % symbol)', () {
      final rawValues = {
        'monthly_fees': '1200',
        'admission_fee': '100',
        'discount_1': '5',
      };
      final targets = {
        'discount_1': 'all',
      };
      final modes = {
        'discount_1': 'percentage',
      };

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fields,
        rawFieldValues: rawValues,
        fieldTargets: targets,
        fieldDiscountModes: modes,
      );

      // Gross = 1300. 5% of 1300 = 65. Net = 1235.
      expect(result.grossTotal, 1300.0);
      expect(result.fieldDeductions['discount_1'], 65.0);
      expect(result.totalDeductions, 65.0);
      expect(result.netTotal, 1235.0);
    });

    test('calculates flat 10 rupee discount on 1900 total (1200+100+500+100) exactly without rounding overflow', () {
      final customFields = [
        FeeConditionFieldConfig(
          id: 'monthly_fees',
          label: 'Monthly Fees (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'admission_fee',
          label: 'Admission Fee (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'book_fee',
          label: 'Book Fee (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'exam_fee',
          label: 'Exam Fee (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'discount_total',
          label: 'Discount',
          fieldType: 'number',
          mathAction: 'discount',
          targetFeeField: 'all',
        ),
      ];

      final rawValues = {
        'monthly_fees': '1200',
        'admission_fee': '100',
        'book_fee': '500',
        'exam_fee': '100',
        'discount_total': '10',
      };

      final result = FeeConditionSettings.calculateConditionFees(
        fields: customFields,
        rawFieldValues: rawValues,
        fieldTargets: {'discount_total': 'all'},
      );

      expect(result.grossTotal, 1900.0);
      expect(result.totalDeductions, 10.0);
      expect(result.netTotal, 1890.0);
    });

    test('StudentFeeHeadItem and StudentFeeSummary parse discount fields correctly', () {
      final json = {
        'id': 'std_123',
        'student_id': 'std_123',
        'student_name': 'Ahmad Raza',
        'monthly_fees': 1194,
        'total_expected': 1890,
        'total_paid': 500,
        'total_pending': 1390,
        'fee_heads': [
          {
            'fee_type_id': 'fee_monthly',
            'fee_type_name': 'Monthly Fee',
            'amount': 1194,
            'original_amount': 1200,
            'discount_amount': 6,
            'discount_tag': 'Staff Disc (₹6)',
            'billing_type': 'monthly',
            'months_count': 12,
            'total_expected': 14328,
            'total_paid': 500,
            'total_pending': 13828,
          },
          {
            'fee_type_id': 'fee_admission',
            'fee_type_name': 'Admission Fee',
            'amount': 99,
            'original_amount': 100,
            'discount_amount': 1,
            'discount_tag': 'Staff Disc (₹1)',
            'billing_type': 'one_time',
            'months_count': 1,
            'total_expected': 99,
            'total_paid': 0,
            'total_pending': 99,
          },
          {
            'fee_type_id': 'fee_book',
            'fee_type_name': 'Book Fee',
            'amount': 497,
            'original_amount': 500,
            'discount_amount': 3,
            'discount_tag': 'Staff Disc (₹3)',
            'billing_type': 'one_time',
            'months_count': 1,
            'total_expected': 497,
            'total_paid': 0,
            'total_pending': 497,
          },
        ],
      };

      // Also import fee_models
      final summary = StudentFeeSummary.fromJson(json);
      expect(summary.totalDiscount, 10.0);
      expect(summary.feeHeads.length, 3);
      expect(summary.feeHeads[0].originalAmount, 1200.0);
      expect(summary.feeHeads[0].discountAmount, 6.0);
      expect(summary.feeHeads[0].discountTag, 'Staff Disc (₹6)');
      expect(summary.feeHeads[1].discountAmount, 1.0);
      expect(summary.feeHeads[2].discountAmount, 3.0);
    });

    test('dual discount formatting calculates equivalent percent and amount accurately', () {
      String formatDiscount(double disc, double orig, String tag) {
        final pct = orig > 0 ? (disc / orig) * 100.0 : 0.0;
        String pctStr = pct.toStringAsFixed(pct < 1 ? 2 : 1);
        if (pct == pct.truncateToDouble()) {
          pctStr = '${pct.toInt()}%';
        } else if (pctStr.contains('.')) {
          pctStr = '${pctStr.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}%';
        } else {
          pctStr = '$pctStr%';
        }

        if (tag.isNotEmpty && tag.contains('%')) return tag;
        if (tag.isNotEmpty) return '$tag ($pctStr)';
        return pct > 0 ? '- ₹${disc.toStringAsFixed(0)} ($pctStr)' : '- ₹${disc.toStringAsFixed(0)}';
      }

      // Flat 6 on 1200 Monthly Fee -> equivalent 0.5%
      expect(formatDiscount(6, 1200, ''), '- ₹6 (0.5%)');

      // Flat 100 on 1000 Monthly Fee -> equivalent 10%
      expect(formatDiscount(100, 1000, ''), '- ₹100 (10%)');

      // Flat 10 on 1900 Total Expected -> equivalent 0.53%
      expect(formatDiscount(10, 1900, ''), '- ₹10 (0.53%)');

      // Percentage already formatted in tag
      expect(formatDiscount(100, 1000, '-₹100 (10%)'), '-₹100 (10%)');
    });

    test('condition with custom add field (Amount) and All Fees discount calculates correctly', () {
      final customFields = [
        FeeConditionFieldConfig(
          id: 'monthly_fees',
          label: 'Monthly Fees (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'field_amount',
          label: 'Amount (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'discount_partial',
          label: 'Discount',
          fieldType: 'number',
          mathAction: 'discount',
          targetFeeField: 'all',
        ),
      ];

      final rawValues = {
        'monthly_fees': '3500',
        'field_amount': '100',
        'discount_partial': '10',
      };

      final result = FeeConditionSettings.calculateConditionFees(
        fields: customFields,
        rawFieldValues: rawValues,
        fieldTargets: {'discount_partial': 'all'},
      );

      expect(result.grossTotal, 3600.0);
      expect(result.totalDeductions, 10.0);
      expect(result.netTotal, 3590.0);
      expect(result.fieldAmounts['monthly_fees'], 3500.0);
      expect(result.fieldAmounts['field_amount'], 100.0);
    });

    test('condition with custom add field targeted specifically applies discount to that field only', () {
      final customFields = [
        FeeConditionFieldConfig(
          id: 'monthly_fees',
          label: 'Monthly Fees (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'field_amount',
          label: 'Amount (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'discount_partial',
          label: 'Discount',
          fieldType: 'number',
          mathAction: 'discount',
        ),
      ];

      final rawValues = {
        'monthly_fees': '3500',
        'field_amount': '100',
        'discount_partial': '10',
      };

      // Specifically target "field_amount"
      final result = FeeConditionSettings.calculateConditionFees(
        fields: customFields,
        rawFieldValues: rawValues,
        fieldTargets: {'discount_partial': 'field_amount'},
      );

      expect(result.grossTotal, 3600.0);
      expect(result.totalDeductions, 10.0);
      expect(result.netTotal, 3590.0);
      expect(result.fieldDeductions['discount_partial'], 10.0);
    });

    test('condition without deduction fields has strictly 0 deductions and ignores fallback contributor amount', () {
      final noDeductionFields = [
        FeeConditionFieldConfig(
          id: 'monthly_fees',
          label: 'Monthly Fees (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
      ];

      final result = FeeConditionSettings.calculateConditionFees(
        fields: noDeductionFields,
        rawFieldValues: {'monthly_fees': '1500'},
        fallbackContributorAmount: 200.0, // Leftover discount from previous condition
      );

      expect(result.grossTotal, 1500.0);
      expect(result.totalDeductions, 0.0);
      expect(result.netTotal, 1500.0);
      expect(result.fieldDeductions.isEmpty, true);
    });

    test('contributor amount field with mathAction "none" is neutral (no fee impact) while preserving entered value', () {
      final fieldsWithNeutralContributor = [
        FeeConditionFieldConfig(
          id: 'monthly_fees',
          label: 'Monthly Fees (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'contributor_id',
          label: 'Contributor Name',
          fieldType: 'contributor',
          mathAction: 'none',
          fieldSource: 'contributor',
        ),
        FeeConditionFieldConfig(
          id: 'contributor_amount',
          label: 'Contributor Amount (₹)',
          fieldType: 'number',
          mathAction: 'none',
          fieldSource: 'contributor',
          targetFeeField: 'all',
        ),
      ];

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fieldsWithNeutralContributor,
        rawFieldValues: {
          'monthly_fees': '1200',
          'contributor_amount': '1200',
        },
      );

      // Math action is 'none', so student fee is unchanged (Gross = 1200, Deductions = 0, Net = 1200)
      expect(result.grossTotal, 1200.0);
      expect(result.totalDeductions, 0.0);
      expect(result.netTotal, 1200.0);
    });

    test('contributor amount field with mathAction "subtract" properly deducts as concession', () {
      final fieldsWithDeductContributor = [
        FeeConditionFieldConfig(
          id: 'monthly_fees',
          label: 'Monthly Fees (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'contributor_id',
          label: 'Contributor Name',
          fieldType: 'contributor',
          mathAction: 'none',
          fieldSource: 'contributor',
        ),
        FeeConditionFieldConfig(
          id: 'contributor_amount',
          label: 'Contributor Amount (₹)',
          fieldType: 'number',
          mathAction: 'subtract',
          fieldSource: 'contributor',
          targetFeeField: 'all',
        ),
      ];

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fieldsWithDeductContributor,
        rawFieldValues: {
          'monthly_fees': '1500',
          'contributor_amount': '500',
        },
      );

      expect(result.grossTotal, 1500.0);
      expect(result.totalDeductions, 500.0);
      expect(result.netTotal, 1000.0);
      expect(result.fieldDeductions['contributor_amount'], 500.0);
    });

    test('staff concession field with mathAction "discount" (percentage) calculates correctly', () {
      final fieldsWithStaffDiscount = [
        FeeConditionFieldConfig(
          id: 'monthly_fees',
          label: 'Monthly Fees (₹)',
          fieldType: 'number',
          mathAction: 'add',
        ),
        FeeConditionFieldConfig(
          id: 'staff_id',
          label: 'Staff Member Name',
          fieldType: 'staff',
          mathAction: 'none',
          fieldSource: 'staff',
        ),
        FeeConditionFieldConfig(
          id: 'staff_discount',
          label: 'Staff Concession (₹)',
          fieldType: 'number',
          mathAction: 'discount',
          fieldSource: 'staff',
          targetFeeField: 'all',
          discountMode: 'percentage',
        ),
      ];

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fieldsWithStaffDiscount,
        rawFieldValues: {
          'monthly_fees': '2000',
          'staff_discount': '50%',
        },
      );

      expect(result.grossTotal, 2000.0);
      expect(result.totalDeductions, 1000.0);
      expect(result.netTotal, 1000.0);
      expect(result.fieldDeductions['staff_discount'], 1000.0);
    });

    test('user scenario: monthly fee 500 * 12 months = 6000, 10% discount = 5400, net monthly = 450', () {
      final fields = [
        FeeConditionFieldConfig(
          id: 'monthly_fees',
          label: 'Monthly Fees (₹)',
          fieldType: 'number',
          mathAction: 'add',
          billingType: 'monthly',
          billingMonths: 12,
        ),
        FeeConditionFieldConfig(
          id: 'discount_1',
          label: 'Concession Discount',
          fieldType: 'number',
          mathAction: 'discount',
          targetFeeField: 'monthly_fees',
          discountMode: 'percentage',
          billingType: 'monthly',
          billingMonths: 12,
        ),
      ];

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fields,
        rawFieldValues: {
          'monthly_fees': '500',
          'discount_1': '10%',
        },
        sessionMonths: 12,
      );

      // Monthly unit fee = 500
      expect(result.fieldAmounts['monthly_fees'], 500.0);
      // Annual gross = 500 * 12 = 6000
      expect(result.annualFieldAmounts['monthly_fees'], 6000.0);
      expect(result.annualGrossTotal, 6000.0);
      // 10% discount on 6000 = 600 annual deduction (50/month)
      expect(result.annualTotalDeductions, 600.0);
      expect(result.fieldDeductions['discount_1'], 50.0);
      // Annual net total = 6000 - 600 = 5400
      expect(result.annualNetTotal, 5400.0);
      // Net monthly payable = 5400 / 12 = 450
      expect(result.monthlyNetPayable, 450.0);
    });

    test('calculateSessionMonths correctly computes months from academic session dates', () {
      // 1 full year from Jan 1 to Dec 31
      final config1 = {
        'start_date': '2026-01-01',
        'end_date': '2026-12-31',
      };
      expect(FeeConditionSettings.calculateSessionMonths(config1), 12);

      // Indian standard academic year from April 1 to March 31
      final config2 = {
        'start_date': '2026-04-01',
        'end_date': '2027-03-31',
      };
      expect(FeeConditionSettings.calculateSessionMonths(config2), 12);

      // Half year / 6 months
      final config3 = {
        'start_date': '2026-07-01',
        'end_date': '2026-12-31',
      };
      expect(FeeConditionSettings.calculateSessionMonths(config3), 6);

      // Fallback if null
      expect(FeeConditionSettings.calculateSessionMonths(null), 12);
    });

    test('contributor amount field allows numeric amount input without being confused for dropdown', () {
      final config = FeeConditionFieldConfig(
        id: 'contributor_amount',
        label: 'Contributor Amount (₹)',
        fieldType: 'number',
        mathAction: 'subtract',
        fieldSource: 'contributor',
      );

      // Even if fieldSource is 'contributor', because fieldType is 'number', isContributor must be false
      // so student form renders a numeric TextField rather than a dropdown!
      expect(config.isContributor, false);
      expect(config.isStaff, false);
    });

    test('staff concession field allows numeric amount input without being confused for dropdown', () {
      final config = FeeConditionFieldConfig(
        id: 'staff_discount',
        label: 'Staff Concession (₹)',
        fieldType: 'number',
        mathAction: 'subtract',
        fieldSource: 'staff',
      );

      // Because fieldType is 'number', isStaff must be false!
      expect(config.isStaff, false);
      expect(config.isContributor, false);
    });

    test('dynamically resolves custom billing frequencies from BillingFrequencySettings', () {
      final customFrequencies = [
        const BillingFrequencyOption(id: 'monthly', name: 'Monthly', months: 1),
        const BillingFrequencyOption(id: 'session_10', name: 'Session', months: 10),
        const BillingFrequencyOption(id: 'term_1', name: 'Term 1', months: 4),
        const BillingFrequencyOption(id: 'custom_aaa', name: 'aaa', months: 0),
      ];

      final fields = [
        FeeConditionFieldConfig(
          id: 'tuition_fee',
          label: 'Tuition Fee (₹)',
          fieldType: 'number',
          mathAction: 'add',
          billingType: 'session',
        ),
        FeeConditionFieldConfig(
          id: 'term_fee',
          label: 'Term 1 Exam Fee (₹)',
          fieldType: 'number',
          mathAction: 'add',
          billingType: 'term_1',
        ),
        FeeConditionFieldConfig(
          id: 'discount_1',
          label: 'Session Discount',
          fieldType: 'number',
          mathAction: 'discount',
          targetFeeField: 'tuition_fee',
          discountMode: 'percentage',
          billingType: 'session',
        ),
      ];

      final result = FeeConditionSettings.calculateConditionFees(
        fields: fields,
        rawFieldValues: {
          'tuition_fee': '600',
          'term_fee': '250',
          'discount_1': '10%',
        },
        sessionMonths: 10,
        frequencies: customFrequencies,
      );

      // Tuition Fee = 600 * 10 = 6000
      expect(result.fieldAmounts['tuition_fee'], 600.0);
      expect(result.annualFieldAmounts['tuition_fee'], 6000.0);
      expect(result.fieldBillingMonths['tuition_fee'], 10);

      // Term 1 Fee = 250 * 4 = 1000
      expect(result.fieldAmounts['term_fee'], 250.0);
      expect(result.annualFieldAmounts['term_fee'], 1000.0);
      expect(result.fieldBillingMonths['term_fee'], 4);

      // Annual Gross = 6000 + 1000 = 7000
      expect(result.annualGrossTotal, 7000.0);

      // 10% Discount on Tuition Fee (6000) = 600 annual deduction
      expect(result.annualTotalDeductions, 600.0);

      // Annual Net Total = 7000 - 600 = 6400
      expect(result.annualNetTotal, 6400.0);

      // Monthly Net Tuition Payable = (6000 - 600) / 10 = 540
      expect(result.monthlyNetPayable, 540.0);
    });

    test('BillingFrequencyOption serializes and resolves specific monthsList correctly', () {
      const option = BillingFrequencyOption(
        id: 'quarterly_custom',
        name: 'Quarterly Custom',
        months: 3,
        monthsList: ['January', 'April', 'July'],
      );

      expect(option.months, 3);
      expect(option.monthsList, ['January', 'April', 'July']);
      expect(option.monthsDisplay, 'Jan, Apr, Jul');
      expect(option.isDueInMonth('January'), isTrue);
      expect(option.isDueInMonth('jan'), isTrue);
      expect(option.isDueInMonth('April'), isTrue);
      expect(option.isDueInMonth('July'), isTrue);
      expect(option.isDueInMonth('February'), isFalse);
      expect(option.isDueInMonth('December'), isFalse);

      final json = option.toJson();
      expect(json['months_list'], ['January', 'April', 'July']);

      final restored = BillingFrequencyOption.fromJson(json);
      expect(restored.id, 'quarterly_custom');
      expect(restored.months, 3);
      expect(restored.monthsList, ['January', 'April', 'July']);
      expect(restored.monthsDisplay, 'Jan, Apr, Jul');
    });

    test('StudentFeeHeadItem parses months_list and checks isDueInMonth correctly', () {
      final item = StudentFeeHeadItem.fromJson({
        'fee_type_id': 'exam_fee',
        'fee_type_name': 'Exam Fee',
        'amount': 500,
        'billing_type': 'custom',
        'months_count': 2,
        'months_list': ['March', 'September'],
        'total_expected': 1000,
        'total_paid': 0,
        'total_pending': 1000,
      });

      expect(item.feeTypeName, 'Exam Fee');
      expect(item.monthsCount, 2);
      expect(item.monthsList, ['March', 'September']);
      expect(item.monthsDisplay, 'Mar, Sep');
      expect(item.isDueInMonth('September'), isTrue);
      expect(item.isDueInMonth('sep'), isTrue);
      expect(item.isDueInMonth('March'), isTrue);
      expect(item.isDueInMonth('October'), isFalse);

      final json = item.toJson();
      expect(json['months_list'], ['March', 'September']);

      final restored = StudentFeeHeadItem.fromJson(json);
      expect(restored.monthsList, ['March', 'September']);
      expect(restored.isDueInMonth('September'), isTrue);
    });

    test('FeeType and FeeConditionFieldConfig store and parse monthsList properly', () {
      final feeType = FeeType(
        id: 'sports_fee',
        name: 'Sports Fee',
        billingType: 'custom',
        defaultMonths: 1,
        defaultAmount: 300,
        monthsList: ['August'],
      );

      final feeTypeJson = feeType.toJson();
      expect(feeTypeJson['months_list'], ['August']);
      final restoredFeeType = FeeType.fromJson(feeTypeJson);
      expect(restoredFeeType.monthsList, ['August']);

      final fieldConfig = FeeConditionFieldConfig(
        id: 'field_annual',
        label: 'Annual Function Fee',
        fieldType: 'number',
        mathAction: 'add',
        billingType: 'custom',
        billingMonths: 1,
        monthsList: ['December'],
      );

      final fieldConfigJson = fieldConfig.toJson();
      expect(fieldConfigJson['months_list'], ['December']);
      final restoredConfig = FeeConditionFieldConfig.fromJson(fieldConfigJson);
      expect(restoredConfig.monthsList, ['December']);
    });
  });
}
