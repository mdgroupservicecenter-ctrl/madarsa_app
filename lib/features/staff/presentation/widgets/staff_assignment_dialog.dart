import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/platform_utils.dart';
import '../../../classes/data/repositories/academic_repository.dart';
import '../../data/repositories/staff_repository.dart';

class StaffAssignmentDialog extends StatefulWidget {
  final String staffId;
  final VoidCallback onSaved;

  const StaffAssignmentDialog({
    super.key,
    required this.staffId,
    required this.onSaved,
  });

  @override
  State<StaffAssignmentDialog> createState() => _StaffAssignmentDialogState();
}

class _StaffAssignmentDialogState extends State<StaffAssignmentDialog> {
  final AcademicRepository _academicRepository = AcademicRepository(ApiClient());
  final StaffRepository _staffRepository = StaffRepository(ApiClient());
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  List<dynamic> _hierarchy = [];
  Set<String> _selectedCourseBookIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final hierarchy = await _academicRepository.getAcademicHierarchy();
      final staff = await _staffRepository.getById(widget.staffId);

      final preAssigned = (staff.assignedBooks ?? [])
          .map((b) => b['course_book_id'].toString())
          .toSet();

      if (mounted) {
        setState(() {
          _hierarchy = hierarchy;
          _selectedCourseBookIds = preAssigned;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveAssignments() async {
    setState(() => _isSaving = true);
    try {
      await _staffRepository.assignBooks(
        widget.staffId,
        _selectedCourseBookIds.toList(),
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save assignments: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  void _selectAll(bool select) {
    setState(() {
      if (!select) {
        _selectedCourseBookIds.clear();
        return;
      }
      for (final cls in _hierarchy) {
        final courses = cls['courses'] as List? ?? [];
        for (final course in courses) {
          final books = course['books'] as List? ?? [];
          for (final book in books) {
            final id = book['course_book_id'].toString();
            _selectedCourseBookIds.add(id);
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isMobile = context.isMobile || width < 700;
    final scale = isMobile ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

    final formContent = _isLoading
        ? Center(
            child: Padding(
              padding: EdgeInsets.all(40 * scale),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    strokeWidth: 3 * scale,
                    color: AppTheme.primaryColor,
                  ),
                  SizedBox(height: 16 * scale),
                  Text(
                    context.tr('loading'),
                    style: AppTheme.getFontStyle(
                      fontSize: 14 * scale,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          )
        : _hierarchy.isEmpty
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(40 * scale),
                  child: Text(
                    context.tr('no_academic_structure'),
                    style: AppTheme.getFontStyle(
                      fontSize: 14 * scale,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Search & Batch Actions Bar ───────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16 * scale,
                      16 * scale,
                      16 * scale,
                      12 * scale,
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          style: AppTheme.getFontStyle(fontSize: 14 * scale),
                          decoration: InputDecoration(
                            hintText: '${context.tr('search')} books...',
                            hintStyle: AppTheme.getFontStyle(
                              fontSize: 13 * scale,
                              color: Colors.grey.shade500,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18 * scale,
                              color: AppTheme.primaryColor,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear_rounded,
                                      size: 16 * scale,
                                    ),
                                    onPressed: () => _searchCtrl.clear(),
                                  )
                                : null,
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF2A2A3E)
                                : Colors.grey.shade100,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14 * scale,
                              vertical: 12 * scale,
                            ),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(12 * scale),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(12 * scale),
                              borderSide: BorderSide(
                                color: AppTheme.primaryColor,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 10 * scale),
                        Row(
                          children: [
                            Text(
                              '${_selectedCourseBookIds.length} ${context.tr('assigned_books')}',
                              style: AppTheme.getFontStyle(
                                fontSize: 12 * scale,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _selectAll(true),
                              icon: Icon(
                                Icons.select_all_rounded,
                                size: 14 * scale,
                              ),
                              label: Text(
                                'Select All',
                                style: AppTheme.getFontStyle(
                                  fontSize: 11 * scale,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8 * scale,
                                ),
                              ),
                            ),
                            SizedBox(width: 4 * scale),
                            TextButton.icon(
                              onPressed: () => _selectAll(false),
                              icon: Icon(
                                Icons.deselect_rounded,
                                size: 14 * scale,
                              ),
                              label: Text(
                                'Clear All',
                                style: AppTheme.getFontStyle(
                                  fontSize: 11 * scale,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade400,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red.shade400,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8 * scale,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white.withAlpha(10)
                        : Colors.grey.shade200,
                  ),

                  // ── Hierarchy List ─────────────────────────────────────
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8 * scale,
                        vertical: 8 * scale,
                      ),
                      itemCount: _hierarchy.length,
                      itemBuilder: (context, cIndex) {
                        final cls = _hierarchy[cIndex];
                        final className = (cls['name'] ?? '').toString();
                        final courses = cls['courses'] as List? ?? [];

                        // Filter courses/books if searching
                        final matchingCourses = courses.where((course) {
                          final courseName =
                              (course['name'] ?? '').toString().toLowerCase();
                          final books = course['books'] as List? ?? [];
                          if (className.toLowerCase().contains(_searchQuery) ||
                              courseName.contains(_searchQuery)) {
                            return true;
                          }
                          return books.any((b) => (b['name'] ?? '')
                              .toString()
                              .toLowerCase()
                              .contains(_searchQuery));
                        }).toList();

                        if (matchingCourses.isEmpty &&
                            _searchQuery.isNotEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            leading: Container(
                              padding: EdgeInsets.all(6 * scale),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB8860B).withAlpha(20),
                                borderRadius:
                                    BorderRadius.circular(8 * scale),
                              ),
                              child: Icon(
                                Icons.class_rounded,
                                size: 16 * scale,
                                color: const Color(0xFFB8860B),
                              ),
                            ),
                            title: Text(
                              className,
                              style: AppTheme.getFontStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15 * scale,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A2E),
                              ),
                            ),
                            children: matchingCourses.map<Widget>((course) {
                              final courseName =
                                  (course['name'] ?? '').toString();
                              final books = course['books'] as List? ?? [];

                              final matchingBooks = books.where((b) {
                                if (_searchQuery.isEmpty) return true;
                                final bName =
                                    (b['name'] ?? '').toString().toLowerCase();
                                final bAuth = (b['author'] ?? '')
                                    .toString()
                                    .toLowerCase();
                                return className
                                        .toLowerCase()
                                        .contains(_searchQuery) ||
                                    courseName
                                        .toLowerCase()
                                        .contains(_searchQuery) ||
                                    bName.contains(_searchQuery) ||
                                    bAuth.contains(_searchQuery);
                              }).toList();

                              if (matchingBooks.isEmpty &&
                                  _searchQuery.isNotEmpty) {
                                return const SizedBox.shrink();
                              }

                              return Padding(
                                padding: EdgeInsets.only(left: 12 * scale),
                                child: ExpansionTile(
                                  initiallyExpanded: true,
                                  leading: Icon(
                                    Icons.school_outlined,
                                    size: 16 * scale,
                                    color: AppTheme.primaryColor,
                                  ),
                                  title: Text(
                                    courseName,
                                    style: AppTheme.getFontStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13 * scale,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                  children: matchingBooks.map<Widget>((book) {
                                    final courseBookId = book['course_book_id']
                                        .toString();
                                    final bookName =
                                        (book['name'] ?? '').toString();
                                    final author = book['author'] != null &&
                                            book['author']
                                                .toString()
                                                .isNotEmpty
                                        ? book['author'].toString()
                                        : null;
                                    final isSelected = _selectedCourseBookIds
                                        .contains(courseBookId);

                                    return Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8 * scale,
                                        vertical: 2 * scale,
                                      ),
                                      child: Container(
                                        margin: EdgeInsets.only(
                                          bottom: 4 * scale,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppTheme.primaryColor
                                                  .withAlpha(isDark ? 25 : 12)
                                              : (isDark
                                                  ? Colors.white.withAlpha(5)
                                                  : Colors.grey.shade50),
                                          borderRadius: BorderRadius.circular(
                                              10 * scale),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppTheme.primaryColor
                                                    .withAlpha(60)
                                                : (isDark
                                                    ? Colors.white.withAlpha(10)
                                                    : Colors.grey.shade200),
                                          ),
                                        ),
                                        child: CheckboxListTile(
                                          dense: true,
                                          activeColor: AppTheme.primaryColor,
                                          checkboxShape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                4 * scale),
                                          ),
                                          title: Text(
                                            bookName,
                                            style: AppTheme.getFontStyle(
                                              fontSize: 13 * scale,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF1A1A2E),
                                            ),
                                          ),
                                          subtitle: author != null
                                              ? Text(
                                                  '${context.tr('author')}: $author',
                                                  style: TextStyle(
                                                    fontSize: 11 * scale,
                                                    color: Colors.grey.shade500,
                                                  ),
                                                )
                                              : null,
                                          value: isSelected,
                                          onChanged: (val) {
                                            setState(() {
                                              if (val == true) {
                                                _selectedCourseBookIds
                                                    .add(courseBookId);
                                              } else {
                                                _selectedCourseBookIds
                                                    .remove(courseBookId);
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );

    if (isMobile) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF141421) : Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(isDark, isMobile, scale),
              Expanded(child: formContent),
              _buildFooter(isDark, scale),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 24 * scale,
      ),
      child: Container(
        width: min(650.0, MediaQuery.of(context).size.width - 32),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(24 * scale),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 100 : 40),
              blurRadius: 40 * scale,
              offset: Offset(0, 16 * scale),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(isDark, isMobile, scale),
            Expanded(child: formContent),
            _buildFooter(isDark, scale),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark, bool isMobile, double scale) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 * scale : 24 * scale,
        18 * scale,
        16 * scale,
        16 * scale,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF043927), Color(0xFF0D6B4E)],
        ),
        borderRadius: isMobile
            ? BorderRadius.zero
            : BorderRadius.vertical(top: Radius.circular(24 * scale)),
      ),
      child: Row(
        children: [
          if (isMobile) ...[
            InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(12 * scale),
              child: Container(
                padding: EdgeInsets.all(8 * scale),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 20 * scale,
                ),
              ),
            ),
            SizedBox(width: 12 * scale),
          ] else ...[
            Container(
              padding: EdgeInsets.all(10 * scale),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(25),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                color: Colors.white,
                size: 22 * scale,
              ),
            ),
            SizedBox(width: 14 * scale),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  context.tr('assign_books'),
                  style: AppTheme.getFontStyle(
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Select books to assign to staff member',
                  style: AppTheme.getFontStyle(
                    fontSize: 12 * scale,
                    color: Colors.white.withAlpha(180),
                  ),
                ),
              ],
            ),
          ),
          if (!isMobile)
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 24 * scale,
              ),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────
  Widget _buildFooter(bool isDark, double scale) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24 * scale,
        14 * scale,
        24 * scale,
        18 * scale,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
          ),
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(24 * scale),
        ),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, size: 18 * scale),
            label: Text(
              context.tr('cancel'),
              style: AppTheme.getFontStyle(fontSize: 13 * scale),
            ),
          ),
          const Spacer(),
          if (_isSaving)
            SizedBox(
              width: 24 * scale,
              height: 24 * scale,
              child: CircularProgressIndicator(strokeWidth: 2 * scale),
            )
          else
            FilledButton.icon(
              onPressed: _saveAssignments,
              icon: Icon(Icons.save_rounded, size: 18 * scale),
              label: Text(
                context.tr('save_assignments'),
                style: AppTheme.getFontStyle(
                  fontSize: 14 * scale,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: EdgeInsets.symmetric(
                  horizontal: 24 * scale,
                  vertical: 12 * scale,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12 * scale),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
