import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/platform_utils.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:math';
import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/receipt_pdf_generator.dart';
import '../../../students/data/models/student_model.dart';
import '../../../students/data/repositories/student_repository.dart';
import '../../../staff/data/models/staff_model.dart';
import '../../../staff/data/repositories/staff_repository.dart';
import '../../../hostel/data/models/hostel_models.dart';
import '../../../hostel/data/repositories/hostel_repository.dart';
import '../../data/models/library_models.dart';
import '../../data/repositories/library_repository.dart';
import '../bloc/library_bloc.dart';
import '../../../../core/widgets/app_date_range_picker.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  Widget _buildResponsiveRow(BuildContext context, Widget child1, Widget child2) {
    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child1,
          const SizedBox(height: 16),
          child2,
        ],
      );
    } else {
      return Row(
        children: [
          Expanded(child: child1),
          const SizedBox(width: 16),
          Expanded(child: child2),
        ],
      );
    }
  }

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _txSearchController = TextEditingController();

  String _parseApiError(dynamic e) {
    if (e is DioException) {
      if (e.response?.data != null && e.response!.data is Map) {
        final data = e.response!.data as Map;
        if (data.containsKey('message')) {
          return data['message'].toString();
        }
      }
      return e.message ?? e.toString();
    }
    return e.toString();
  }
  final FocusNode _scanFocusNode = FocusNode();
  final TextEditingController _scanController = TextEditingController();
  
  String? _selectedCategoryId;
  String? _selectedAvailability;
  int _activeSettingsSubTab = 0;

  // Transaction Tab Filters
  String? _txStatusFilter;
  DateTimeRange? _txDateRange;

  // Student borrowing history section states
  Student? _historyStudent;
  List<LibraryTransaction> _studentHistory = [];
  bool _isLoadingHistory = false;

  final _studentSearchRepo = StudentRepository(ApiClient());
  final _staffSearchRepo = StaffRepository(ApiClient());
  List<HostelAllocation> _allHostelAllocations = [];
  bool _loadedAllocations = false;

  Future<void> _loadHostelAllocations() async {
    if (_loadedAllocations) return;
    try {
      final repo = HostelRepository(ApiClient());
      final allocations = await repo.getAllocations(status: 'Active');
      setState(() {
        _allHostelAllocations = allocations;
        _loadedAllocations = true;
      });
    } catch (_) {
      // Fail silently, hostel details just won't show
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHostelAllocations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _txSearchController.dispose();
    _scanFocusNode.dispose();
    _scanController.dispose();
    super.dispose();
  }

  String _generateBookQrData({
    required LibraryBook book,
    int? copyNumber,
  }) {
    final title = book.title.replaceAll('|', ' ').trim();
    final author = (book.author ?? '-').replaceAll('|', ' ').trim();
    final isbn = (book.isbn ?? '-').replaceAll('|', ' ').trim();
    final category = (book.categoryName ?? '-').replaceAll('|', ' ').trim();
    final language = book.language.replaceAll('|', ' ').trim();
    final publisher = (book.publisher ?? '-').replaceAll('|', ' ').trim();
    final shelf = (book.shelfLocation ?? '-').replaceAll('|', ' ').trim();
    final copy = copyNumber != null ? '$copyNumber/${book.totalCopies}' : '1/${book.totalCopies}';

    final blocState = context.read<LibraryBloc>().state;
    String due = '14';
    String lost = '500';
    String lostFound = '100';
    String fpd = '5';
    if (blocState is LibraryLoaded) {
      due = (book.defaultDueDays ?? blocState.settings.defaultDueDays).toString();
      lost = (book.lostBookFine ?? blocState.settings.lostBookFine).toString();
      lostFound = (book.lostBookFoundFine ?? blocState.settings.lostBookFoundFine).toString();
      fpd = (book.finePerDay ?? blocState.settings.finePerDay).toString();
    } else {
      due = (book.defaultDueDays ?? 14).toString();
      lost = (book.lostBookFine ?? 500.0).toString();
      lostFound = (book.lostBookFoundFine ?? 100.0).toString();
      fpd = (book.finePerDay ?? 5.0).toString();
    }

    return 'Title: $title | Author: $author | ISBN: $isbn | Category: $category | Lang: $language | Pub: $publisher | Shelf: $shelf | Copy: $copy | Due Days: $due | Fine/Day: $fpd | Lost Fine: $lost | Found Fine: $lostFound';
  }

  LibraryBook? _findBookFromScannedData(String scannedValue, List<LibraryBook> books) {
    scannedValue = scannedValue.trim();
    
    // Parse the fields
    String? title;
    String? isbn;
    String? author;

    if (scannedValue.contains('|')) {
      final parts = scannedValue.split('|');
      for (var part in parts) {
        part = part.trim();
        if (part.startsWith('Title:')) {
          title = part.substring(6).trim();
        } else if (part.startsWith('ISBN:')) {
          isbn = part.substring(5).trim();
          if (isbn == '-') isbn = null;
        } else if (part.startsWith('Author:')) {
          author = part.substring(7).trim();
          if (author == '-') author = null;
        }
      }
    }

    if (title == null) {
      // Legacy QR code containing just the raw database ID
      final matches = books.where((b) => b.id == scannedValue);
      if (matches.isNotEmpty) {
        return matches.first;
      }
      return null;
    }

    // Match by ISBN first
    if (isbn != null && isbn.isNotEmpty) {
      final matches = books.where((b) => b.isbn?.trim().toLowerCase() == isbn!.toLowerCase());
      if (matches.isNotEmpty) {
        return matches.first;
      }
    }

    // Match by Title and Author
    final matches = books.where((b) {
      final titleMatch = b.title.trim().toLowerCase() == title!.toLowerCase();
      if (!titleMatch) return false;
      
      if (author != null && author.isNotEmpty) {
        return (b.author?.trim().toLowerCase() ?? '') == author.toLowerCase() || b.author == null || b.author!.isEmpty;
      }
      return true;
    });

    if (matches.isNotEmpty) {
      return matches.first;
    }

    return null;
  }

  void _refreshData() {
    context.read<LibraryBloc>().add(LoadLibraryData(
          search: _searchController.text.trim(),
          categoryId: _selectedCategoryId,
          availability: _selectedAvailability,
          txStatus: _txStatusFilter,
          startDate: _txDateRange?.start.toIso8601String().split('T')[0],
          endDate: _txDateRange?.end.toIso8601String().split('T')[0],
        ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppTheme.primaryLight : AppTheme.primaryColor;

    return BlocListener<LibraryBloc, LibraryState>(
      listener: (context, state) {
        if (state is LibraryError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            // Tabs Header
            Container(
              color: isDark ? const Color(0xFF161625) : Colors.white,
              child: TabBar(
                controller: _tabController,
                indicatorColor: primaryColor,
                labelColor: primaryColor,
                unselectedLabelColor: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                labelStyle: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.bold),
                tabs: [Tab(icon: Icon(Icons.menu_book_rounded), text: context.tr('books_inventory')),
                  Tab(icon: Icon(Icons.swap_horiz_rounded), text: context.tr('issue_return')),
                  Tab(icon: Icon(Icons.settings_rounded), text: context.tr('categories_settings')),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<LibraryBloc, LibraryState>(
                builder: (context, state) {
                  if (state is LibraryInitial || (state is LibraryLoading && state is! LibraryLoaded)) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is LibraryLoaded) {

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildBooksInventoryTab(state),
                        _buildIssueReturnTab(state),
                        _buildSettingsCategoriesTab(state),
                      ],
                    );
                  }

                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Failed to load library data.', style: AppTheme.getFontStyle(fontSize: 16)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _refreshData,
                          child: Text(context.tr('retry')),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TAB 1: BOOKS INVENTORY ─────────────────────────────────────────
  Widget _buildBooksInventoryTab(LibraryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppTheme.primaryLight : AppTheme.primaryColor;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── STATS HEADER WITH GRADIENTS ──
          Row(
            children: [
              Expanded(
                child: _buildGradientStatCard(
                  'Total Books',
                  '${state.stats.totalBooks} (${state.stats.totalCopies} copies)',
                  Icons.book_rounded,
                  [const Color(0xFF3A7BD5), const Color(0xFF3A6073)],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildGradientStatCard(
                  'Available Copies',
                  '${state.stats.availableCopies}',
                  Icons.check_circle_outline_rounded,
                  [const Color(0xFF11998E), const Color(0xFF38EF7D)],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildGradientStatCard(
                  'Issued Books',
                  '${state.stats.issuedCount}',
                  Icons.reply_rounded,
                  [const Color(0xFFFC4A1A), const Color(0xFFF7B733)],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildGradientStatCard(
                  'Overdue Books',
                  '${state.stats.overdueCount}',
                  Icons.warning_amber_rounded,
                  [const Color(0xFFEE0979), const Color(0xFFFF6A00)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── FILTERS & SEARCH ──
          context.isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _searchController,
                      style: AppTheme.getFontStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search by title, author, or ISBN...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  _refreshData();
                                },
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _refreshData(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedCategoryId,
                            hint: Text(context.tr('all_categories')),
                            style: AppTheme.getFontStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
                            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                            items: [
                              DropdownMenuItem(value: null, child: Text(context.tr('all_categories'))),
                              ...state.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedCategoryId = val);
                              _refreshData();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedAvailability,
                            hint: Text(context.tr('all_statuses')),
                            style: AppTheme.getFontStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
                            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                            items: [DropdownMenuItem(value: null, child: Text(context.tr('all_statuses'))),
                              DropdownMenuItem(value: 'available', child: Text(context.tr('available'))),
                              DropdownMenuItem(value: 'out_of_stock', child: Text(context.tr('out_of_stock'))),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedAvailability = val);
                              _refreshData();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _showAddEditBookDialog(null),
                            style: FilledButton.styleFrom(
                              backgroundColor: primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.add_rounded),
                            label: Text(context.tr('add_book')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              final data = state.books.map((b) => {
                                    'title': b.title,
                                    'author': b.author,
                                    'category_name': b.categoryName,
                                    'language': b.language,
                                    'total_copies': b.totalCopies,
                                    'available_copies': b.availableCopies,
                                    'shelf_location': b.shelfLocation,
                                  }).toList();
                              ReceiptPdfGenerator.printLibraryInventoryReport(books: data);
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: primary),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: Icon(Icons.picture_as_pdf_rounded, color: primary),
                            label: Text('Report', style: TextStyle(color: primary)),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _searchController,
                        style: AppTheme.getFontStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search by title, author, or ISBN...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    _searchController.clear();
                                    _refreshData();
                                  },
                                )
                              : null,
                        ),
                        onSubmitted: (_) => _refreshData(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCategoryId,
                        hint: Text(context.tr('all_categories')),
                        style: AppTheme.getFontStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
                        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                        items: [
                          DropdownMenuItem(value: null, child: Text(context.tr('all_categories'))),
                          ...state.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                        ],
                        onChanged: (val) {
                          setState(() => _selectedCategoryId = val);
                          _refreshData();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedAvailability,
                        hint: Text(context.tr('all_statuses')),
                        style: AppTheme.getFontStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
                        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                        items: [DropdownMenuItem(value: null, child: Text(context.tr('all_statuses'))),
                          DropdownMenuItem(value: 'available', child: Text(context.tr('available'))),
                          DropdownMenuItem(value: 'out_of_stock', child: Text(context.tr('out_of_stock'))),
                        ],
                        onChanged: (val) {
                          setState(() => _selectedAvailability = val);
                          _refreshData();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      onPressed: () => _showAddEditBookDialog(null),
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.tr('add_book')),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        final data = state.books.map((b) => {
                              'title': b.title,
                              'author': b.author,
                              'category_name': b.categoryName,
                              'language': b.language,
                              'total_copies': b.totalCopies,
                              'available_copies': b.availableCopies,
                              'shelf_location': b.shelfLocation,
                            }).toList();
                        ReceiptPdfGenerator.printLibraryInventoryReport(books: data);
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: primary),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: Icon(Icons.picture_as_pdf_rounded, color: primary),
                      label: Text('Report', style: TextStyle(color: primary)),
                    ),
                  ],
                ),
          const SizedBox(height: 16),

          // ── BOOKS TABLE ──
          Expanded(
            child: Card(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: state.books.isEmpty
                    ? Center(child: Text(context.tr('no_books_found')))
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                          columns: [DataColumn(label: Text(context.tr('title'))),
                            DataColumn(label: Text(context.tr('author'))),
                            DataColumn(label: Text(context.tr('category'))),
                            DataColumn(label: Text(context.tr('language'))),
                            DataColumn(label: Text(context.tr('copies_total_avail'))),
                            DataColumn(label: Text(context.tr('due_fines'))),
                            DataColumn(label: Text(context.tr('shelf_location'))),
                            DataColumn(label: Text(context.tr('actions'))),
                          ],
                          rows: state.books.map((book) {
                            return DataRow(
                              cells: [
                                DataCell(Text(book.title, style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(book.author ?? '-')),
                                DataCell(Text(book.categoryName ?? '-')),
                                DataCell(Text(book.language)),
                                DataCell(Text('${book.totalCopies} / ${book.availableCopies}')),
                                DataCell(Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Due: ${book.defaultDueDays ?? state.settings.defaultDueDays} Days | Fine: ₹${book.finePerDay ?? state.settings.finePerDay}/Day', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    Text('Lost: ₹${book.lostBookFine ?? state.settings.lostBookFine} | Found: ₹${book.lostBookFoundFine ?? state.settings.lostBookFoundFine}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                  ],
                                )),
                                DataCell(Text(book.shelfLocation ?? '-')),
                                DataCell(Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.qr_code_rounded, color: Colors.teal),
                                      tooltip: 'Show QR Code & Label',
                                      onPressed: () => _showBookQrDialog(book),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, color: Colors.blue),
                                      onPressed: () => _showAddEditBookDialog(book),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                                      onPressed: () => _confirmDeleteBook(book.id),
                                    ),
                                  ],
                                )),
                              ],
                            );
                          }).toList(),
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

  // ─── TAB 2: ISSUE & RETURN (INLINE PANEL) ───────────────────────────
  void _showIssueBookDialog(LibraryLoaded state, {LibraryBook? initialSelectedBook}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppTheme.primaryLight : AppTheme.primaryColor;

    LibraryBook? selectedBook = initialSelectedBook;
    String selectedUserType = 'Student';
    Student? selectedStudent;
    StaffMember? selectedStaff;

    final dueDateController = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(
        DateTime.now().add(Duration(days: state.settings.defaultDueDays)),
      ),
    );
    final bookSearchController = TextEditingController(
      text: selectedBook != null ? '${selectedBook.title} - ${selectedBook.author ?? 'Unknown'}' : '',
    );
    final userSearchController = TextEditingController();

    bool isSubmitting = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            int activeIssuesCount = 0;
            bool limitReached = false;
            if (selectedUserType == 'Student' && selectedStudent != null) {
              activeIssuesCount = state.transactions
                  .where((t) =>
                      t.studentId == selectedStudent!.id &&
                      (t.computedStatus == 'Issued' || t.computedStatus == 'Overdue'))
                  .length;
              limitReached = activeIssuesCount >= state.settings.maxBooksPerStudent;
            }

            final bookInfoWidget = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Autocomplete<LibraryBook>(
                  initialValue: TextEditingValue(text: bookSearchController.text),
                  displayStringForOption: (book) =>
                      '${book.title} - ${book.author ?? 'Unknown'} (Copies: ${book.availableCopies})',
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText: 'Search & Scan Book *',
                        prefixIcon: const Icon(Icons.library_books_rounded),
                        suffixIcon: selectedBook != null
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  setDialogState(() {
                                    selectedBook = null;
                                    controller.clear();
                                    bookSearchController.clear();
                                  });
                                },
                              )
                            : null,
                      ),
                    );
                  },
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.trim().isEmpty) {
                      return const Iterable<LibraryBook>.empty();
                    }
                    final query = textEditingValue.text.trim().toLowerCase();
                    return state.books
                        .where((b) => b.availableCopies > 0)
                        .where((b) =>
                            b.title.toLowerCase().contains(query) ||
                            (b.author?.toLowerCase().contains(query) ?? false) ||
                            (b.isbn?.toLowerCase().contains(query) ?? false));
                  },
                  onSelected: (book) {
                    setDialogState(() {
                      selectedBook = book;
                      bookSearchController.text = '${book.title} - ${book.author ?? 'Unknown'}';
                    });
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: dueDateController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: context.tr('due_date_required'),
                    prefixIcon: const Icon(Icons.calendar_today_rounded),
                  ),
                  onTap: () async {
                    final selectedDate = await showDatePicker(
                      context: dialogContext,
                      initialDate: DateTime.now().add(Duration(days: state.settings.defaultDueDays)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (selectedDate != null) {
                      setDialogState(() {
                        dueDateController.text = DateFormat('yyyy-MM-dd').format(selectedDate);
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                if (selectedBook != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.blueGrey.withOpacity(0.1) : Colors.blue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: primary.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Book Details:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primary),
                        ),
                        const SizedBox(height: 6),
                        Text('Title: ${selectedBook!.title}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        Text('Author: ${selectedBook!.author ?? '-'}', style: const TextStyle(fontSize: 12)),
                        Text('Shelf Location: ${selectedBook!.shelfLocation ?? 'Not set'}', style: const TextStyle(fontSize: 12)),
                        Text('Copies: ${selectedBook!.availableCopies} Available of ${selectedBook!.totalCopies}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ],
            );

            final borrowerInfoWidget = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedUserType,
                  decoration: InputDecoration(
                    labelText: context.tr('borrower_type'),
                    prefixIcon: const Icon(Icons.group_rounded),
                  ),
                  items: [
                    DropdownMenuItem(value: 'Student', child: Text(context.tr('student'))),
                    DropdownMenuItem(value: 'Staff', child: Text(context.tr('staff'))),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        selectedUserType = val;
                        selectedStudent = null;
                        selectedStaff = null;
                        userSearchController.clear();
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                if (selectedUserType == 'Student') ...[
                  Autocomplete<Student>(
                    initialValue: TextEditingValue(text: userSearchController.text),
                    displayStringForOption: (student) =>
                        '${student.fullName} ${student.surname ?? ''} (GR: ${student.grNo ?? '-'})',
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Search Student *',
                          prefixIcon: const Icon(Icons.person_search_rounded),
                          suffixIcon: selectedStudent != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    setDialogState(() {
                                      selectedStudent = null;
                                      controller.clear();
                                      userSearchController.clear();
                                    });
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                    optionsBuilder: (textEditingValue) async {
                      if (textEditingValue.text.trim().isEmpty) {
                        return const Iterable<Student>.empty();
                      }
                      try {
                        return await _studentSearchRepo.searchStudents(textEditingValue.text.trim());
                      } catch (_) {
                        return const Iterable<Student>.empty();
                      }
                    },
                    onSelected: (student) {
                      setDialogState(() {
                        selectedStudent = student;
                        userSearchController.text = '${student.fullName} ${student.surname ?? ''}';
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  if (selectedStudent != null) ...[
                    Builder(
                      builder: (context) {
                        final allocation = _allHostelAllocations.firstWhere(
                          (a) => a.studentId == selectedStudent!.id,
                          orElse: () => HostelAllocation(
                            id: '', bedId: '', bedNumber: '-', studentId: '', studentName: '', 
                            roomId: '', roomNumber: 'Not allocated', hostelId: '', hostelName: 'No Hostel', 
                            allocationDate: '', status: ''
                          ),
                        );

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: limitReached ? Colors.red.withOpacity(0.05) : Colors.green.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: limitReached ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Student Details:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 13, 
                                      color: limitReached ? Colors.red : Colors.green
                                    ),
                                  ),
                                  Text(
                                    '$activeIssuesCount/${state.settings.maxBooksPerStudent} Issued',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 11,
                                      color: limitReached ? Colors.redAccent : Colors.green
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('GR No: ${selectedStudent!.grNo ?? '-'}', style: const TextStyle(fontSize: 12)),
                              Text('Name: ${selectedStudent!.fullName} ${selectedStudent!.fatherName ?? ''} ${selectedStudent!.surname ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              Text('Class: ${selectedStudent!.className ?? '-'}', style: const TextStyle(fontSize: 12)),
                              Text('Hostel Name: ${allocation.hostelName}', style: const TextStyle(fontSize: 12)),
                              Text('Hostel Room: ${allocation.roomNumber}', style: const TextStyle(fontSize: 12)),
                              Text('Seat/Bed No: ${allocation.bedNumber}', style: const TextStyle(fontSize: 12)),
                              Text('Mobile No: ${selectedStudent!.mobileNo ?? '-'}', style: const TextStyle(fontSize: 12)),
                              if (limitReached) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  '⚠️ Max borrowing limit reached!', 
                                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11)
                                ),
                              ]
                            ],
                          ),
                        );
                      }
                    ),
                  ],
                ] else ...[
                  Autocomplete<StaffMember>(
                    initialValue: TextEditingValue(text: userSearchController.text),
                    displayStringForOption: (staff) =>
                        '${staff.fullName} (No: ${staff.staffNo})',
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: context.tr('search_staff_required'),
                          prefixIcon: const Icon(Icons.person_search_rounded),
                          suffixIcon: selectedStaff != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    setDialogState(() {
                                      selectedStaff = null;
                                      controller.clear();
                                      userSearchController.clear();
                                    });
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                    optionsBuilder: (textEditingValue) async {
                      if (textEditingValue.text.trim().isEmpty) {
                        return const Iterable<StaffMember>.empty();
                      }
                      try {
                        return await _staffSearchRepo.getAll(query: textEditingValue.text.trim());
                      } catch (_) {
                        return const Iterable<StaffMember>.empty();
                      }
                    },
                    onSelected: (staff) {
                      setDialogState(() {
                        selectedStaff = staff;
                        userSearchController.text = staff.fullName;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  if (selectedStaff != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Staff Details:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                          ),
                          const SizedBox(height: 6),
                          Text('Staff No: ${selectedStaff!.staffNo}', style: const TextStyle(fontSize: 12)),
                          Text('Name: ${selectedStaff!.fullName}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          Text('Role/Type: ${selectedStaff!.staffType}', style: const TextStyle(fontSize: 12)),
                          Text('Mobile No: ${selectedStaff!.mobileNo ?? '-'}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            );

            return Dialog(
              backgroundColor: isDark ? const Color(0xFF1E1E2F) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: min(650.0, MediaQuery.of(context).size.width - 32),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.add_circle_outline_rounded, color: primary, size: 28),
                            const SizedBox(width: 12),
                            Text(
                              'Issue Book Form',
                              style: AppTheme.getFontStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    if (errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    Flexible(
                      child: SingleChildScrollView(
                        child: context.isMobile
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  bookInfoWidget,
                                  const SizedBox(height: 24),
                                  borrowerInfoWidget,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: bookInfoWidget),
                                  const SizedBox(width: 24),
                                  Expanded(child: borrowerInfoWidget),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                          child: Text(context.tr('cancel')),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: (selectedBook == null ||
                                  (selectedUserType == 'Student' && (selectedStudent == null || limitReached)) ||
                                  (selectedUserType == 'Staff' && selectedStaff == null) ||
                                  isSubmitting)
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isSubmitting = true;
                                    errorMessage = null;
                                  });

                                  try {
                                    final txRepo = LibraryRepository(ApiClient());
                                    final txId = 'TX-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';
                                    
                                    String borrowerName;
                                    String? hostelName;
                                    String? roomNumber;
                                    String? bedNumber;

                                    if (selectedUserType == 'Student') {
                                      borrowerName = '${selectedStudent!.fullName} ${selectedStudent!.fatherName ?? ''} ${selectedStudent!.surname ?? ''}'
                                          .trim()
                                          .replaceAll(RegExp(r'\s+'), ' ');
                                      
                                      final allocation = _allHostelAllocations.firstWhere(
                                        (a) => a.studentId == selectedStudent!.id,
                                        orElse: () => HostelAllocation(
                                          id: '', bedId: '', bedNumber: '-', studentId: '', studentName: '', 
                                          roomId: '', roomNumber: '-', hostelId: '', hostelName: '-', 
                                          allocationDate: '', status: ''
                                        ),
                                      );
                                      
                                      if (allocation.id.isNotEmpty) {
                                        hostelName = allocation.hostelName;
                                        roomNumber = allocation.roomNumber;
                                        bedNumber = allocation.bedNumber;
                                      }
                                    } else {
                                      borrowerName = selectedStaff!.fullName;
                                    }

                                    await txRepo.issueBook(
                                      transactionId: txId,
                                      studentId: selectedUserType == 'Student' ? selectedStudent!.id : null,
                                      staffId: selectedUserType == 'Staff' ? selectedStaff!.id : null,
                                      borrowerName: borrowerName,
                                      hostelName: hostelName,
                                      roomNumber: roomNumber,
                                      bedNumber: bedNumber,
                                      bookId: selectedBook!.id,
                                      dueDate: dueDateController.text,
                                    );

                                    if (mounted) {
                                      context.read<LibraryBloc>().add(LoadLibraryData());
                                    }

                                    Navigator.pop(dialogContext);

                                    final hostelInfo = (selectedUserType == 'Student' && hostelName != null && hostelName != '-')
                                        ? 'Hostel: $hostelName / Rm: $roomNumber / Bed: $bedNumber'
                                        : null;

                                    _showIssueSuccessDialog(
                                      transactionId: txId,
                                      borrowerName: borrowerName,
                                      borrowerType: selectedUserType,
                                      bookTitle: selectedBook!.title,
                                      issueDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                                      dueDate: dueDateController.text,
                                      hostelInfo: hostelInfo,
                                      defaultDueDays: selectedBook!.defaultDueDays,
                                      finePerDay: selectedBook!.finePerDay,
                                      lostBookFine: selectedBook!.lostBookFine,
                                      lostBookFoundFine: selectedBook!.lostBookFoundFine,
                                    );
                                  } catch (e) {
                                    setDialogState(() {
                                      isSubmitting = false;
                                      errorMessage = _parseApiError(e);
                                    });
                                  }
                                },
                          style: FilledButton.styleFrom(backgroundColor: primary),
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(context.tr('issue_book')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showIssueSuccessDialog({
    required String transactionId,
    required String borrowerName,
    required String borrowerType,
    required String bookTitle,
    required String issueDate,
    required String dueDate,
    String? hostelInfo,
    int? defaultDueDays,
    double? finePerDay,
    double? lostBookFine,
    double? lostBookFoundFine,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppTheme.primaryLight : AppTheme.primaryColor;
    final state = context.read<LibraryBloc>().state as LibraryLoaded;

    final due = defaultDueDays ?? state.settings.defaultDueDays;
    final fpd = finePerDay ?? state.settings.finePerDay;
    final lost = lostBookFine ?? state.settings.lostBookFine;
    final found = lostBookFoundFine ?? state.settings.lostBookFoundFine;
    final qrData = 'TX:$transactionId | Due Days: $due | Fine/Day: $fpd | Lost Fine: $lost | Found Fine: $found';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2F) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Book Issued Successfully!',
                  style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Generate receipt QR code to easily process book return on scan.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 160.0,
                    gapless: false,
                    errorStateBuilder: (cxt, err) {
                      return Center(child: Text(context.tr('qr_generation_error')));
                    },
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Transaction ID: $transactionId',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                if (hostelInfo != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    hostelInfo,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.blueGrey),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(context.tr('close')),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        ReceiptPdfGenerator.printTransactionQrLabel(
                          transactionId: transactionId,
                          borrowerName: borrowerName,
                          borrowerType: borrowerType,
                          bookTitle: bookTitle,
                          issueDate: issueDate,
                          dueDate: dueDate,
                          hostelInfo: hostelInfo,
                          qrData: qrData,
                        );
                      },
                      style: FilledButton.styleFrom(backgroundColor: primary),
                      icon: const Icon(Icons.print_rounded),
                      label: Text(context.tr('print_receipt_qr')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditTransactionDialog(LibraryLoaded state, LibraryTransaction tx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppTheme.primaryLight : AppTheme.primaryColor;

    final dueDateController = TextEditingController(text: tx.dueDate);
    final remarksController = TextEditingController(text: tx.remarks ?? '');
    String selectedStatus = tx.status;
    double fineAmount = tx.fineAmount;
    final fineController = TextEditingController(text: fineAmount.toStringAsFixed(1));

    bool isSubmitting = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              backgroundColor: isDark ? const Color(0xFF1E1E2F) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 450,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.edit_calendar_rounded, color: primary, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Edit Issue Details',
                              style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    if (errorMessage != null) ...[
                      Text(errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                      const SizedBox(height: 12),
                    ],

                    TextFormField(
                      controller: dueDateController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: context.tr('due_date'),
                        prefixIcon: Icon(Icons.calendar_today_rounded),
                      ),
                      onTap: () async {
                        final parsed = DateTime.tryParse(tx.dueDate) ?? DateTime.now();
                        final selectedDate = await showDatePicker(
                          context: dialogContext,
                          initialDate: parsed,
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 120)),
                        );
                        if (selectedDate != null) {
                          setDialogState(() {
                            dueDateController.text = DateFormat('yyyy-MM-dd').format(selectedDate);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      value: selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        prefixIcon: Icon(Icons.info_outline_rounded),
                      ),
                      items: [DropdownMenuItem(value: 'Issued', child: Text(context.tr('issued_active'))),
                        DropdownMenuItem(value: 'Returned', child: Text(context.tr('returned'))),
                        DropdownMenuItem(value: 'Lost', child: Text(context.tr('lost'))),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            final book = state.books.where(
                              (b) => b.id == tx.bookId,
                            ).firstOrNull;
                            // Lost → Returned: apply lost book found fine
                            if (selectedStatus == 'Lost' && val == 'Returned') {
                              fineAmount = book?.lostBookFoundFine ?? state.settings.lostBookFoundFine;
                              fineController.text = fineAmount.toStringAsFixed(1);
                            }
                            // Any → Lost: apply lost book fine
                            else if (selectedStatus != 'Lost' && val == 'Lost') {
                              fineAmount = book?.lostBookFine ?? state.settings.lostBookFine;
                              fineController.text = fineAmount.toStringAsFixed(1);
                            }
                            // Any → Issued: reset fine to 0
                            else if (val == 'Issued') {
                              fineAmount = 0.0;
                              fineController.text = '0.0';
                            }
                            selectedStatus = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: fineController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: context.tr('fine_amount_inr'),
                        prefixIcon: Icon(Icons.currency_rupee_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: remarksController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Remarks',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                          child: Text(context.tr('cancel')),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: isSubmitting
                              ? null
                              : () {
                                  setDialogState(() {
                                    isSubmitting = true;
                                  });
                                  context.read<LibraryBloc>().add(
                                        UpdateTransactionEvent(
                                          transactionId: tx.id,
                                          dueDate: dueDateController.text,
                                          status: selectedStatus,
                                          fineAmount: double.tryParse(fineController.text) ?? 0.0,
                                          remarks: remarksController.text,
                                        ),
                                      );
                                  Navigator.pop(dialogContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(context.tr('issue_details_updated'))),
                                  );
                                },
                          style: FilledButton.styleFrom(backgroundColor: primary),
                          child: Text(context.tr('save_changes')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildIssueReturnTab(LibraryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppTheme.primaryLight : AppTheme.primaryColor;

    final txSearch = _txSearchController.text.trim().toLowerCase();
    final filteredTxs = state.transactions.where((tx) {
      if (txSearch.isEmpty) return true;
      final borrowerName = tx.studentId != null 
          ? '${tx.studentName} ${tx.surname ?? ''}'.toLowerCase()
          : (tx.staffName ?? '').toLowerCase();
      final bookTitle = tx.bookTitle.toLowerCase();
      final grNo = (tx.studentGrNo ?? '').toLowerCase();
      final staffNo = (tx.staffNo ?? '').toLowerCase();
      final fatherName = (tx.fatherName ?? '').toLowerCase();
      return borrowerName.contains(txSearch) ||
          bookTitle.contains(txSearch) ||
          grNo.contains(txSearch) ||
          staffNo.contains(txSearch) ||
          fatherName.contains(txSearch);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── QUICK BARCODE SCAN / MANUAL TOGGLE ROW ──
          Card(
            color: isDark ? const Color(0xFF1E1E32) : const Color(0xFFF9FAFC),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      focusNode: _scanFocusNode,
                      controller: _scanController,
                      decoration: InputDecoration(
                        labelText: context.tr('quick_scan_qr_desc'),
                        prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                        hintText: context.tr('place_cursor_scan'),
                      ),
                      onFieldSubmitted: (val) {
                        final input = val.trim();
                        if (input.isEmpty) return;

                        if (input.startsWith('TX:')) {
                          final parts = input.split('|');
                          final txId = parts[0].substring(3).trim();
                          context.read<LibraryBloc>().add(ReturnBookEvent(transactionId: txId));
                          _scanController.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.tr('processing_quick_return')),
                              backgroundColor: Colors.teal,
                            ),
                          );
                        } else {
                          final match = _findBookFromScannedData(input, state.books);
                          if (match != null) {
                            _scanController.clear();
                            if (match.availableCopies > 0) {
                              _showIssueBookDialog(state, initialSelectedBook: match);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(context.tr('scanned_book_out_of_stock')),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          } else {
                            _scanController.clear();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.tr('no_book_tx_found_qr')),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: () => _showIssueBookDialog(state),
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: Text(
                      'Issue Book Panel',
                      style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── TRANSACTION FILTERS & ACTION REPORT ──
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _txSearchController,
                  style: AppTheme.getFontStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: context.tr('search_issues_hint'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _txSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _txSearchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _txStatusFilter,
                  hint: Text(context.tr('all_statuses')),
                  style: AppTheme.getFontStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                  items: [DropdownMenuItem(value: null, child: Text(context.tr('all_statuses'))),
                    DropdownMenuItem(value: 'Issued', child: Text(context.tr('active_stay'))),
                    DropdownMenuItem(value: 'Overdue', child: Text(context.tr('overdue_issues'))),
                    DropdownMenuItem(value: 'Returned', child: Text(context.tr('returned'))),
                    DropdownMenuItem(value: 'Lost', child: Text(context.tr('lost'))),
                  ],
                  onChanged: (val) {
                    setState(() => _txStatusFilter = val);
                    _refreshData();
                  },
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final dates = await AppDateRangePicker.show(
                    context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                    initialDateRange: _txDateRange,
                    title: 'Library Date Range',
                  );
                  if (dates != null) {
                    setState(() => _txDateRange = dates);
                    _refreshData();
                  }
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.date_range_rounded),
                label: Text(_txDateRange == null
                    ? 'Filter by Date'
                    : '${DateFormat('dd/MM').format(_txDateRange!.start)} - ${DateFormat('dd/MM').format(_txDateRange!.end)}'),
              ),
              if (_txDateRange != null) ...[
                IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.red),
                  onPressed: () {
                    setState(() => _txDateRange = null);
                    _refreshData();
                  },
                )
              ],
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  final data = filteredTxs.map((t) => {
                        'student_name': t.studentId != null ? t.studentName : t.staffName,
                        'father_name': t.studentId != null ? t.fatherName : '(Staff)',
                        'surname': t.studentId != null ? t.surname : '',
                        'book_title': t.bookTitle,
                        'issue_date': t.issueDate,
                        'due_date': t.dueDate,
                        'overdue_days': t.overdueDays,
                        'fine_amount': t.fineAmount,
                      }).toList();
                  ReceiptPdfGenerator.printOverdueBooksReport(records: data);
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: primary),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(Icons.picture_as_pdf_rounded, color: primary),
                label: Text(context.tr('export_list_pdf'), style: TextStyle(color: primary)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── TRANSACTION TABLE ──
          Expanded(
            child: Card(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: filteredTxs.isEmpty
                    ? Center(child: Text(context.tr('no_tx_filters_match')))
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                          columns: [DataColumn(label: Text(context.tr('borrower_name'))),
                            DataColumn(label: Text(context.tr('father_name_role'))),
                            DataColumn(label: Text(context.tr('hostel_location'))),
                            DataColumn(label: Text(context.tr('book_title'))),
                            DataColumn(label: Text(context.tr('issue_date'))),
                            DataColumn(label: Text(context.tr('due_date'))),
                            DataColumn(label: Text(context.tr('status_badge'))),
                            DataColumn(label: Text(context.tr('overdue_days'))),
                            DataColumn(label: Text(context.tr('fine_inr'))),
                            DataColumn(label: Text(context.tr('actions'))),
                          ],
                          rows: filteredTxs.map((tx) {
                            final isOverdue = tx.computedStatus == 'Overdue';
                            final textStyle = isOverdue ? const TextStyle(color: Colors.red, fontWeight: FontWeight.bold) : null;

                            return DataRow(
                              color: isOverdue ? WidgetStateProperty.all(Colors.red.withAlpha(15)) : null,
                              cells: [
                                DataCell(
                                  Text(
                                    tx.borrowerName.isNotEmpty
                                        ? '${tx.borrowerName} ${tx.studentGrNo != null ? "(${tx.studentGrNo})" : ""}'
                                        : (tx.studentId != null
                                            ? '${tx.studentName} ${tx.surname ?? ''} (${tx.studentGrNo ?? 'No GR'})'
                                            : '${tx.staffName ?? 'Staff Member'} (No: ${tx.staffNo ?? '-'})'),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    tx.studentId != null 
                                        ? (tx.fatherName ?? '-') 
                                        : '(Staff member)',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    tx.studentId != null
                                        ? (tx.hostelName != null && tx.hostelName != 'No Hostel'
                                            ? '${tx.hostelName} / Rm: ${tx.roomNumber ?? '-'} / Bed: ${tx.bedNumber ?? '-'}'
                                            : 'Not allocated')
                                        : '-',
                                  ),
                                ),
                                DataCell(Text(tx.bookTitle)),
                                DataCell(Text(tx.issueDate)),
                                DataCell(Text(tx.dueDate, style: textStyle)),
                                DataCell(_buildStatusChip(tx.computedStatus, tx.overdueDays)),
                                DataCell(Text(tx.computedStatus == 'Overdue' ? '${tx.overdueDays} days' : '-', style: textStyle)),
                                DataCell(Text('₹${tx.fineAmount.toStringAsFixed(1)}', style: textStyle)),
                                DataCell(Row(
                                  children: [
                                    if (tx.status != 'Returned') ...[
                                      IconButton(
                                        icon: const Icon(Icons.assignment_return_rounded, color: Colors.green),
                                        tooltip: context.tr('return_book'),
                                        onPressed: () => _returnBook(tx),
                                      ),
                                      if (tx.status != 'Lost') ...[
                                        IconButton(
                                          icon: const Icon(Icons.report_problem_rounded, color: Colors.amber),
                                          tooltip: context.tr('mark_as_lost'),
                                          onPressed: () => _markAsLost(tx.id),
                                        ),
                                      ]
                                    ],
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, color: Colors.blue),
                                      tooltip: context.tr('edit_issue_details'),
                                      onPressed: () => _showEditTransactionDialog(state, tx),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.print_rounded, color: Colors.teal),
                                      tooltip: context.tr('print_return_qr_label'),
                                      onPressed: () {
                                        final hostelInfo = (tx.studentId != null && tx.hostelName != null && tx.hostelName != 'No Hostel')
                                            ? 'Hostel: ${tx.hostelName} / Rm: ${tx.roomNumber ?? '-'} / Bed: ${tx.bedNumber ?? '-'}'
                                            : null;
                                        
                                        final book = state.books.where((b) => b.id == tx.bookId).firstOrNull;
                                        final due = book?.defaultDueDays ?? state.settings.defaultDueDays;
                                        final fpd = book?.finePerDay ?? state.settings.finePerDay;
                                        final lost = book?.lostBookFine ?? state.settings.lostBookFine;
                                        final found = book?.lostBookFoundFine ?? state.settings.lostBookFoundFine;
                                        final qrData = 'TX:${tx.id} | Due Days: $due | Fine/Day: $fpd | Lost Fine: $lost | Found Fine: $found';

                                        ReceiptPdfGenerator.printTransactionQrLabel(
                                          transactionId: tx.id,
                                          borrowerName: tx.borrowerName.isNotEmpty 
                                              ? tx.borrowerName 
                                              : (tx.studentId != null 
                                                  ? '${tx.studentName} ${tx.surname ?? ''}' 
                                                  : (tx.staffName ?? 'Staff')),
                                          borrowerType: tx.studentId != null ? 'Student' : 'Staff',
                                          bookTitle: tx.bookTitle,
                                          issueDate: tx.issueDate,
                                          dueDate: tx.dueDate,
                                          hostelInfo: hostelInfo,
                                          qrData: qrData,
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                                      tooltip: context.tr('delete_log'),
                                      onPressed: () => _deleteTransaction(tx.id),
                                    ),
                                  ],
                                )),
                              ],
                            );
                          }).toList(),
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

  // ─── TAB 3: CATEGORIES, HISTORY & SETTINGS (REDESIGNED) ───────────
  Widget _buildSettingsCategoriesTab(LibraryLoaded state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? AppTheme.primaryLight : AppTheme.primaryColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Navigation Sidebar
        Container(
          width: 260,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade200,
              ),
            ),
            color: isDark ? const Color(0xFF161622) : Colors.grey.shade50,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Library Admin',
                      style: AppTheme.getFontStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage categories, history & settings',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _buildSubTabItem(
                index: 0,
                icon: Icons.category_rounded,
                title: context.tr('book_categories'),
                subtitle: context.tr('manage_categories'),
                badge: '${state.categories.length}',
                primary: primary,
                isDark: isDark,
              ),
              _buildSubTabItem(
                index: 1,
                icon: Icons.settings_suggest_rounded,
                title: context.tr('library_settings_title'),
                subtitle: context.tr('fine_rules_config'),
                primary: primary,
                isDark: isDark,
              ),
              _buildSubTabItem(
                index: 2,
                icon: Icons.history_edu_rounded,
                title: context.tr('borrowing_history'),
                subtitle: context.tr('student_activity_logs'),
                primary: primary,
                isDark: isDark,
              ),
            ],
          ),
        ),

        // Right Main Content
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF0F0F1A) : Colors.white,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Align(
                key: ValueKey<int>(_activeSettingsSubTab),
                alignment: Alignment.topLeft,
                child: _buildActiveSubTabView(state, isDark, primary),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubTabItem({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    String? badge,
    required Color primary,
    required bool isDark,
  }) {
    final isActive = _activeSettingsSubTab == index;
    final activeBg = isDark ? primary.withOpacity(0.12) : primary.withOpacity(0.08);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Material(
        color: isActive ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _activeSettingsSubTab = index;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isActive ? primary : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  size: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTheme.getFontStyle(
                          fontSize: 13.5,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                          color: isActive ? (isDark ? Colors.white : Colors.black87) : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isActive ? primary : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSubTabView(LibraryLoaded state, bool isDark, Color primary) {
    switch (_activeSettingsSubTab) {
      case 0:
        return _buildCategoriesSubTab(state, isDark, primary);
      case 1:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              child: _buildSettingsPanel(state.settings),
            ),
          ),
        );
      case 2:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.history_edu_rounded, color: primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Borrower Activity Log',
                    style: AppTheme.getFontStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildStudentHistorySection(isDark, primary),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCategoriesSubTab(LibraryLoaded state, bool isDark, Color primary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.category_rounded, color: primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Book Categories',
                    style: AppTheme.getFontStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => _showCategoryDialog(null),
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add),
                label: Text(context.tr('add_category')),
              )
            ],
          ),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              mainAxisExtent: 110,
            ),
            itemCount: state.categories.length,
            itemBuilder: (context, idx) {
              final cat = state.categories[idx];
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade100,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.collections_bookmark_rounded, color: primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              cat.name, 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${cat.bookCount} books', 
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 18),
                        onPressed: () => _showCategoryDialog(cat),
                        tooltip: context.tr('edit_category'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 18),
                        onPressed: () => _deleteCategory(cat.id),
                        tooltip: context.tr('delete_category'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Settings Panel Layout
  Widget _buildSettingsPanel(LibrarySettings settings) {
    final formKey = GlobalKey<FormState>();
    final fineController = TextEditingController(text: settings.finePerDay.toString());
    final limitController = TextEditingController(text: settings.maxBooksPerStudent.toString());
    final daysController = TextEditingController(text: settings.defaultDueDays.toString());
    final lostController = TextEditingController(text: settings.lostBookFine.toString());
    final lostFoundController = TextEditingController(text: settings.lostBookFoundFine.toString());
    final primary = Theme.of(context).brightness == Brightness.dark ? AppTheme.primaryLight : AppTheme.primaryColor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('library_settings'), style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                controller: fineController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: context.tr('fine_per_day_inr')),
                validator: (val) => val == null || double.tryParse(val) == null ? 'Enter valid amount' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: limitController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr('max_books_per_student')),
                validator: (val) => val == null || int.tryParse(val) == null ? 'Enter valid number' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: daysController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr('default_due_days')),
                validator: (val) => val == null || int.tryParse(val) == null ? 'Enter valid days' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: lostController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: context.tr('lost_book_fine_inr'),
                  helperText: context.tr('fine_charged_lost_book'),
                ),
                validator: (val) => val == null || double.tryParse(val) == null ? 'Enter valid amount' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: lostFoundController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: context.tr('lost_book_found_fine_inr'),
                  helperText: context.tr('fine_charged_lost_book_returned'),
                ),
                validator: (val) => val == null || double.tryParse(val) == null ? 'Enter valid amount' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    final newSettings = LibrarySettings(
                      finePerDay: double.parse(fineController.text),
                      maxBooksPerStudent: int.parse(limitController.text),
                      defaultDueDays: int.parse(daysController.text),
                      lostBookFine: double.parse(lostController.text),
                      lostBookFoundFine: double.parse(lostFoundController.text),
                    );
                    context.read<LibraryBloc>().add(UpdateSettingsEvent(newSettings));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.tr('library_settings_saved'))),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(context.tr('save_settings')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Student Borrowing History Section with Data Table
  Widget _buildStudentHistorySection(bool isDark, Color primary) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Autocomplete<Student>(
                    displayStringForOption: (student) =>
                        '${student.fullName} ${student.surname ?? ''} (${student.grNo ?? 'No GR'})',
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: context.tr('select_student_name_gr'),
                          prefixIcon: Icon(Icons.person_search_rounded),
                        ),
                      );
                    },
                    optionsBuilder: (textEditingValue) async {
                      if (textEditingValue.text.trim().isEmpty) return const Iterable<Student>.empty();
                      try {
                        return await _studentSearchRepo.searchStudents(textEditingValue.text.trim());
                      } catch (_) {
                        return const Iterable<Student>.empty();
                      }
                    },
                    onSelected: (student) async {
                      setState(() {
                        _historyStudent = student;
                        _isLoadingHistory = true;
                      });
                      try {
                        final repo = LibraryRepository(ApiClient());
                        final history = await repo.getStudentHistory(student.id);
                        setState(() {
                          _studentHistory = history;
                          _isLoadingHistory = false;
                        });
                      } catch (e) {
                        setState(() {
                          _studentHistory = [];
                          _isLoadingHistory = false;
                        });
                      }
                    },
                  ),
                ),
                if (_historyStudent != null) ...[
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      final data = _studentHistory.map((h) => {
                            'book_title': h.bookTitle,
                            'book_author': h.bookAuthor,
                            'issue_date': h.issueDate,
                            'return_date': h.returnDate,
                            'due_date': h.dueDate,
                            'computed_status': h.computedStatus,
                            'fine_amount': h.fineAmount,
                          }).toList();

                      ReceiptPdfGenerator.printStudentBorrowingHistory(
                        studentName: _historyStudent!.fullName,
                        fatherName: _historyStudent!.fatherName ?? '-',
                        grNo: _historyStudent!.grNo ?? '-',
                        history: data,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: primary),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(Icons.picture_as_pdf_rounded, color: primary),
                    label: Text(context.tr('export_history_pdf'), style: TextStyle(color: primary)),
                  ),
                ]
              ],
            ),
            const SizedBox(height: 24),
            if (_isLoadingHistory)
              const Center(child: CircularProgressIndicator())
            else if (_historyStudent == null)
              Center(child: Text(context.tr('search_student_history_hint')))
            else if (_studentHistory.isEmpty)
              Center(child: Text(context.tr('student_no_borrow_logs')))
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                  columns: [DataColumn(label: Text(context.tr('book_title'))),
                    DataColumn(label: Text(context.tr('issue_date'))),
                    DataColumn(label: Text(context.tr('return_date'))),
                    DataColumn(label: Text(context.tr('status'))),
                    DataColumn(label: Text(context.tr('fine_inr'))),
                  ],
                  rows: _studentHistory.map((h) {
                    final returnText = h.returnDate ?? 'Due: ${h.dueDate}';
                    return DataRow(
                      cells: [
                        DataCell(Text(h.bookTitle, style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(h.issueDate)),
                        DataCell(Text(returnText)),
                        DataCell(_buildStatusChip(h.computedStatus, h.overdueDays)),
                        DataCell(Text('₹${h.fineAmount.toStringAsFixed(1)}')),
                      ],
                    );
                  }).toList(),
                ),
              ),),
          ],
        ),
      ),
    );
  }

  // ─── HELPER GRADIENT CARD DESIGN ───
  Widget _buildGradientStatCard(String title, String value, IconData icon, List<Color> colors) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(22.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(50),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, [int overdueDays = 0]) {
    if (status == 'Overdue') {
      return _PulsingOverdueBadge(text: 'Overdue ($overdueDays days)');
    }

    Color bg = Colors.grey;
    switch (status) {
      case 'Issued':
        bg = Colors.green.shade600;
        break;
      case 'Returned':
        bg = Colors.blue.shade600;
        break;
      case 'Lost':
        bg = Colors.black87;
        break;
    }

    return Chip(
      label: Text(status, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      backgroundColor: bg,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide.none),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // Dialog to Add/Edit book
  void _showAddEditBookDialog(LibraryBook? book) {
    final state = context.read<LibraryBloc>().state as LibraryLoaded;
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController(text: book?.title ?? '');
    final authorController = TextEditingController(text: book?.author ?? '');
    final isbnController = TextEditingController(text: book?.isbn ?? '');
    final publisherController = TextEditingController(text: book?.publisher ?? '');
    final copiesController = TextEditingController(text: book?.totalCopies.toString() ?? '1');
    final shelfController = TextEditingController(text: book?.shelfLocation ?? '');
    final descController = TextEditingController(text: book?.description ?? '');
    final dueDaysController = TextEditingController(text: book?.defaultDueDays?.toString() ?? state.settings.defaultDueDays.toString());
    final finePerDayController = TextEditingController(text: book?.finePerDay?.toString() ?? state.settings.finePerDay.toString());
    final lostFineController = TextEditingController(text: book?.lostBookFine?.toString() ?? state.settings.lostBookFine.toString());
    final lostFoundFineController = TextEditingController(text: book?.lostBookFoundFine?.toString() ?? state.settings.lostBookFoundFine.toString());
    String? categoryId = book?.categoryId;
    String language = book?.language ?? 'Urdu';

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final primaryColor = isDark ? AppTheme.primaryLight : AppTheme.primaryColor;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(book == null ? Icons.library_add_rounded : Icons.edit_note_rounded, color: primaryColor),
              const SizedBox(width: 12),
              Text(
                book == null ? 'Add New Book' : 'Edit Book Details',
                style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Container(constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    // Title (Full Width)
                    TextFormField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: context.tr('book_title_required'),
                        prefixIcon: Icon(Icons.book_rounded),
                      ),
                      validator: (val) => val == null || val.isEmpty ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Author & ISBN
                    _buildResponsiveRow(
                      context,
                      TextFormField(
                        controller: authorController,
                        decoration: InputDecoration(
                          labelText: context.tr('author_name'),
                          prefixIcon: Icon(Icons.person_rounded),
                        ),
                      ),
                      TextFormField(
                        controller: isbnController,
                        decoration: InputDecoration(
                          labelText: context.tr('isbn_number'),
                          prefixIcon: Icon(Icons.qr_code_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Category & Language
                    _buildResponsiveRow(
                      context,
                      DropdownButtonFormField<String>(
                        initialValue: categoryId,
                        decoration: InputDecoration(
                          labelText: context.tr('category'),
                          prefixIcon: Icon(Icons.category_rounded),
                        ),
                        items: state.categories
                            .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                            .toList(),
                        onChanged: (val) => categoryId = val,
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: language,
                        decoration: InputDecoration(
                          labelText: context.tr('language'),
                          prefixIcon: Icon(Icons.language_rounded),
                        ),
                        items: [DropdownMenuItem(value: 'Urdu', child: Text(context.tr('urdu_lang'))),
                          DropdownMenuItem(value: 'Arabic', child: Text(context.tr('arabic_lang'))),
                          DropdownMenuItem(value: 'Hindi', child: Text(context.tr('hindi_lang'))),
                          DropdownMenuItem(value: 'English', child: Text(context.tr('english_lang'))),
                        ],
                        onChanged: (val) => language = val ?? 'Urdu',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Publisher & Shelf Location
                    _buildResponsiveRow(
                      context,
                      TextFormField(
                        controller: publisherController,
                        decoration: InputDecoration(
                          labelText: context.tr('publisher'),
                          prefixIcon: Icon(Icons.business_rounded),
                        ),
                      ),
                      TextFormField(
                        controller: shelfController,
                        decoration: const InputDecoration(
                          labelText: 'Shelf Location',
                          prefixIcon: Icon(Icons.place_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Total Copies
                    context.isMobile
                        ? TextFormField(
                            controller: copiesController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('total_copies_required'),
                              prefixIcon: Icon(Icons.copy_rounded),
                            ),
                            validator: (val) => val == null || int.tryParse(val) == null
                                ? 'Enter valid number'
                                : null,
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: copiesController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: context.tr('total_copies_required'),
                                    prefixIcon: Icon(Icons.copy_rounded),
                                  ),
                                  validator: (val) => val == null || int.tryParse(val) == null
                                      ? 'Enter valid number'
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Spacer(),
                            ],
                          ),
                    const SizedBox(height: 16),

                    // Custom Book Rules (Optional - Falls back to Library Settings)
                    _buildResponsiveRow(
                      context,
                      TextFormField(
                        controller: dueDaysController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.tr('default_due_days'),
                          helperText: context.tr('falls_back_library_settings'),
                          prefixIcon: Icon(Icons.calendar_today_rounded),
                        ),
                        validator: (val) => val != null && val.isNotEmpty && int.tryParse(val) == null
                            ? 'Enter valid number'
                            : null,
                      ),
                      TextFormField(
                        controller: finePerDayController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: context.tr('fine_per_day_inr'),
                          helperText: context.tr('falls_back_library_settings'),
                          prefixIcon: Icon(Icons.currency_rupee_rounded),
                        ),
                        validator: (val) => val != null && val.isNotEmpty && double.tryParse(val) == null
                            ? 'Enter valid amount'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildResponsiveRow(
                      context,
                      TextFormField(
                        controller: lostFineController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: context.tr('lost_book_fine_inr'),
                          helperText: context.tr('falls_back_library_settings'),
                          prefixIcon: Icon(Icons.money_off_rounded),
                        ),
                        validator: (val) => val != null && val.isNotEmpty && double.tryParse(val) == null
                            ? 'Enter valid amount'
                            : null,
                      ),
                      TextFormField(
                        controller: lostFoundFineController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: context.tr('lost_book_found_fine_inr'),
                          helperText: context.tr('falls_back_library_settings'),
                          prefixIcon: Icon(Icons.attach_money_rounded),
                        ),
                        validator: (val) => val != null && val.isNotEmpty && double.tryParse(val) == null
                            ? 'Enter valid amount'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description (Full Width)
                    TextFormField(
                      controller: descController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: context.tr('description_remarks'),
                        prefixIcon: Icon(Icons.description_rounded),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final newBook = LibraryBook(
                    id: book?.id ?? '',
                    title: titleController.text.trim(),
                    author: authorController.text.trim().isEmpty ? null : authorController.text.trim(),
                    isbn: isbnController.text.trim().isEmpty ? null : isbnController.text.trim(),
                    categoryId: categoryId,
                    publisher: publisherController.text.trim().isEmpty ? null : publisherController.text.trim(),
                    language: language,
                    totalCopies: int.parse(copiesController.text),
                    availableCopies: book?.availableCopies ?? int.parse(copiesController.text),
                    shelfLocation: shelfController.text.trim().isEmpty ? null : shelfController.text.trim(),
                    description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                    addedDate: book?.addedDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
                    defaultDueDays: dueDaysController.text.isEmpty ? null : int.tryParse(dueDaysController.text),
                    lostBookFine: lostFineController.text.isEmpty ? null : double.tryParse(lostFineController.text),
                    lostBookFoundFine: lostFoundFineController.text.isEmpty ? null : double.tryParse(lostFoundFineController.text),
                    finePerDay: finePerDayController.text.isEmpty ? null : double.tryParse(finePerDayController.text),
                  );

                  if (book == null) {
                    context.read<LibraryBloc>().add(CreateBookEvent(newBook));
                  } else {
                    context.read<LibraryBloc>().add(UpdateBookEvent(id: book.id, book: newBook));
                  }
                  Navigator.pop(ctx);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(book == null ? 'Create Book' : 'Save Changes'),
            )
          ],
        );
      },
    );
  }

  // Dialog to show QR code and print label
  void _showBookQrDialog(LibraryBook book) {
    int selectedCopy = 1;
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final primaryColor = isDark ? AppTheme.primaryLight : AppTheme.primaryColor;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final qrData = _generateBookQrData(
              book: book,
              copyNumber: book.totalCopies > 1 ? selectedCopy : null,
            );

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header (Title)
                    Row(
                      children: [
                        Icon(Icons.qr_code_rounded, color: primaryColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Book QR Label',
                            style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // QR image container
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(10),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: qrData,
                          version: QrVersions.auto,
                          size: 200.0,
                          gapless: false,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      book.title,
                      style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    if (book.author != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'By: ${book.author}',
                        style: AppTheme.getFontStyle(fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (book.totalCopies > 1) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Copy: ', style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: selectedCopy,
                            dropdownColor: isDark ? const Color(0xFF1E1E32) : Colors.white,
                            style: AppTheme.getFontStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
                            items: List.generate(book.totalCopies, (index) => index + 1)
                                .map((copyNum) => DropdownMenuItem<int>(
                                      value: copyNum,
                                      child: Text('Copy #$copyNum of ${book.totalCopies}'),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() {
                                  selectedCopy = val;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                    if (book.shelfLocation != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Chip(
                          label: Text('Shelf: ${book.shelfLocation}'),
                          avatar: const Icon(Icons.place_rounded, size: 16),
                          backgroundColor: primaryColor.withAlpha(20),
                          side: BorderSide.none,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(context.tr('close')),
                        ),
                        const Spacer(),
                        if (book.totalCopies > 1) ...[
                          FilledButton.icon(
                            onPressed: () {
                              final qrDataList = List.generate(book.totalCopies, (idx) {
                                return _generateBookQrData(
                                  book: book,
                                  copyNumber: idx + 1,
                                );
                              });
                              final copyInfoList = List.generate(book.totalCopies, (idx) {
                                return 'Copy #${idx + 1} of ${book.totalCopies}';
                              });
                              ReceiptPdfGenerator.printAllBookQrLabels(
                                bookId: book.id,
                                title: book.title,
                                author: book.author,
                                shelfLocation: book.shelfLocation,
                                qrDataList: qrDataList,
                                copyInfoList: copyInfoList,
                              );
                              Navigator.pop(ctx);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.teal,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.print_rounded),
                            label: Text(context.tr('print_all')),
                          ),
                          const SizedBox(width: 8),
                        ],
                        FilledButton.icon(
                          onPressed: () {
                            ReceiptPdfGenerator.printBookQrLabel(
                              bookId: book.id,
                              qrData: qrData,
                              title: book.title,
                              author: book.author,
                              shelfLocation: book.shelfLocation,
                              copyInfo: book.totalCopies > 1 ? 'Copy #$selectedCopy of ${book.totalCopies}' : null,
                            );
                            Navigator.pop(ctx);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.print_rounded),
                          label: Text(context.tr('print')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteBook(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_book_title')),
        content: Text(context.tr('delete_book_confirm_logs')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              context.read<LibraryBloc>().add(DeleteBookEvent(id));
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: Text(context.tr('delete')),
          )
        ],
      ),
    );
  }

  // Dialog to Add/Edit Category
  void _showCategoryDialog(LibraryCategory? cat) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: cat?.name ?? '');
    final descController = TextEditingController(text: cat?.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cat == null ? 'Add Category' : 'Edit Category'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(labelText: context.tr('category_name_required')),
                validator: (val) => val == null || val.isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descController,
                decoration: InputDecoration(labelText: context.tr('description')),
                maxLines: 2,
              )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                if (cat == null) {
                  context.read<LibraryBloc>().add(CreateCategoryEvent(
                        name: nameController.text.trim(),
                        description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                      ));
                } else {
                  context.read<LibraryBloc>().add(UpdateCategoryEvent(
                        id: cat.id,
                        name: nameController.text.trim(),
                        description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                      ));
                }
                Navigator.pop(ctx);
              }
            },
            child: Text(context.tr('save')),
          )
        ],
      ),
    );
  }

  void _deleteCategory(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_category')),
        content: Text(context.tr('confirm_delete_category')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              context.read<LibraryBloc>().add(DeleteCategoryEvent(id));
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: Text(context.tr('delete')),
          )
        ],
      ),
    );
  }

  void _returnBook(LibraryTransaction tx) {
    final remarksController = TextEditingController();
    final isLost = tx.status == 'Lost';
    // For lost books, default fine = lost_book_found_fine (book-level or settings)
    double defaultFine = 0.0;
    if (isLost) {
      final state = context.read<LibraryBloc>().state;
      if (state is LibraryLoaded) {
        final book = state.books.where(
          (b) => b.id == tx.bookId,
        ).firstOrNull;
        defaultFine = book?.lostBookFoundFine ?? state.settings.lostBookFoundFine;
      } else {
        defaultFine = tx.fineAmount;
      }
    }
    final fineController = TextEditingController(text: isLost ? defaultFine.toStringAsFixed(1) : '0.0');

    showDialog(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2F) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                isLost ? Icons.youtube_searched_for_rounded : Icons.assignment_return_rounded,
                color: isLost ? Colors.orangeAccent : Colors.green,
                size: 26,
              ),
              const SizedBox(width: 10),
              Text(
                isLost ? 'Return Lost Book' : 'Return Book',
                style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Container(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isLost
                      ? 'This book was marked as Lost. Process return entry and specify the final fine to charge for this transaction.'
                      : 'Mark this book as returned. All overdue fines will be automatically computed.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                if (isLost) ...[
                  TextFormField(
                    controller: fineController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: context.tr('final_fine_required'),
                      prefixIcon: Icon(Icons.currency_rupee_rounded),
                      hintText: context.tr('enter_fine_amount_hint'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: remarksController,
                  decoration: InputDecoration(
                    labelText: context.tr('return_remarks_optional'),
                    prefixIcon: Icon(Icons.notes_rounded),
                    hintText: context.tr('return_remarks_eg'),
                  ),
                )
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () {
                final double? customFine = isLost ? (double.tryParse(fineController.text) ?? 0.0) : null;
                context.read<LibraryBloc>().add(ReturnBookEvent(
                      transactionId: tx.id,
                      remarks: remarksController.text.trim().isEmpty ? null : remarksController.text.trim(),
                      customFine: customFine,
                    ));
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isLost 
                        ? 'Lost book returned successfully with ₹${customFine?.toStringAsFixed(1) ?? '0.0'} fine.' 
                        : 'Book marked as returned successfully.'
                    ),
                  ),
                );
              },
              style: FilledButton.styleFrom(backgroundColor: isLost ? Colors.orangeAccent : Colors.green),
              child: Text(isLost ? 'Return & Charge Fine' : 'Mark Returned'),
            )
          ],
        );
      },
    );
  }

  void _markAsLost(String transactionId) {
    final descController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('mark_book_lost')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('lost_book_charge_confirm')),
            const SizedBox(height: 12),
            TextFormField(
              controller: descController,
              decoration: InputDecoration(labelText: context.tr('lost_remarks_optional')),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              context.read<LibraryBloc>().add(MarkBookLostEvent(
                    transactionId: transactionId,
                    remarks: descController.text.trim().isEmpty ? null : descController.text.trim(),
                  ));
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.black87),
            child: Text(context.tr('mark_lost')),
          )
        ],
      ),
    );
  }

  void _deleteTransaction(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_transaction_log')),
        content: Text(context.tr('delete_issue_record_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              context.read<LibraryBloc>().add(DeleteTransactionEvent(id));
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: Text(context.tr('delete')),
          )
        ],
      ),
    );
  }
}

// ─── PULSING OVERDUE BADGE WIDGET ───
class _PulsingOverdueBadge extends StatefulWidget {
  final String text;
  const _PulsingOverdueBadge({required this.text});

  @override
  State<_PulsingOverdueBadge> createState() => _PulsingOverdueBadgeState();
}

class _PulsingOverdueBadgeState extends State<_PulsingOverdueBadge> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Chip(
            label: Text(
              widget.text,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.red.shade700,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide.none),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      },
    );
  }
}
