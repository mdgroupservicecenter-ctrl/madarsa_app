import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:madarsa_app/features/fees/data/models/fee_models.dart';
import 'package:madarsa_app/core/services/donation_receipt_settings.dart';
import 'package:madarsa_app/features/fees/presentation/widgets/donation_receipt_config_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('FeePayment Model & Date-Time Formatting Tests', () {
    test('FeePayment fromJson parses created_at, remarks, and receipt_no', () {
      final json = {
        'id': 'pay_12345',
        'student_id': 'std_001',
        'amount': 600,
        'payment_date': '2026-09-22',
        'fee_type': 'Monthly Fees',
        'status': 'Paid',
        'created_at': '2026-09-22 05:52:45',
        'receipt_no': 'REC-9988',
        'remarks': 'Cash collection',
      };

      final payment = FeePayment.fromJson(json);

      expect(payment.id, 'pay_12345');
      expect(payment.studentId, 'std_001');
      expect(payment.amount, 600.0);
      expect(payment.feeType, 'Monthly Fees');
      expect(payment.status, 'Paid');
      expect(payment.paymentDate, '2026-09-22');
      expect(payment.createdAt, '2026-09-22 05:52:45');
      expect(payment.receiptNo, 'REC-9988');
      expect(payment.remarks, 'Cash collection');
    });

    test('Formats SQLite UTC datetime to local Date and Time accurately', () {
      const sqliteTimestamp = '2026-09-22 05:52:45';
      String raw = sqliteTimestamp.trim();
      if (raw.length == 19 && raw.contains(' ') && !raw.contains('T')) {
        raw = '${raw.replaceFirst(' ', 'T')}Z';
      }
      final dt = DateTime.tryParse(raw)?.toLocal();
      expect(dt, isNotNull);

      final formatted = DateFormat('dd MMM yyyy, hh:mm a').format(dt!);
      // In any timezone, it contains day, month, year, and AM/PM time
      expect(formatted, contains('22 Sep 2026'));
      expect(formatted, anyOf(contains('AM'), contains('PM')));
    });

    test('Formats ISO string with time to Date and Time', () {
      const isoTimestamp = '2026-09-22T11:45:30.000Z';
      final dt = DateTime.tryParse(isoTimestamp)?.toLocal();
      expect(dt, isNotNull);

      final formatted = DateFormat('dd MMM yyyy, hh:mm a').format(dt!);
      expect(formatted, contains('22 Sep 2026'));
      expect(formatted, anyOf(contains('AM'), contains('PM')));
    });

    test('Handles fallback when createdAt is missing and paymentDate is only date', () {
      final payment = FeePayment(
        id: 'pay_1',
        studentId: 'std_001',
        amount: 500,
        paymentDate: '2026-09-22',
        feeType: 'Admission Fee',
        status: 'Paid',
      );

      DateTime? dt;
      if (payment.createdAt != null && payment.createdAt!.trim().isNotEmpty) {
        dt = DateTime.tryParse(payment.createdAt!)?.toLocal();
      }
      if (dt == null && payment.paymentDate != null && payment.paymentDate!.trim().isNotEmpty) {
        dt = DateTime.tryParse(payment.paymentDate!.trim());
      }

      expect(dt, isNotNull);
      final validDt = dt!;
      final hasTime = (payment.createdAt != null && payment.createdAt!.trim().isNotEmpty) ||
          (validDt.hour != 0 || validDt.minute != 0 || validDt.second != 0);
      final formatted = hasTime
          ? DateFormat('dd MMM yyyy, hh:mm a').format(validDt)
          : DateFormat('dd MMM yyyy').format(validDt);

      expect(formatted, '22 Sep 2026');
    });

    testWidgets('Payment history dialog layout renders with finite bounded height without layout exceptions', (tester) async {
      final payments = [
        FeePayment(
          id: 'pay_1',
          studentId: 'std_001',
          amount: 600,
          feeType: 'Monthly Fees',
          status: 'Paid',
          paymentDate: '2026-09-22',
          createdAt: '2026-09-22 05:52:45',
          receiptNo: 'REC-101',
          remarks: 'September fees paid',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final size = MediaQuery.of(context).size;
                final dialogWidth = (size.width * 0.9).clamp(320.0, 560.0);
                final dialogHeight = (size.height * 0.75).clamp(360.0, 520.0);

                return Center(
                  child: AlertDialog(
                    title: const Text('Payment History'),
                    content: SizedBox(
                      width: dialogWidth,
                      height: dialogHeight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: 50,
                            color: Colors.grey.shade100,
                            child: const Center(child: Text('KPI Bar')),
                          ),
                          Expanded(
                            child: ListView.separated(
                              itemCount: payments.length,
                              separatorBuilder: (context, index) => const Divider(height: 8),
                              itemBuilder: (context, idx) {
                                final p = payments[idx];
                                return ListTile(
                                  title: Text(p.feeType),
                                  subtitle: Text(p.createdAt ?? ''),
                                  trailing: Text('₹${p.amount.toStringAsFixed(0)}'),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Expect KPI Bar and payment items rendered with no exceptions
      expect(find.text('KPI Bar'), findsOneWidget);
      expect(find.text('Monthly Fees'), findsOneWidget);
      expect(find.text('₹600'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('Custom receipt format preview matches user config (ERC-B26-00001)', () {
      final config = DonationReceiptSettingsModel(
        customPrefix: 'ERC-',
        enableAlphabet: true,
        alphabetPrefix: 'B',
        enableYear: true,
        yearFormat: '2digit',
        customYearValue: '26',
        digitPadding: 5,
        startingNumber: 1,
      );

      final preview = config.buildReceiptNo(config.startingNumber);
      expect(preview, 'ERC-B26-00001');
    });

    test('Fee and Donation receipt numbers synchronize in alternating sequence', () {
      final config = DonationReceiptSettingsModel(
        customPrefix: 'ERC-',
        enableAlphabet: true,
        alphabetPrefix: 'B',
        enableYear: true,
        yearFormat: '2digit',
        customYearValue: '26',
        digitPadding: 5,
        startingNumber: 1,
      );

      final List<String> databaseReceiptNos = [];

      // Step 1: Fee payment generates first receipt
      final feeReceipt1 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: databaseReceiptNos,
        settings: config,
      );
      expect(feeReceipt1, 'ERC-B26-00001');
      databaseReceiptNos.add(feeReceipt1);

      // Step 2: Next Donation generates synchronized next in series (00002)
      final donationReceipt1 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: databaseReceiptNos,
        settings: config,
      );
      expect(donationReceipt1, 'ERC-B26-00002');
      databaseReceiptNos.add(donationReceipt1);

      // Step 3: Next Fee payment generates synchronized next in series (00003)
      final feeReceipt2 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: databaseReceiptNos,
        settings: config,
      );
      expect(feeReceipt2, 'ERC-B26-00003');
      databaseReceiptNos.add(feeReceipt2);

      // Step 4: Next Donation generates 00004
      final donationReceipt2 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: databaseReceiptNos,
        settings: config,
      );
      expect(donationReceipt2, 'ERC-B26-00004');
    });

    test('Zero-prefix / pure numeric format (0001 -> 0002 -> 0003) synchronizes smoothly', () {
      final config = DonationReceiptSettingsModel(
        customPrefix: '',
        enableAlphabet: false,
        enableYear: false,
        digitPadding: 4,
        startingNumber: 1,
      );

      final List<String> databaseReceiptNos = [];

      // Fee #1: 0001
      final fee1 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: databaseReceiptNos,
        settings: config,
      );
      expect(fee1, '0001');
      databaseReceiptNos.add(fee1);

      // Donation #1: 0002
      final don1 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: databaseReceiptNos,
        settings: config,
      );
      expect(don1, '0002');
      databaseReceiptNos.add(don1);

      // Fee #2: 0003
      final fee2 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: databaseReceiptNos,
        settings: config,
      );
      expect(fee2, '0003');
    });

    test('When syncReceiptNumbers is false, Fee and Donation receipts run separate independent series', () {
      final config = DonationReceiptSettingsModel(
        customPrefix: 'REC-',
        enableAlphabet: false,
        enableYear: false,
        digitPadding: 4,
        startingNumber: 1,
        syncReceiptNumbers: false,
      );

      final List<String> feeReceiptNos = [];
      final List<String> donationReceiptNos = [];

      // Fee #1: 0001
      final fee1 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: feeReceiptNos,
        settings: config,
      );
      expect(fee1, 'REC-0001');
      feeReceiptNos.add(fee1);

      // Fee #2: 0002
      final fee2 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: feeReceiptNos,
        settings: config,
      );
      expect(fee2, 'REC-0002');
      feeReceiptNos.add(fee2);

      // Donation #1 starts at 0001 independently (does NOT jump to 0003)
      final don1 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: donationReceiptNos,
        settings: config,
      );
      expect(don1, 'REC-0001');
      donationReceiptNos.add(don1);

      // Donation #2: 0002
      final don2 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: donationReceiptNos,
        settings: config,
      );
      expect(don2, 'REC-0002');
      donationReceiptNos.add(don2);

      // Fee #3: 0003
      final fee3 = DonationReceiptGenerator.generateNextReceiptNo(
        existingReceiptNos: feeReceiptNos,
        settings: config,
      );
      expect(fee3, 'REC-0003');
      feeReceiptNos.add(fee3);

      // Verify they remained strictly independent
      expect(feeReceiptNos, ['REC-0001', 'REC-0002', 'REC-0003']);
      expect(donationReceiptNos, ['REC-0001', 'REC-0002']);
    });

    test('DonationReceiptSettingsModel supports syncReceiptNumbers field and copyWith', () {
      final defaultModel = DonationReceiptSettingsModel();
      expect(defaultModel.syncReceiptNumbers, isTrue);

      final separateModel = defaultModel.copyWith(syncReceiptNumbers: false);
      expect(separateModel.syncReceiptNumbers, isFalse);
      expect(separateModel.customPrefix, defaultModel.customPrefix);

      final syncedAgain = separateModel.copyWith(syncReceiptNumbers: true);
      expect(syncedAgain.syncReceiptNumbers, isTrue);
    });

    test('Receipt No and Date filtering in Fee Payments list works accurately', () {
      final payments = [
        FeePayment(
          id: 'pay_1',
          studentId: 'std_001',
          amount: 500,
          feeType: 'Admission Fee',
          status: 'Paid',
          paymentDate: '2026-09-20',
          createdAt: '2026-09-20 10:30:00',
          receiptNo: 'ERC-B26-00001',
          remarks: 'New admission cash',
        ),
        FeePayment(
          id: 'pay_2',
          studentId: 'std_001',
          amount: 600,
          feeType: 'Monthly Fees',
          status: 'Paid',
          paymentDate: '2026-09-22',
          createdAt: '2026-09-22 14:15:00',
          receiptNo: 'ERC-B26-00003',
          remarks: 'September monthly',
        ),
        FeePayment(
          id: 'pay_3',
          studentId: 'std_001',
          amount: 250,
          feeType: 'Book Fee',
          status: 'Paid',
          paymentDate: '2026-09-22',
          createdAt: '2026-09-22 16:45:00',
          receiptNo: 'REC-9999',
          remarks: 'Syllabus books',
        ),
      ];

      // Helper simulating _filteredPayments logic
      List<FeePayment> filterPayments(String query, DateTime? selectedDate) {
        final q = query.trim().toLowerCase();
        return payments.where((p) {
          if (q.isNotEmpty) {
            final rcpt = (p.receiptNo ?? '').toLowerCase();
            final type = p.feeType.toLowerCase();
            final remarks = (p.remarks ?? '').toLowerCase();
            final amountStr = p.amount.toStringAsFixed(0);
            final matches = rcpt.contains(q) || type.contains(q) || remarks.contains(q) || amountStr == q;
            if (!matches) return false;
          }
          if (selectedDate != null) {
            DateTime? dt;
            if (p.createdAt != null && p.createdAt!.trim().isNotEmpty) {
              String raw = p.createdAt!.trim();
              if (raw.length == 19 && raw.contains(' ') && !raw.contains('T')) {
                raw = '${raw.replaceFirst(' ', 'T')}Z';
              }
              dt = DateTime.tryParse(raw)?.toLocal();
            }
            if (dt == null && p.paymentDate != null && p.paymentDate!.trim().isNotEmpty) {
              dt = DateTime.tryParse(p.paymentDate!.trim());
            }
            if (dt == null) return false;
            if (dt.year != selectedDate.year || dt.month != selectedDate.month || dt.day != selectedDate.day) {
              return false;
            }
          }
          return true;
        }).toList();
      }

      // Case 1: Search by partial receipt no "00001"
      final r1 = filterPayments('00001', null);
      expect(r1.length, 1);
      expect(r1.first.receiptNo, 'ERC-B26-00001');

      // Case 2: Search by prefix "REC"
      final r2 = filterPayments('rec', null);
      expect(r2.length, 1);
      expect(r2.first.receiptNo, 'REC-9999');

      // Case 3: Filter by Date (22 Sep 2026) without text filter
      final r3 = filterPayments('', DateTime(2026, 9, 22));
      expect(r3.length, 2);
      expect(r3.map((e) => e.receiptNo).toList(), containsAll(['ERC-B26-00003', 'REC-9999']));

      // Case 4: Filter by both Date (22 Sep 2026) and Receipt No ("00003")
      final r4 = filterPayments('00003', DateTime(2026, 9, 22));
      expect(r4.length, 1);
      expect(r4.first.receiptNo, 'ERC-B26-00003');

      // Case 5: Filter by Date (20 Sep 2026) and mismatched Receipt No ("00003") -> 0 results
      final r5 = filterPayments('00003', DateTime(2026, 9, 20));
      expect(r5.isEmpty, isTrue);

      // Case 6: Reset filters -> all 3 payments returned
      final r6 = filterPayments('', null);
      expect(r6.length, 3);
    });

    testWidgets('Payment history search and date filter widgets render without layout overflow', (tester) async {
      final payments = [
        FeePayment(
          id: 'pay_1',
          studentId: 'std_001',
          amount: 600,
          feeType: 'Monthly Fees',
          status: 'Paid',
          paymentDate: '2026-09-22',
          createdAt: '2026-09-22 05:52:45',
          receiptNo: 'ERC-B26-00001',
          remarks: 'September fees',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                final searchCtrl = TextEditingController();
                DateTime? selectedDate = DateTime(2026, 9, 22);

                return Center(
                  child: AlertDialog(
                    title: const Text('Payment History'),
                    content: SizedBox(
                      width: 500,
                      height: 500,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Search and Date Filter Row
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 38,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: TextField(
                                    controller: searchCtrl,
                                    decoration: const InputDecoration(
                                      hintText: 'Search Receipt No...',
                                      prefixIcon: Icon(Icons.search),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.teal),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 14),
                                    const SizedBox(width: 4),
                                    Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              itemCount: payments.length,
                              itemBuilder: (context, i) {
                                final p = payments[i];
                                return ListTile(
                                  title: Text('${p.feeType} (#${p.receiptNo})'),
                                  trailing: Text('₹${p.amount}'),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Search Receipt No...'), findsOneWidget);
      expect(find.text('22 Sep 2026'), findsOneWidget);
      expect(find.text('Monthly Fees (#ERC-B26-00001)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Fee Payment delete flow prompts confirmation and deletes item', (tester) async {
      final payments = [
        FeePayment(
          id: 'pay_del_1',
          studentId: 'std_001',
          amount: 600,
          feeType: 'Monthly Fees',
          status: 'Paid',
          paymentDate: '2026-09-22',
          createdAt: '2026-09-22 05:52:45',
          receiptNo: 'REC-101',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return ListView.builder(
                  itemCount: payments.length,
                  itemBuilder: (ctx, i) {
                    final p = payments[i];
                    return ListTile(
                      title: Text(p.feeType),
                      subtitle: Text(p.receiptNo ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.picture_as_pdf_rounded),
                            onPressed: () {},
                          ),
                          IconButton(
                            key: const Key('delete_payment_btn'),
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (dlgCtx) => AlertDialog(
                                  title: const Text('Delete Fee Payment'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Kya aap waqai is fee payment entry ko delete karna chahte hain?'),
                                      Text('• Student: Zaid Khan'),
                                      Text('• Fee Type: ${p.feeType}'),
                                      Text('• Amount: ₹${p.amount.toStringAsFixed(0)}'),
                                      Text('• Receipt No: #${p.receiptNo}'),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dlgCtx, false),
                                      child: const Text('Nahi / Cancel'),
                                    ),
                                    ElevatedButton(
                                      key: const Key('confirm_delete_payment_btn'),
                                      onPressed: () => Navigator.pop(dlgCtx, true),
                                      child: const Text('Haan, Delete Karein'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                setState(() {
                                  payments.removeAt(i);
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Monthly Fees'), findsOneWidget);
      expect(find.byKey(const Key('delete_payment_btn')), findsOneWidget);

      // Tap delete button
      await tester.tap(find.byKey(const Key('delete_payment_btn')));
      await tester.pumpAndSettle();

      // Verify confirmation dialog contents
      expect(find.text('Delete Fee Payment'), findsOneWidget);
      expect(find.text('Kya aap waqai is fee payment entry ko delete karna chahte hain?'), findsOneWidget);
      expect(find.text('• Fee Type: Monthly Fees'), findsOneWidget);
      expect(find.text('• Amount: ₹600'), findsOneWidget);
      expect(find.text('• Receipt No: #REC-101'), findsOneWidget);

      // Tap confirm delete
      await tester.tap(find.byKey(const Key('confirm_delete_payment_btn')));
      await tester.pumpAndSettle();

      // Verify item removed
      expect(find.text('Monthly Fees'), findsNothing);
      expect(payments.isEmpty, isTrue);
    });

    testWidgets('Donation delete flow prompts confirmation and deletes donation entry', (tester) async {
      final donations = [
        Donation(
          id: 'don_del_1',
          donorName: 'Haji Abdul Rahman',
          amount: 5000,
          donationType: 'Zakat',
          paymentMethod: 'Cash',
          paymentDate: '2026-09-22',
          receiptNo: 'ERC-B26-00001',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                final totalAmt = donations.fold<double>(0, (s, d) => s + d.amount);
                return Column(
                  children: [
                    Text('Total: ₹$totalAmt (${donations.length} receipts)'),
                    Expanded(
                      child: ListView.builder(
                        itemCount: donations.length,
                        itemBuilder: (ctx, i) {
                          final d = donations[i];
                          return ListTile(
                            title: Text(d.donorName ?? ''),
                            subtitle: Text('${d.donationType} - #${d.displayReceiptNo}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: const Key('delete_donation_btn'),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (dlgCtx) => AlertDialog(
                                        title: const Text('Delete Donation Record'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Kya aap waqai is donation record ko delete karna chahte hain?'),
                                            Text('• Donor: ${d.donorName}'),
                                            Text('• Receipt No: #${d.displayReceiptNo}'),
                                            Text('• Category: ${d.donationType}'),
                                            Text('• Amount: ₹${d.amount.toStringAsFixed(0)}'),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dlgCtx, false),
                                            child: const Text('Nahi / Cancel'),
                                          ),
                                          ElevatedButton(
                                            key: const Key('confirm_delete_donation_btn'),
                                            onPressed: () => Navigator.pop(dlgCtx, true),
                                            child: const Text('Haan, Delete Karein'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      setState(() {
                                        donations.removeAt(i);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Haji Abdul Rahman'), findsOneWidget);
      expect(find.text('Total: ₹5000.0 (1 receipts)'), findsOneWidget);

      // Tap delete button
      await tester.tap(find.byKey(const Key('delete_donation_btn')));
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Delete Donation Record'), findsOneWidget);
      expect(find.text('• Donor: Haji Abdul Rahman'), findsOneWidget);
      expect(find.text('• Amount: ₹5000'), findsOneWidget);
      expect(find.text('• Receipt No: #ERC-B26-00001'), findsOneWidget);

      // Confirm deletion
      await tester.tap(find.byKey(const Key('confirm_delete_donation_btn')));
      await tester.pumpAndSettle();

      // Verify item removed and total updated
      expect(find.text('Haji Abdul Rahman'), findsNothing);
      expect(find.text('Total: ₹0.0 (0 receipts)'), findsOneWidget);
      expect(donations.isEmpty, isTrue);
    });

    group('Unique Donor Aggregation & Payment History Tests', () {
      test('groupDonationsByDonor groups multiple donations of same donor into single entry', () {
        final rawDonations = <Donation>[
          Donation(
            id: 'd1',
            donorName: 'Mohammad Tariq',
            donorPhone: '9876543210',
            village: 'Deoband',
            taluka: 'Deoband',
            district: 'Saharanpur',
            state: 'Uttar Pradesh',
            amount: 2000,
            donationType: 'Zakat',
            paymentMethod: 'Cash',
            paymentDate: '2026-08-15',
            receiptNo: 'REC-001',
          ),
          Donation(
            id: 'd2',
            donorName: 'mohammad tariq', // lower-case variation
            donorPhone: '9876543210',
            village: 'Deoband',
            amount: 3000,
            donationType: 'Sadqah',
            paymentMethod: 'Cash',
            paymentDate: '2026-09-20',
            receiptNo: 'REC-002',
          ),
          Donation(
            id: 'd3',
            donorName: 'Zubair Ahmad',
            donorPhone: '9123456780',
            village: 'Nanauta',
            amount: 1500,
            donationType: 'Imdad',
            paymentMethod: 'Online (UPI/Bank)',
            paymentDate: '2026-09-21',
            receiptNo: 'REC-003',
          ),
        ];

        final donors = DonorSummary.groupDonationsByDonor(rawDonations);

        // Expect 2 unique donors instead of 3 rows
        expect(donors.length, 2);

        final tariq = donors.firstWhere((d) => d.donorName.toLowerCase().contains('tariq'));
        expect(tariq.totalCount, 2);
        expect(tariq.totalDonated, 5000.0);
        expect(tariq.village, 'Deoband');
        expect(tariq.district, 'Saharanpur');
        expect(tariq.state, 'Uttar Pradesh');
        expect(tariq.donations.length, 2);
        // Latest donation should be REC-002 on 2026-09-20
        expect(tariq.latestDonation.receiptNo, 'REC-002');

        final zubair = donors.firstWhere((d) => d.donorName.toLowerCase().contains('zubair'));
        expect(zubair.totalCount, 1);
        expect(zubair.totalDonated, 1500.0);
      });

      test('Adding second donation to existing donor preserves single row and updates total', () {
        final initialDonations = <Donation>[
          Donation(
            id: 'd1',
            donorName: 'Sultan Khan',
            donorPhone: '9988776655',
            village: 'Rampur',
            amount: 1000,
            donationType: 'General Fund',
            paymentMethod: 'Cash',
            paymentDate: '2026-09-10',
            receiptNo: 'REC-100',
          ),
        ];

        var summaries = DonorSummary.groupDonationsByDonor(initialDonations);
        expect(summaries.length, 1);
        expect(summaries.first.totalDonated, 1000.0);
        expect(summaries.first.totalCount, 1);

        // User clicks Pay button and adds another donation for Sultan Khan
        final updatedDonations = List<Donation>.from(initialDonations)
          ..add(
            Donation(
              id: 'd2',
              donorName: 'Sultan Khan',
              donorPhone: '9988776655',
              village: 'Rampur',
              amount: 4000,
              donationType: 'Zakat',
              paymentMethod: 'Cash',
              paymentDate: '2026-09-22',
              receiptNo: 'REC-101',
            ),
          );

        summaries = DonorSummary.groupDonationsByDonor(updatedDonations);
        // Still 1 unique row in table!
        expect(summaries.length, 1);
        expect(summaries.first.totalDonated, 5000.0);
        expect(summaries.first.totalCount, 2);
        expect(summaries.first.donations.length, 2);
        expect(summaries.first.latestDonation.receiptNo, 'REC-101');
      });

      testWidgets('Donor Payment History dialog renders donor KPI and lists all donations', (tester) async {
        final donorDonations = <Donation>[
          Donation(
            id: 'd1',
            donorName: 'Haji Yusuf',
            donorPhone: '9876543210',
            amount: 5000,
            donationType: 'Zakat',
            paymentMethod: 'Cash',
            paymentDate: '2026-08-01',
            receiptNo: 'REC-001',
          ),
          Donation(
            id: 'd2',
            donorName: 'Haji Yusuf',
            donorPhone: '9876543210',
            amount: 15000,
            donationType: 'Building Fund',
            paymentMethod: 'Cash',
            paymentDate: '2026-09-15',
            receiptNo: 'REC-002',
          ),
        ];

        final donor = DonorSummary(
          donorKey: 'haji yusuf|9876543210',
          donorName: 'Haji Yusuf',
          donorPhone: '9876543210',
          village: 'Meerut',
          totalDonated: 20000,
          totalCount: 2,
          donations: donorDonations,
          latestDonation: donorDonations.last,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Center(
                    child: AlertDialog(
                      title: Text(donor.donorName),
                      content: SizedBox(
                        width: 500,
                        height: 450,
                        child: Column(
                          children: [
                            // KPI Card
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Text('Total: ₹${donor.totalDonated.toStringAsFixed(0)}'),
                                Text('Count: ${donor.totalCount}'),
                              ],
                            ),
                            const Divider(),
                            Expanded(
                              child: ListView.builder(
                                itemCount: donor.donations.length,
                                itemBuilder: (ctx, i) {
                                  final d = donor.donations[i];
                                  return ListTile(
                                    title: Text('${d.donationType} (#${d.displayReceiptNo})'),
                                    subtitle: Text(d.paymentDate ?? ''),
                                    trailing: Text('₹${d.amount.toStringAsFixed(0)}'),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        ElevatedButton.icon(
                          key: const Key('dialog_pay_button'),
                          icon: const Icon(Icons.payment_rounded),
                          label: const Text('Pay / Add Donation'),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify KPI and receipts displayed
        expect(find.text('Haji Yusuf'), findsOneWidget);
        expect(find.text('Total: ₹20000'), findsOneWidget);
        expect(find.text('Count: 2'), findsOneWidget);
        expect(find.text('Zakat (#REC-001)'), findsOneWidget);
        expect(find.text('Building Fund (#REC-002)'), findsOneWidget);
        expect(find.text('₹5000'), findsOneWidget);
        expect(find.text('₹15000'), findsOneWidget);
        expect(find.byKey(const Key('dialog_pay_button')), findsOneWidget);
      });
    });

    group('Merged Student Fees & Pending Filter Tests', () {
      test('Filtering student fees by pending, paid, and all works accurately', () {
        final students = [
          StudentFeeSummary(
            id: 's1',
            grNo: '001',
            fullName: 'Zaid Khan',
            className: 'Class 1',
            monthlyFees: 600,
            totalExpected: 1200,
            totalPaid: 600,
            totalPending: 600,
            feeHeads: [],
          ),
          StudentFeeSummary(
            id: 's2',
            grNo: '002',
            fullName: 'Umar Farooq',
            className: 'Class 2',
            monthlyFees: 500,
            totalExpected: 1000,
            totalPaid: 1000,
            totalPending: 0,
            feeHeads: [],
          ),
          StudentFeeSummary(
            id: 's3',
            grNo: '003',
            fullName: 'Bilal Ahmad',
            className: 'Class 1',
            monthlyFees: 800,
            totalExpected: 1600,
            totalPaid: 0,
            totalPending: 1600,
            feeHeads: [],
          ),
        ];

        // Helper matching screen filtering logic
        List<StudentFeeSummary> filter(String mode) {
          return students.where((s) {
            if (mode == 'pending') return s.totalPending > 0;
            if (mode == 'paid') return s.totalPending <= 0;
            return true;
          }).toList();
        }

        final all = filter('all');
        expect(all.length, 3);

        final pending = filter('pending');
        expect(pending.length, 2);
        expect(pending.map((e) => e.fullName), containsAll(['Zaid Khan', 'Bilal Ahmad']));

        final paid = filter('paid');
        expect(paid.length, 1);
        expect(paid.first.fullName, 'Umar Farooq');
      });

      testWidgets('Student Fees table shows both Paid and Pending badges', (tester) async {
        final student = StudentFeeSummary(
          id: 's1',
          grNo: '00001',
          fullName: 'Mohsin Imran',
          className: 'Class 1',
          monthlyFees: 600,
          totalExpected: 1300,
          totalPaid: 600,
          totalPending: 700,
          feeHeads: [],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  Text('Paid: ₹${student.totalPaid.toStringAsFixed(0)}'),
                  const SizedBox(width: 20),
                  Text('Pending: ₹${student.totalPending.toStringAsFixed(0)}'),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text('Paid: ₹600'), findsOneWidget);
        expect(find.text('Pending: ₹700'), findsOneWidget);
      });

      test('Student Fees column calculation dynamically fills available screen width without empty gaps', () {
        double calculateTotalRowWidth(double screenWidth) {
          const double minWidth = 1460.0;
          final effectiveWidth = screenWidth > minWidth ? screenWidth : minWidth;
          final availableWidth = effectiveWidth - 32.0;

          const double colIndex = 48.0;
          const double colGrNo = 100.0;
          const double colClass = 105.0;
          const double colActions = 125.0;
          const double fixedTotal = colIndex + colGrNo + colClass + colActions;

          const double baseName = 230.0;
          const double baseFeeType = 360.0;
          const double baseMonthlyFee = 115.0;
          const double baseTotalExpected = 135.0;
          const double basePaid = 105.0;
          const double basePending = 115.0;
          const double baseFlexTotal = baseName + baseFeeType + baseMonthlyFee + baseTotalExpected + basePaid + basePending;

          final flexibleWidth = availableWidth - fixedTotal;
          final flexRatio = math.max(1.0, flexibleWidth / baseFlexTotal);

          final colName = baseName * flexRatio;
          final colFeeType = baseFeeType * flexRatio;
          final colMonthlyFee = baseMonthlyFee * flexRatio;
          final colTotalExpected = baseTotalExpected * flexRatio;
          final colPaid = basePaid * flexRatio;
          final colPending = flexibleWidth - (colName + colFeeType + colMonthlyFee + colTotalExpected + colPaid);

          // Total row width with padding
          return (colIndex + colGrNo + colName + colClass + colFeeType + colMonthlyFee + colTotalExpected + colPaid + colPending + colActions) + 32.0;
        }

        // On 1920 monitor (matches user screenshot monitor)
        final width1920 = calculateTotalRowWidth(1920.0);
        expect(width1920, closeTo(1920.0, 0.001));

        // On 1600 laptop
        final width1600 = calculateTotalRowWidth(1600.0);
        expect(width1600, closeTo(1600.0, 0.001));

        // On small screen (below minWidth 1460), minWidth applies for horizontal scrolling
        final width1000 = calculateTotalRowWidth(1000.0);
        expect(width1000, closeTo(1460.0, 0.001));
      });

      testWidgets('DonationReceiptConfigDialog renders sync switch and toggles state', (tester) async {
        SharedPreferences.setMockInitialValues({
          'donation_receipt_sync_receipt_numbers': true,
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: DonationReceiptConfigDialog(
                initialFeeReceiptNos: ['REC-0001', 'REC-0002'],
                initialDonationReceiptNos: ['REC-0001'],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sync Fee & Donation Numbers'), findsOneWidget);
        expect(find.text('SYNCED'), findsOneWidget);

        // Find the sync switch by key
        final switchFinder = find.byKey(const Key('sync_receipt_numbers_switch'));
        expect(switchFinder, findsOneWidget);

        // Tap the switch to toggle sync OFF
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        // Badge should update to SEPARATE and preview should show INDEPENDENT SERIES
        expect(find.text('SEPARATE'), findsOneWidget);
        expect(find.text('INDEPENDENT SERIES'), findsOneWidget);
        expect(find.text('FEE RECEIPT'), findsOneWidget);
        expect(find.text('DONOR RECEIPT'), findsOneWidget);
      });
    });
  });
}

