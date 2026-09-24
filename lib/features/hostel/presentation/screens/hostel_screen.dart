import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/platform_utils.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/receipt_pdf_generator.dart';
import '../../../students/data/repositories/student_repository.dart';
import '../../../students/data/models/student_model.dart';
import '../bloc/hostel_bloc.dart';
import '../../data/models/hostel_models.dart';
import '../../data/repositories/hostel_repository.dart';
import '../../../../core/widgets/app_date_range_picker.dart';

class HostelScreen extends StatefulWidget {
  const HostelScreen({super.key});

  @override
  State<HostelScreen> createState() => _HostelScreenState();
}

class _HostelScreenState extends State<HostelScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  // Filter states
  String _selectedStatus = 'All'; // 'All', 'Active', 'Vacated'
  String? _selectedFilterHostelId;
  String? _selectedFilterRoomId;
  String? _selectedFilterDateStart;
  String? _selectedFilterDateEnd;

  // Hierarchical states
  Hostel? _selectedHostel; // null means we are showing Hostels list

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refreshData() {
    context.read<HostelBloc>().add(
          LoadHostelData(
            hostelId: _selectedHostel?.id,
            roomId: _selectedFilterRoomId,
            status: _selectedStatus,
            search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocConsumer<HostelBloc, HostelState>(
      listener: (context, state) {
        if (state is HostelError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message, style: AppTheme.getFontStyle(color: Colors.white)),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is HostelInitial) {
          return const Center(child: CircularProgressIndicator());
        }

        List<Hostel> hostels = [];
        List<HostelRoom> rooms = [];
        List<HostelAllocation> allocations = [];
        bool isLoading = state is HostelLoading;

        if (state is HostelLoaded) {
          hostels = state.hostels;
          rooms = state.rooms;
          allocations = state.allocations;
        }

        // Stats calculations
        final int totalHostels = hostels.length;
        final int totalRooms = hostels.fold(0, (sum, h) => sum + h.roomCount);
        final int totalCapacity = hostels.fold(0, (sum, h) => sum + h.capacity);
        final int occupiedBeds = hostels.fold(0, (sum, h) => sum + h.occupiedCount);
        final int vacantBeds = totalCapacity - occupiedBeds;

        final stats = [
          (
            label: context.tr('total_hostels'),
            value: totalHostels.toString(),
            icon: Icons.domain_rounded,
            color: const Color(0xFF0D6B4E),
          ),
          (
            label: context.tr('total_rooms'),
            value: totalRooms.toString(),
            icon: Icons.meeting_room_rounded,
            color: const Color(0xFF1565C0),
          ),
          (
            label: context.tr('occupied_beds'),
            value: '$occupiedBeds / $totalCapacity',
            icon: Icons.airline_seat_flat_rounded,
            color: const Color(0xFF6A1B9A),
          ),
          (
            label: context.tr('vacant_beds'),
            value: vacantBeds.toString(),
            icon: Icons.airline_seat_flat_angled_rounded,
            color: const Color(0xFFE65100),
          ),
        ];

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF0F0F1A) : const Color(0xFFF8F9FA),
          body: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth < 600
                        ? 1
                        : constraints.maxWidth < 900
                            ? 2
                            : 4;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 2.3,
                      ),
                      itemCount: stats.length,
                      itemBuilder: (context, idx) {
                        final stat = stats[idx];
                        return _MiniStat(
                          label: stat.label,
                          value: stat.value,
                          icon: stat.icon,
                          color: stat.color,
                          isDark: isDark,
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Controls & Tab Bar
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF161625) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200,
                          ),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          isScrollable: context.isMobile,
                          indicator: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          labelColor: Colors.white,
                          unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          labelStyle: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          unselectedLabelStyle: AppTheme.getFontStyle(fontWeight: FontWeight.normal, fontSize: 13),
                          tabs: [Tab(text: context.isMobile ? 'Stay Records' : 'Stay Records & Allocations'),
                            Tab(text: 'Rooms Configuration'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _refreshData,
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Tab Content
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildStayRecordsTab(allocations, rooms, hostels, isDark),
                            _buildRoomsTab(hostels, rooms, isDark),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── TAB 1: STAY RECORDS ───────────────────────────────────────────

  Widget _buildStayRecordsTab(
      List<HostelAllocation> allocations, List<HostelRoom> rooms, List<Hostel> hostels, bool isDark) {
    // Client-side date and hostel/room filters
    final filtered = allocations.where((a) {
      if (_selectedFilterHostelId != null && a.hostelId != _selectedFilterHostelId) {
        return false;
      }
      if (_selectedFilterRoomId != null && a.roomId != _selectedFilterRoomId) {
        return false;
      }
      if (_selectedFilterDateStart != null) {
        final start = DateTime.tryParse(_selectedFilterDateStart!);
        final alloc = DateTime.tryParse(a.allocationDate);
        if (start != null && alloc != null && alloc.isBefore(start)) return false;
      }
      if (_selectedFilterDateEnd != null) {
        final end = DateTime.tryParse(_selectedFilterDateEnd!);
        final alloc = DateTime.tryParse(a.allocationDate);
        if (end != null && alloc != null && alloc.isAfter(end)) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Search & Filter Row
        context.isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by Student Name, GR.No., Hostel, or Room...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _refreshData();
                              },
                            )
                          : null,
                    ),
                    onFieldSubmitted: (_) => _refreshData(),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade300),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedStatus,
                              items: [DropdownMenuItem(value: 'All', child: Text(context.tr('all_stays'))),
                                DropdownMenuItem(value: 'Active', child: Text(context.tr('active_stay'))),
                                DropdownMenuItem(value: 'Vacated', child: Text(context.tr('vacated_stay'))),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedStatus = val);
                                  _refreshData();
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade300),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: _selectedFilterHostelId,
                              hint: Text(context.tr('filter_hostel')),
                              items: [
                                DropdownMenuItem(value: null, child: Text(context.tr('all_hostels'))),
                                ...hostels.map((h) => DropdownMenuItem(
                                      value: h.id,
                                      child: Text(h.name),
                                    )),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedFilterHostelId = val;
                                  _selectedFilterRoomId = null;
                                });
                                _refreshData();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade300),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: _selectedFilterRoomId,
                              hint: Text(context.tr('filter_room')),
                              items: [
                                DropdownMenuItem(value: null, child: Text(context.tr('all_rooms'))),
                                ...rooms
                                    .where((r) => _selectedFilterHostelId == null || r.hostelId == _selectedFilterHostelId)
                                    .map((r) => DropdownMenuItem(
                                          value: r.id,
                                          child: Text('${r.hostelName ?? "Hostel"} - Room ${r.roomNumber}'),
                                        )),
                              ],
                              onChanged: (val) {
                                setState(() => _selectedFilterRoomId = val);
                                _refreshData();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.date_range_rounded),
                          tooltip: context.tr('filter_date_range'),
                          onPressed: () => _showDateRangePicker(context),
                        ),
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red),
                          tooltip: context.tr('export_stay_report'),
                          onPressed: () => _printStayRecordsReport(filtered),
                        ),
                        const SizedBox(width: 4),
                        FilledButton.icon(
                          onPressed: () => _showAllocateRoomDialog(rooms),
                          icon: const Icon(Icons.add_home_work_rounded),
                          label: Text(context.tr('allocate_room')),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by Student Name, GR.No., Hostel, or Room...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _refreshData();
                                },
                              )
                            : null,
                      ),
                      onFieldSubmitted: (_) => _refreshData(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedStatus,
                        items: [DropdownMenuItem(value: 'All', child: Text(context.tr('all_stays'))),
                          DropdownMenuItem(value: 'Active', child: Text(context.tr('active_stay'))),
                          DropdownMenuItem(value: 'Vacated', child: Text(context.tr('vacated_stay'))),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedStatus = val);
                            _refreshData();
                          }
                        },
                      ),
                    ),
                  ),
                   const SizedBox(width: 12),
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 12),
                     decoration: BoxDecoration(
                       color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                       borderRadius: BorderRadius.circular(12),
                       border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade300),
                     ),
                     child: DropdownButtonHideUnderline(
                       child: DropdownButton<String?>(
                         value: _selectedFilterHostelId,
                         hint: Text(context.tr('filter_hostel')),
                         items: [
                           DropdownMenuItem(value: null, child: Text(context.tr('all_hostels'))),
                           ...hostels.map((h) => DropdownMenuItem(
                                 value: h.id,
                                 child: Text(h.name),
                               )),
                         ],
                         onChanged: (val) {
                           setState(() {
                             _selectedFilterHostelId = val;
                             _selectedFilterRoomId = null;
                           });
                           _refreshData();
                         },
                       ),
                     ),
                   ),
                   const SizedBox(width: 12),
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 12),
                     decoration: BoxDecoration(
                       color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                       borderRadius: BorderRadius.circular(12),
                       border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade300),
                     ),
                     child: DropdownButtonHideUnderline(
                       child: DropdownButton<String?>(
                         value: _selectedFilterRoomId,
                         hint: Text(context.tr('filter_room')),
                         items: [
                           DropdownMenuItem(value: null, child: Text(context.tr('all_rooms'))),
                           ...rooms
                               .where((r) => _selectedFilterHostelId == null || r.hostelId == _selectedFilterHostelId)
                               .map((r) => DropdownMenuItem(
                                     value: r.id,
                                     child: Text('${r.hostelName ?? "Hostel"} - Room ${r.roomNumber}'),
                                   )),
                         ],
                         onChanged: (val) {
                           setState(() => _selectedFilterRoomId = val);
                           _refreshData();
                         },
                       ),
                     ),
                   ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.date_range_rounded),
                    tooltip: context.tr('filter_date_range'),
                    onPressed: () => _showDateRangePicker(context),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red),
                    tooltip: context.tr('export_stay_report'),
                    onPressed: () => _printStayRecordsReport(filtered),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _showAllocateRoomDialog(rooms),
                    icon: const Icon(Icons.add_home_work_rounded),
                    label: Text(context.tr('allocate_room')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
        const SizedBox(height: 16),

        // Date filter tags
        if (_selectedFilterDateStart != null || _selectedFilterDateEnd != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text(
                  'Date Filter: ${_selectedFilterDateStart ?? "Start"} to ${_selectedFilterDateEnd ?? "End"}',
                  style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    setState(() {
                      _selectedFilterDateStart = null;
                      _selectedFilterDateEnd = null;
                    });
                  },
                  child: const Icon(Icons.cancel_rounded, size: 16, color: Colors.red),
                ),
              ],
            ),
          ),

        // Stay Records List
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('No stay records match the criteria.', style: AppTheme.getFontStyle(color: Colors.grey.shade500)))
              : Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 28,
                          headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF151522) : Colors.grey.shade100),
                          columns: [
                            DataColumn(label: Text('Student Name', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Village', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Hostel Name', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Room No', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Bed No', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Class', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Allocation Date', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(context.tr('status'), style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Vacated Date', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text(context.tr('actions'), style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: filtered.map((alloc) {
                            final isActive = alloc.status == 'Active';
                            return DataRow(
                              cells: [
                                DataCell(Text(alloc.studentName, style: AppTheme.getFontStyle())),
                                DataCell(Text(alloc.village ?? '-', style: AppTheme.getFontStyle())),
                                DataCell(Text(alloc.hostelName, style: AppTheme.getFontStyle())),
                                DataCell(Text('Room ${alloc.roomNumber}', style: AppTheme.getFontStyle())),
                                DataCell(Text(alloc.bedNumber, style: AppTheme.getFontStyle())),
                                DataCell(Text(alloc.className ?? '-', style: AppTheme.getFontStyle())),
                                DataCell(Text(alloc.allocationDate, style: AppTheme.getFontStyle())),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isActive ? Colors.green.withAlpha(30) : Colors.grey.withAlpha(30),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      alloc.status,
                                      style: AppTheme.getFontStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isActive ? Colors.green.shade800 : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(Text(alloc.vacateDate ?? '-', style: AppTheme.getFontStyle())),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isActive)
                                        IconButton(
                                          icon: const Icon(Icons.logout_rounded, color: Colors.orange, size: 18),
                                          tooltip: 'Vacate Stay',
                                          onPressed: () => _showVacateStayDialog(alloc),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                                        tooltip: context.tr('delete_log'),
                                        onPressed: () => _confirmDeleteAllocation(alloc.id),
                                      ),
                                    ],
                                  ),
                                ),
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
    );
  }

  // ─── TAB 2: ROOMS/HOSTELS TAB ──────────────────────────────────────

  Widget _buildRoomsTab(List<Hostel> hostels, List<HostelRoom> rooms, bool isDark) {
    if (_selectedHostel == null) {
      // LEVEL 1: Hostels List
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hostels List',
                style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
              ),
              FilledButton.icon(
                onPressed: () => _showHostelFormDialog(),
                icon: const Icon(Icons.add_rounded),
                label: Text(context.tr('add_hostel')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: hostels.isEmpty
                ? Center(child: Text('No hostels configured yet.', style: AppTheme.getFontStyle(color: Colors.grey.shade500)))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 350,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.4,
                    ),
                    itemCount: hostels.length,
                    itemBuilder: (ctx, idx) {
                      final hostel = hostels[idx];
                      final double usagePercent = hostel.capacity > 0 ? (hostel.occupiedCount / hostel.capacity) : 0.0;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedHostel = hostel;
                          });
                          _refreshData();
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200,
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 50 : 10),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      hostel.name,
                                      style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        onPressed: () => _showHostelFormDialog(hostel),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                        onPressed: () => _confirmDeleteHostel(hostel),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                              if (hostel.description != null && hostel.description!.isNotEmpty)
                                Text(
                                  hostel.description!,
                                  style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const Spacer(),
                              Text(
                                '${hostel.roomCount} Rooms configured',
                                style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${hostel.occupiedCount}/${hostel.capacity} Beds Occupied',
                                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${(usagePercent * 100).toStringAsFixed(0)}%',
                                    style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: usagePercent,
                                  minHeight: 5,
                                  backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                  color: usagePercent > 0.85 ? Colors.red : Colors.blue,
                                ),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    } else {
      // LEVEL 2: Rooms list for selected Hostel
      return Column(
        children: [
          context.isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedHostel = null;
                            });
                            _refreshData();
                          },
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: Text(context.tr('back_to_hostels')),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () => _showRoomFormDialog(),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(context.tr('add_room')),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Text(
                        '${_selectedHostel!.name}  •  Rooms',
                        style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedHostel = null;
                        });
                        _refreshData();
                      },
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: Text(context.tr('back_to_hostels')),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedHostel!.name}  •  Rooms Configuration',
                      style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => _showRoomFormDialog(),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.tr('add_room')),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 16),
          Expanded(
            child: rooms.isEmpty
                ? Center(child: Text('No rooms configured under this hostel.', style: AppTheme.getFontStyle(color: Colors.grey.shade500)))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 320,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.3,
                    ),
                    itemCount: rooms.length,
                    itemBuilder: (ctx, idx) {
                      final room = rooms[idx];
                      final usagePercent = room.bedCount > 0 ? (room.occupiedCount / room.bedCount) : 0.0;
                      final isFull = room.vacantCount == 0 && room.bedCount > 0;

                      return InkWell(
                        onTap: () => _showBedsManagementDialog(room),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isFull
                                  ? Colors.redAccent.withAlpha(80)
                                  : isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200,
                              width: isFull ? 1.5 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 50 : 10),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Room ${room.roomNumber}',
                                          style: AppTheme.getFontStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (room.description != null && room.description!.isNotEmpty)
                                          Text(
                                            room.description!,
                                            style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey.shade500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        onPressed: () => _showRoomFormDialog(room),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                        onPressed: () => _confirmDeleteRoom(room),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${room.occupiedCount}/${room.bedCount} Beds Occupied',
                                    style: AppTheme.getFontStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isFull ? Colors.redAccent : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                                    ),
                                  ),
                                  Text(
                                    '${room.vacantCount} Vacant',
                                    style: AppTheme.getFontStyle(
                                      fontSize: 12,
                                      color: isFull ? Colors.grey : Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: usagePercent,
                                  minHeight: 6,
                                  backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                  color: isFull
                                      ? Colors.redAccent
                                      : usagePercent > 0.75 ? Colors.orange : Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    }
  }

  // ─── DIALOGS ───────────────────────────────────────────────────────

  void _showDateRangePicker(BuildContext context) async {
    final picked = await AppDateRangePicker.show(
      context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _selectedFilterDateStart != null && _selectedFilterDateEnd != null
          ? DateTimeRange(
              start: DateTime.parse(_selectedFilterDateStart!),
              end: DateTime.parse(_selectedFilterDateEnd!),
            )
          : null,
      title: 'Hostel Date Range',
    );
    if (picked != null) {
      setState(() {
        _selectedFilterDateStart = picked.start.toIso8601String().split('T')[0];
        _selectedFilterDateEnd = picked.end.toIso8601String().split('T')[0];
      });
    }
  }

  void _printStayRecordsReport(List<HostelAllocation> records) async {
    final List<Map<String, dynamic>> mapped = records
        .map((r) => {
              'student_name': r.studentName,
              'father_name': r.fatherName ?? '-',
              'surname': r.surname ?? '-',
              'village': r.village ?? '-',
              'bed_number': r.bedNumber,
              'age': r.age?.toString() ?? '-',
              'hostel_name': r.hostelName,
              'room_number': r.roomNumber,
              'allocation_date': r.allocationDate,
              'status': r.status,
              'vacate_date': r.vacateDate ?? '-',
            })
        .toList();

    String? printHostel;
    String? printRoom;
    
    if (_selectedFilterRoomId != null && records.isNotEmpty) {
      final matchedRoom = records.firstWhere((r) => r.roomId == _selectedFilterRoomId, orElse: () => records.first);
      printHostel = matchedRoom.hostelName;
      printRoom = matchedRoom.roomNumber;
    } else if (_selectedHostel != null) {
      printHostel = _selectedHostel!.name;
    }

    try {
      await ReceiptPdfGenerator.printHostelStayRecordsReport(
        records: mapped,
        hostelName: printHostel,
        roomNumber: printRoom,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error printing report: $e', style: AppTheme.getFontStyle(color: Colors.white)),
            backgroundColor: Colors.redAccent),
      );
    }
  }

  void _showHostelFormDialog([Hostel? hostel]) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: hostel?.name);
    final descController = TextEditingController(text: hostel?.description);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(hostel == null ? 'Add Hostel' : 'Edit Hostel Details', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: context.tr('hostel_name_eg')),
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descController,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: context.tr('description_optional')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final name = nameController.text.trim();
                  final desc = descController.text.trim();

                  if (hostel == null) {
                    context.read<HostelBloc>().add(
                          CreateHostelEvent(name: name, description: desc.isEmpty ? null : desc),
                        );
                  } else {
                    context.read<HostelBloc>().add(
                          UpdateHostelEvent(id: hostel.id, name: name, description: desc.isEmpty ? null : desc),
                        );
                  }
                  Navigator.pop(ctx);
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
              child: Text(hostel == null ? 'Create Hostel' : 'Save Changes'),
            )
          ],
        );
      },
    );
  }

  void _confirmDeleteHostel(Hostel hostel) {
    if (hostel.occupiedCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Cannot Delete Hostel', style: AppTheme.getFontStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Text('Hostel "${hostel.name}" has active allocations. Please vacate them first.', style: AppTheme.getFontStyle()),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Hostel "${hostel.name}"?', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this hostel and all rooms/beds permanently?', style: AppTheme.getFontStyle()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              context.read<HostelBloc>().add(DeleteHostelEvent(hostel.id));
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }

  void _showRoomFormDialog([HostelRoom? room]) {
    final formKey = GlobalKey<FormState>();
    final numController = TextEditingController(text: room?.roomNumber);
    final descController = TextEditingController(text: room?.description);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(room == null ? 'Add Room' : 'Edit Room Details', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: numController,
                  decoration: const InputDecoration(labelText: 'Room Number (e.g. 101, A-3)'),
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: descController,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: context.tr('description_optional')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate() && _selectedHostel != null) {
                  final roomNum = numController.text.trim();
                  final desc = descController.text.trim();

                  if (room == null) {
                    context.read<HostelBloc>().add(
                          CreateRoomEvent(
                            hostelId: _selectedHostel!.id,
                            roomNumber: roomNum,
                            description: desc.isEmpty ? null : desc,
                          ),
                        );
                  } else {
                    context.read<HostelBloc>().add(
                          UpdateRoomEvent(
                            id: room.id,
                            roomNumber: roomNum,
                            description: desc.isEmpty ? null : desc,
                          ),
                        );
                  }
                  Navigator.pop(ctx);
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
              child: Text(room == null ? 'Create Room' : 'Save Changes'),
            )
          ],
        );
      },
    );
  }

  void _confirmDeleteRoom(HostelRoom room) {
    if (room.occupiedCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Cannot Delete Room', style: AppTheme.getFontStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Text('Room ${room.roomNumber} has active student allocations. Please vacate them first.', style: AppTheme.getFontStyle()),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Room ${room.roomNumber}?', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this room permanently?', style: AppTheme.getFontStyle()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              context.read<HostelBloc>().add(DeleteRoomEvent(room.id));
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }

  // LEVEL 3: Beds Management Dialog
  void _showBedsManagementDialog(HostelRoom room) {
    final bedNumberController = TextEditingController();
    final bedRepo = HostelRepository(ApiClient());
    List<HostelBed> bedsList = [];
    bool isDialogLoading = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          Future<void> fetchBeds() async {
            try {
              final beds = await bedRepo.getBeds(room.id);
              setDialogState(() {
                bedsList = beds;
                isDialogLoading = false;
              });
            } catch (e) {
              setDialogState(() => isDialogLoading = false);
            }
          }

          if (isDialogLoading) {
            fetchBeds();
          }

          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Beds in Room ${room.roomNumber}', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _refreshData();
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            content: Container(
              constraints: const BoxConstraints(maxWidth: 500, maxHeight: 450),
              child: isDialogLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Add Bed Form
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: bedNumberController,
                                decoration: InputDecoration(
                                  labelText: context.tr('new_bed_number_eg'),
                                  isDense: true,
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: () async {
                                final bedNum = bedNumberController.text.trim();
                                if (bedNum.isNotEmpty) {
                                  try {
                                    setDialogState(() => isDialogLoading = true);
                                    await bedRepo.createBed(roomId: room.id, bedNumber: bedNum);
                                    bedNumberController.clear();
                                    fetchBeds();
                                  } catch (e) {
                                    setDialogState(() => isDialogLoading = false);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text(e.toString(), style: AppTheme.getFontStyle(color: Colors.white)),
                                        backgroundColor: Colors.redAccent));
                                  }
                                }
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: Text(context.tr('add_bed')),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Configured Beds (${bedsList.length})',
                          style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: bedsList.isEmpty
                              ? Center(
                                  child: Text(
                                    'No beds configured in this room yet.',
                                    style: AppTheme.getFontStyle(color: Colors.grey),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: bedsList.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (ctx2, idx) {
                                    final bed = bedsList[idx];
                                    final occupied = bed.isOccupied == 1;

                                    return ListTile(
                                      dense: true,
                                      leading: Icon(
                                        Icons.single_bed_rounded,
                                        color: occupied ? Colors.purple : Colors.green,
                                        size: 24,
                                      ),
                                      title: Text(
                                        bed.bedNumber,
                                        style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        occupied
                                            ? 'Occupied by: ${bed.studentName ?? "N/A"} (${bed.studentGrNo ?? ""})'
                                            : 'Vacant',
                                        style: AppTheme.getFontStyle(
                                            fontSize: 11, color: occupied ? Colors.purple.shade700 : Colors.green.shade700),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                        onPressed: () async {
                                          if (occupied) {
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                              content: Text('Cannot delete occupied bed.',
                                                  style: AppTheme.getFontStyle(color: Colors.white)),
                                              backgroundColor: Colors.redAccent,
                                            ));
                                            return;
                                          }
                                          try {
                                            setDialogState(() => isDialogLoading = true);
                                            await bedRepo.deleteBed(bed.id);
                                            fetchBeds();
                                          } catch (e) {
                                            setDialogState(() => isDialogLoading = false);
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                              content: Text('Failed to delete: $e', style: AppTheme.getFontStyle(color: Colors.white)),
                                              backgroundColor: Colors.redAccent,
                                            ));
                                          }
                                        },
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  _refreshData();
                  Navigator.pop(ctx);
                },
                child: Text(context.tr('close')),
              ),
            ],
          );
        });
      },
    );
  }

  void _showAllocateRoomDialog(List<HostelRoom> rooms) {
    final hostelBloc = context.read<HostelBloc>();
    final dateController = TextEditingController(text: DateTime.now().toIso8601String().split('T')[0]);
    final studentSearchController = TextEditingController();
    final minAgeController = TextEditingController();
    final maxAgeController = TextEditingController();
    final studentSearchRepo = StudentRepository(ApiClient());

    HostelRoom? selectedRoom;
    final List<Student> selectedStudents = [];
    List<Student> searchResults = [];
    bool isSearching = false;

    final availableRooms = rooms.where((r) => r.vacantCount > 0).toList();

    if (availableRooms.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Beds Unavailable', style: AppTheme.getFontStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Text('No rooms have vacant beds currently. Please increase room capacities or vacate students.', style: AppTheme.getFontStyle()),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    selectedRoom = availableRooms.first;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final int vacantBeds = selectedRoom?.vacantCount ?? 0;
            final int selectedCount = selectedStudents.length;
            final bool isOverCapacity = selectedCount > vacantBeds;
            final double capacityPercent = vacantBeds > 0 ? (selectedCount / vacantBeds).clamp(0.0, 1.0) : 0.0;

            Future<void> doSearch() async {
              final query = studentSearchController.text.trim();
              final minAgeStr = minAgeController.text.trim();
              final maxAgeStr = maxAgeController.text.trim();

              if (query.length < 2 && minAgeStr.isEmpty && maxAgeStr.isEmpty) {
                setDialogState(() {
                  searchResults = [];
                  isSearching = false;
                });
                return;
              }

              setDialogState(() => isSearching = true);
              try {
                final minAge = int.tryParse(minAgeStr);
                final maxAge = int.tryParse(maxAgeStr);
                final results = await studentSearchRepo.searchStudents(
                  query,
                  minAge: minAge,
                  maxAge: maxAge,
                  excludeAllocated: true,
                );
                // Exclude already selected students from results
                final selectedIds = selectedStudents.map((s) => s.id).toSet();
                setDialogState(() {
                  searchResults = results.where((s) => !selectedIds.contains(s.id)).toList();
                  isSearching = false;
                });
              } catch (e) {
                setDialogState(() {
                  searchResults = [];
                  isSearching = false;
                });
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── HEADER ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.primaryColor, AppTheme.primaryColor.withAlpha(200)],
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(30),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Bulk Room Allocation',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Add multiple students to a hostel room at once',
                                  style: AppTheme.getFontStyle(fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),

                    // ── BODY ────────────────────────────────
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Room & Date Row
                            context.isMobile
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      DropdownButtonFormField<HostelRoom>(
                                        value: selectedRoom,
                                        decoration: const InputDecoration(
                                          labelText: 'Select Room',
                                          prefixIcon: Icon(Icons.meeting_room_rounded),
                                          isDense: true,
                                        ),
                                        isExpanded: true,
                                        items: availableRooms.map((r) {
                                          return DropdownMenuItem(
                                            value: r,
                                            child: Text(
                                              '${r.hostelName ?? "Hostel"} - Room ${r.roomNumber}  •  ${r.vacantCount} beds vacant',
                                              style: AppTheme.getFontStyle(fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) setDialogState(() => selectedRoom = val);
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: dateController,
                                        decoration: InputDecoration(
                                          labelText: context.tr('allocation_date'),
                                          suffixIcon: Icon(Icons.calendar_today_rounded),
                                          isDense: true,
                                        ),
                                        readOnly: true,
                                        onTap: () async {
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: DateTime.now(),
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime(2030),
                                          );
                                          if (picked != null) {
                                            dateController.text = picked.toIso8601String().split('T')[0];
                                          }
                                        },
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: DropdownButtonFormField<HostelRoom>(
                                          value: selectedRoom,
                                          decoration: const InputDecoration(
                                            labelText: 'Select Room',
                                            prefixIcon: Icon(Icons.meeting_room_rounded),
                                            isDense: true,
                                          ),
                                          items: availableRooms.map((r) {
                                            return DropdownMenuItem(
                                              value: r,
                                              child: Text(
                                                '${r.hostelName ?? "Hostel"} - Room ${r.roomNumber}  •  ${r.vacantCount} beds vacant',
                                                style: AppTheme.getFontStyle(fontSize: 13),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) setDialogState(() => selectedRoom = val);
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: dateController,
                                          decoration: InputDecoration(
                                            labelText: context.tr('allocation_date'),
                                            suffixIcon: Icon(Icons.calendar_today_rounded),
                                            isDense: true,
                                          ),
                                          readOnly: true,
                                          onTap: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: DateTime.now(),
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime(2030),
                                            );
                                            if (picked != null) {
                                              dateController.text = picked.toIso8601String().split('T')[0];
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: 20),

                            // ── AGE RANGE FILTER ───────────────
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue.withAlpha(12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.blue.withAlpha(40)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.filter_alt_rounded, size: 18, color: Colors.blue.shade700),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Age Range Filter',
                                        style: AppTheme.getFontStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        'Set age to filter students in search',
                                        style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: minAgeController,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: context.tr('min_age_years'),
                                            hintText: 'e.g. 10',
                                            isDense: true,
                                            prefixIcon: const Icon(Icons.arrow_downward_rounded, size: 18),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          onChanged: (val) => doSearch(),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Text('to', style: AppTheme.getFontStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        child: TextFormField(
                                          controller: maxAgeController,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: context.tr('max_age_years'),
                                            hintText: 'e.g. 20',
                                            isDense: true,
                                            prefixIcon: const Icon(Icons.arrow_upward_rounded, size: 18),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          onChanged: (val) => doSearch(),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      FilledButton.tonalIcon(
                                        onPressed: () => doSearch(),
                                        icon: const Icon(Icons.refresh_rounded, size: 18),
                                        label: Text(context.tr('apply')),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ── STUDENT SEARCH ─────────────────
                            TextFormField(
                              controller: studentSearchController,
                              decoration: InputDecoration(
                                labelText: 'Search Students (Name or GR No)',
                                prefixIcon: const Icon(Icons.person_search_rounded),
                                suffixIcon: isSearching
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                      )
                                    : studentSearchController.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear_rounded),
                                            onPressed: () {
                                              studentSearchController.clear();
                                              setDialogState(() => searchResults = []);
                                            },
                                          )
                                        : null,
                                isDense: true,
                                hintText: 'Type search text or use age filter above',
                              ),
                              style: AppTheme.getFontStyle(fontSize: 13),
                              onFieldSubmitted: (_) => doSearch(),
                              onChanged: (val) {
                                if (val.length >= 2 ||
                                    minAgeController.text.trim().isNotEmpty ||
                                    maxAgeController.text.trim().isNotEmpty) {
                                  doSearch();
                                } else if (val.isEmpty) {
                                  setDialogState(() => searchResults = []);
                                }
                              },
                            ),

                            // ── SEARCH RESULTS ─────────────────
                            if (searchResults.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                constraints: const BoxConstraints(maxHeight: 180),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E2E) : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade300),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(12),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: searchResults.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                                  itemBuilder: (ctx2, idx) {
                                    final student = searchResults[idx];
                                    // Calculate age display
                                    String ageStr = '';
                                    if (student.dateOfBirth != null && student.dateOfBirth!.isNotEmpty) {
                                      final dob = DateTime.tryParse(student.dateOfBirth!);
                                      if (dob != null) {
                                        final age = DateTime.now().difference(dob).inDays ~/ 365;
                                        ageStr = '${age}y';
                                      }
                                    }
                                    return ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: AppTheme.primaryColor.withAlpha(30),
                                        child: Text(
                                          student.fullName.isNotEmpty ? student.fullName[0].toUpperCase() : '?',
                                          style: AppTheme.getFontStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryColor,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        student.fullName,
                                        style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text(
                                        'Village: ${student.village ?? "N/A"}  •  ${student.className ?? "No Class"}${ageStr.isNotEmpty ? "  •  $ageStr" : ""}',
                                        style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey.shade500),
                                      ),
                                      trailing: Icon(Icons.add_circle_rounded, color: AppTheme.primaryColor, size: 22),
                                      onTap: () {
                                        if (!selectedStudents.any((s) => s.id == student.id)) {
                                          setDialogState(() {
                                            selectedStudents.add(student);
                                            searchResults.removeWhere((s) => s.id == student.id);
                                          });
                                        }
                                      },
                                    );
                                  },
                                ),
                              )
                            else if (studentSearchController.text.trim().isNotEmpty ||
                                minAgeController.text.trim().isNotEmpty ||
                                maxAgeController.text.trim().isNotEmpty)
                              if (!isSearching)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withAlpha(20),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.orange.withAlpha(50)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'No active, unallocated students found matching the criteria.',
                                            style: AppTheme.getFontStyle(color: Colors.orange.shade800, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                            const SizedBox(height: 20),

                            // ── SELECTED STUDENTS CHIPS ────────
                            Row(
                              children: [
                                Icon(Icons.people_rounded, size: 18, color: AppTheme.primaryColor),
                                const SizedBox(width: 8),
                                Text(
                                  'Selected Students',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isOverCapacity ? Colors.redAccent.withAlpha(30) : AppTheme.primaryColor.withAlpha(25),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$selectedCount / $vacantBeds beds',
                                    style: AppTheme.getFontStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isOverCapacity ? Colors.redAccent : AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (selectedStudents.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () => setDialogState(() => selectedStudents.clear()),
                                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                                    label: Text(context.tr('clear_all')),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.redAccent,
                                      textStyle: AppTheme.getFontStyle(fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Capacity progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: capacityPercent,
                                minHeight: 6,
                                backgroundColor: Colors.grey.shade200,
                                color: isOverCapacity
                                    ? Colors.redAccent
                                    : capacityPercent > 0.75 ? Colors.orange : AppTheme.primaryColor,
                              ),
                            ),
                            if (isOverCapacity)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.redAccent),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Capacity exceeded! Remove ${selectedCount - vacantBeds} student(s) or change room.',
                                      style:
                                          AppTheme.getFontStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 10),

                            if (selectedStudents.isEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 24),
                                alignment: Alignment.center,
                                child: Column(
                                  children: [
                                    Icon(Icons.person_add_alt_rounded, size: 36, color: Colors.grey.shade300),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No students selected yet.\nSearch above and tap a student to add them.',
                                      textAlign: TextAlign.center,
                                      style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade400),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: selectedStudents.map((student) {
                                  String ageStr = '';
                                  if (student.dateOfBirth != null && student.dateOfBirth!.isNotEmpty) {
                                    final dob = DateTime.tryParse(student.dateOfBirth!);
                                    if (dob != null) {
                                      final age = DateTime.now().difference(dob).inDays ~/ 365;
                                      ageStr = ' • ${age}y';
                                    }
                                  }
                                  return Chip(
                                    avatar: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: AppTheme.primaryColor,
                                      child: Text(
                                        student.fullName.isNotEmpty ? student.fullName[0].toUpperCase() : '?',
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    label: Text(
                                      '${student.fullName} (GR: ${student.grNo ?? "N/A"}$ageStr)',
                                      style: AppTheme.getFontStyle(fontSize: 12),
                                    ),
                                    deleteIcon: const Icon(Icons.cancel_rounded, size: 18),
                                    onDeleted: () {
                                      setDialogState(() {
                                        selectedStudents.removeWhere((s) => s.id == student.id);
                                      });
                                    },
                                    backgroundColor: AppTheme.primaryColor.withAlpha(18),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(color: AppTheme.primaryColor.withAlpha(60)),
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // ── FOOTER ACTIONS ──────────────────────
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF151522) : Colors.grey.shade50,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                        border: Border(top: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Row(
                        children: [
                          if (selectedStudents.isNotEmpty)
                            Text(
                              '${selectedStudents.length} student${selectedStudents.length > 1 ? "s" : ""} will be allocated to Room ${selectedRoom?.roomNumber ?? ""}',
                              style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(context.tr('cancel')),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: (selectedStudents.isEmpty || isOverCapacity || selectedRoom == null)
                                ? null
                                : () {
                                    final studentIds = selectedStudents.map((s) => s.id).toList();
                                    hostelBloc.add(
                                      BulkAllocateRoomEvent(
                                        roomId: selectedRoom!.id,
                                        studentIds: studentIds,
                                        allocationDate: dateController.text.trim(),
                                      ),
                                    );
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(this.context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${studentIds.length} student(s) allocated to Room ${selectedRoom!.roomNumber}',
                                          style: AppTheme.getFontStyle(color: Colors.white),
                                        ),
                                        backgroundColor: AppTheme.primaryColor,
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.check_circle_rounded),
                            label: Text('Allocate ${selectedStudents.length} Student${selectedStudents.length != 1 ? "s" : ""}'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
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

  void _showVacateStayDialog(HostelAllocation alloc) {
    final formKey = GlobalKey<FormState>();
    final dateController = TextEditingController(text: DateTime.now().toIso8601String().split('T')[0]);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Vacate Student Stay', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to vacate ${alloc.studentName} from Room ${alloc.roomNumber} - ${alloc.bedNumber}?',
                  style: AppTheme.getFontStyle(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: dateController,
                  decoration: const InputDecoration(
                    labelText: 'Vacating Date',
                    suffixIcon: Icon(Icons.calendar_today_rounded),
                    isDense: true,
                  ),
                  readOnly: true,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      dateController.text = picked.toIso8601String().split('T')[0];
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
            FilledButton(
              onPressed: () {
                context.read<HostelBloc>().add(
                      VacateRoomEvent(id: alloc.id, vacateDate: dateController.text.trim()),
                    );
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
              child: Text(context.tr('vacate_now')),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteAllocation(String allocationId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Allocation Log?', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this stay record history entry?', style: AppTheme.getFontStyle()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            onPressed: () {
              context.read<HostelBloc>().add(DeleteAllocationEvent(allocationId));
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }
}

// ─── PREMIUM MINI STAT CARD ──────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E1E2E), const Color(0xFF1A1A2A), color.withAlpha(12)]
              : [Colors.white, color.withAlpha(8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withAlpha(80) : color.withAlpha(15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: isDark ? color.withAlpha(12) : color.withAlpha(5),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: isDark ? color.withAlpha(38) : color.withAlpha(30),
          width: 1.2,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withAlpha(15),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: AppTheme.getFontStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: AppTheme.getFontStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
