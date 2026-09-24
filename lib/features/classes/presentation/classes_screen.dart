import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../data/repositories/classes_repository.dart';
import '../data/repositories/academic_repository.dart';
import 'widgets/departments_tab.dart';
import 'widgets/classes_tab.dart';
import 'widgets/courses_tab.dart';
import 'widgets/books_tab.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  late final ClassesRepository _repository;
  late final AcademicRepository _academicRepository;
  bool _isLoading = true;
  List<dynamic> _classes = [];
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _repository = ClassesRepository(ApiClient());
    _academicRepository = AcademicRepository(ApiClient());
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    try {
      final data = await _repository.getAllClasses();
      setState(() {
        _classes = data;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load classes: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildMobileDropdown(double scale) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      {'title': context.tr('department'), 'icon': Icons.business_rounded, 'index': 0},
      {'title': context.tr('class_tab'), 'icon': Icons.class_rounded, 'index': 1},
      {'title': context.tr('courses'), 'icon': Icons.subject_rounded, 'index': 2},
      {'title': context.tr('books'), 'icon': Icons.menu_book_rounded, 'index': 3},
    ];

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12 * scale),
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 2 * scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedTabIndex,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryColor, size: 22 * scale),
          dropdownColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(14 * scale),
          items: items.map((item) {
            final idx = item['index'] as int;
            final title = item['title'] as String;
            final icon = item['icon'] as IconData;
            final isSelected = _selectedTabIndex == idx;

            return DropdownMenuItem<int>(
              value: idx,
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6 * scale),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryColor.withAlpha(20) : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 18 * scale,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (isDark ? Colors.white70 : Colors.grey.shade700),
                    ),
                  ),
                  SizedBox(width: 10 * scale),
                  Text(
                    title,
                    style: AppTheme.getFontStyle(
                      fontSize: 14 * scale,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedTabIndex = val);
            }
          },
        ),
      ),
    );
  }

  Widget _buildTabSwitcher(bool isCompact, double scale) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tabs = [
      _buildTabButton(context.tr('department'), 0, Icons.business_rounded, isCompact, scale),
      _buildTabButton(context.tr('class_tab'), 1, Icons.class_rounded, isCompact, scale),
      _buildTabButton(context.tr('courses'), 2, Icons.subject_rounded, isCompact, scale),
      _buildTabButton(context.tr('books'), 3, Icons.menu_book_rounded, isCompact, scale),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2D) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      padding: EdgeInsets.all(3 * scale),
      child: isCompact
          ? Row(
              children: tabs.map((t) => Expanded(child: t)).toList(),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: tabs,
              ),
            ),
    );
  }

  Widget _buildTabButton(String title, int index, IconData icon, bool isCompact, double scale) {
    final isSelected = _selectedTabIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? (3 * scale) : 20,
          vertical: isCompact ? (7 * scale) : 10,
        ),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8 * scale),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isCompact ? (13 * scale) : 18,
              color: isSelected
                  ? Colors.white
                  : (isDark ? Colors.white54 : Colors.black54),
            ),
            SizedBox(width: isCompact ? (3 * scale) : 6 * scale),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.getFontStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white54 : Colors.black54),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: isCompact ? (10.5 * scale) : 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _classes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (_selectedTabIndex) {
      case 0:
        return DepartmentsTab(repository: _academicRepository);
      case 1:
        return ClassesTab(
          repository: _repository,
          academicRepository: _academicRepository,
        );
      case 2:
        return CoursesTab(repository: _academicRepository, classes: _classes);
      case 3:
        return BooksTab(repository: _academicRepository, classes: _classes);
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 700;
        final scale = isCompact ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

        return Padding(
          padding: EdgeInsets.all(isCompact ? (10 * scale) : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show Academic Structure Heading only on Desktop view
              if (!isCompact) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('academic_structure'),
                            style: AppTheme.getFontStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.tr('manage_academic_subtitle'),
                            style: AppTheme.getFontStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              // Navigation Bar: Dropdown on Mobile, Tab Bar on Desktop
              isCompact ? _buildMobileDropdown(scale) : _buildTabSwitcher(isCompact, scale),
              if (!isCompact) const SizedBox(height: 24),
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        );
      },
    );
  }
}
