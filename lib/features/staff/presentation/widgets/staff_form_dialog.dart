import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../../core/network/api_client.dart';

import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/utils/hijri_cubit.dart';
import '../../../../core/utils/platform_utils.dart';
import '../../data/models/staff_model.dart';
import '../bloc/staff_bloc.dart';
import '../../../../core/services/pincode_settings.dart';
import '../../../../core/services/student_form_options_settings.dart';
import '../../../../core/services/student_status_settings.dart';
import '../../../../shared/widgets/dribbble_date_picker.dart';

// ── Default Staff Types (fallback) ─────────────────────────────────────────
const List<String> kDefaultStaffTypes = [
  'Teacher',
  'Bavarchi',
  'Nazim-e-Matbakh',
  'Accountant',
  'Worker',
  'Office Staff',
  'Other',
];

const List<String> kDefaultQualifications = [
  'Matric',
  'Intermediate',
  'Bachelor',
  'Master',
  'PhD',
  'Hafiz',
  'Alim',
  'Fazil',
  'Other',
];

class StaffFormDialog extends StatefulWidget {
  final StaffMember? staff;
  const StaffFormDialog({super.key, this.staff});

  @override
  State<StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isFetchingPinCode = false;

  // Controllers
  late TextEditingController _staffNoCtrl;
  late TextEditingController _fullNameCtrl;
  late TextEditingController _fatherNameCtrl;
  late TextEditingController _surnameCtrl;
  late TextEditingController _dobCtrl;
  late TextEditingController _qualificationCtrl;
  late TextEditingController _experienceCtrl;
  late TextEditingController _joiningDateCtrl;
  late TextEditingController _joiningDateHCtrl;
  late TextEditingController _salaryCtrl;
  late TextEditingController _mobileCtrl;
  late TextEditingController _aadhaarCtrl;
  late TextEditingController _pinCodeCtrl;
  late TextEditingController _villageCtrl;
  late TextEditingController _talukaCtrl;
  late TextEditingController _districtCtrl;
  late TextEditingController _stateCtrl;
  late TextEditingController _emergencyCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _noteCtrl;

  String? _selectedStaffType;
  String? _selectedGender;
  String _selectedStatus = 'Active';
  bool _isActive = true;

  // Village auto-fill
  List<String> _pinCodeVillages = [];
  List<String> _villageSuggestions = [];
  bool _showVillageDropdown = false;
  bool _ignoreVillageListener = false;
  String? _photoPath;
  bool _isUploadingPhoto = false;
  double _scale = 1.0;

  // Dynamic staff types & qualifications & genders & statuses
  List<String> _staffTypes = List.from(kDefaultStaffTypes);
  List<String> _qualifications = List.from(kDefaultQualifications);
  List<String> _genders = ['Male', 'Female', 'Other'];
  List<String> _statuses = List.from(StudentStatusSettings.defaultStatuses);

  @override
  void initState() {
    super.initState();
    final s = widget.staff;
    _staffNoCtrl = TextEditingController(text: s?.staffNo ?? '');
    _fullNameCtrl = TextEditingController(text: s?.fullName ?? '');
    _fatherNameCtrl = TextEditingController(text: s?.fatherName ?? '');
    _surnameCtrl = TextEditingController(text: s?.surname ?? '');
    _dobCtrl = TextEditingController(text: s?.dateOfBirth ?? '');
    _qualificationCtrl = TextEditingController(text: s?.qualification ?? '');
    _experienceCtrl = TextEditingController(
        text: s != null ? s.experienceYears.toString() : '0');
    _joiningDateCtrl = TextEditingController(text: s?.joiningDate ?? '');
    _joiningDateHCtrl = TextEditingController(text: s?.joiningDateH ?? '');
    _salaryCtrl =
        TextEditingController(text: s != null ? s.salary.toString() : '');
    _mobileCtrl = TextEditingController(text: s?.mobileNo ?? '');
    _aadhaarCtrl = TextEditingController(text: s?.aadhaarNo ?? '');
    _pinCodeCtrl = TextEditingController(text: s?.pinCode ?? '');
    _villageCtrl = TextEditingController(text: s?.village ?? '');
    _talukaCtrl = TextEditingController(text: s?.taluka ?? '');
    _districtCtrl = TextEditingController(text: s?.district ?? '');
    _stateCtrl = TextEditingController(text: s?.state ?? '');
    _emergencyCtrl = TextEditingController(text: s?.emergencyContact ?? '');
    _addressCtrl = TextEditingController(text: s?.address ?? '');
    _noteCtrl = TextEditingController(text: s?.note ?? '');

    _selectedStaffType = s?.staffType ?? 'Teacher';
    _selectedGender = s?.gender;
    _isActive = s?.isActive ?? true;
    _selectedStatus = _isActive ? 'Active' : 'Inactive';
    _photoPath = s?.photoPath;

    // Load next staff no if new
    if (s == null) _loadNextStaffNo();

    // Set today's joining date if new
    if (s == null) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _joiningDateCtrl.text = today;
      _updateHijriForJoining(today);
    }

    // Village listener
    _villageCtrl.addListener(_onVillageChanged);

    // Load dynamic staff types & qualifications from API, and genders & statuses from students settings
    _loadStaffTypes();
  }

  Future<void> _loadStaffTypes() async {
    try {
      final resp = await ApiClient().get('/staff/types');
      final dynamic raw = resp.data;
      List types = [];
      if (raw is List) {
        types = raw;
      } else if (raw is Map && raw['data'] is List) {
        types = raw['data'];
      }
      if (mounted && types.isNotEmpty) {
        setState(() {
          _staffTypes = types
              .map((t) => (t is Map ? t['name'] : t.toString()).toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (_selectedStaffType != null && !_staffTypes.contains(_selectedStaffType)) {
            _staffTypes.add(_selectedStaffType!);
          }
        });
      }
    } catch (_) {}

    // Also load qualifications
    try {
      final resp = await ApiClient().get('/staff/qualifications');
      final dynamic raw = resp.data;
      List quals = [];
      if (raw is List) {
        quals = raw;
      } else if (raw is Map && raw['data'] is List) {
        quals = raw['data'];
      }
      if (mounted && quals.isNotEmpty) {
        setState(() {
          _qualifications = quals
              .map((q) => (q is Map ? q['name'] : q.toString()).toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
          final current = _qualificationCtrl.text.trim();
          if (current.isNotEmpty && !_qualifications.contains(current)) {
            _qualifications.add(current);
          }
        });
      }
    } catch (_) {}

    // Also load genders from StudentFormOptionsSettings
    try {
      final loadedGenders = await StudentFormOptionsSettings.getGenders();
      if (mounted && loadedGenders.isNotEmpty) {
        setState(() {
          _genders = List.from(loadedGenders);
          if (_selectedGender != null && !_genders.contains(_selectedGender)) {
            _genders.add(_selectedGender!);
          }
        });
      }
    } catch (_) {}

    // Also load statuses from StudentStatusSettings
    try {
      final loadedStatuses = await StudentStatusSettings.getStatuses();
      if (mounted && loadedStatuses.isNotEmpty) {
        setState(() {
          _statuses = List.from(loadedStatuses);
          if (!_statuses.contains(_selectedStatus)) {
            _statuses.insert(0, _selectedStatus);
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _villageCtrl.removeListener(_onVillageChanged);
    for (final c in [
      _staffNoCtrl, _fullNameCtrl, _fatherNameCtrl, _surnameCtrl, _dobCtrl,
      _qualificationCtrl, _experienceCtrl, _joiningDateCtrl, _joiningDateHCtrl,
      _salaryCtrl, _mobileCtrl, _aadhaarCtrl, _pinCodeCtrl, _villageCtrl,
      _talukaCtrl, _districtCtrl, _stateCtrl, _emergencyCtrl, _addressCtrl,
      _noteCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadNextStaffNo() async {
    try {
      final resp = await ApiClient().get('/staff/next-no');
      if (mounted && resp.data != null) {
        final staffNo = resp.data['staff_no'] ?? resp.data['next_no'] ?? 'S-0001';
        setState(() => _staffNoCtrl.text = staffNo.toString());
      }
    } catch (_) {
      if (mounted) setState(() => _staffNoCtrl.text = 'S-0001');
    }
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  Future<void> _fetchPinCodeDetails(String pinCode) async {
    if (pinCode.length != 6) return;
    setState(() => _isFetchingPinCode = true);
    
    bool fetched = false;
    final provider = await PincodeSettings.getProvider();

    // 1. Custom Provider Fetch
    if (provider == 'custom') {
      try {
        final customUrlPattern = await PincodeSettings.getCustomUrl();
        if (customUrlPattern.isNotEmpty) {
          final apiKey = await PincodeSettings.getApiKey();
          final url = customUrlPattern
              .replaceAll('{pincode}', pinCode)
              .replaceAll('{apiKey}', apiKey);

          debugPrint('Pincode custom fetch URL: $url');
          final res = await Dio().get(url);
          if (res.statusCode == 200 && res.data != null) {
            final jsonPayload = res.data;

            final mapTalukaKey = await PincodeSettings.getMapTaluka();
            final mapDistrictKey = await PincodeSettings.getMapDistrict();
            final mapStateKey = await PincodeSettings.getMapState();
            final mapVillageKey = await PincodeSettings.getMapVillage();

            final rawTaluka = PincodeSettings.findKeyInJson(jsonPayload, mapTalukaKey);
            final rawDistrict = PincodeSettings.findKeyInJson(jsonPayload, mapDistrictKey);
            final rawState = PincodeSettings.findKeyInJson(jsonPayload, mapStateKey);
            final rawVillages = PincodeSettings.extractVillages(jsonPayload, mapVillageKey);

            String talukaVal = rawTaluka != null ? _toTitleCase(rawTaluka.toString()) : '';
            String districtVal = rawDistrict != null ? _toTitleCase(rawDistrict.toString()) : '';
            String stateVal = rawState != null ? _toTitleCase(rawState.toString()) : '';
            final villages = rawVillages.map((v) {
              final clean = v.replaceAll(RegExp(r'\s+(H\.O|B\.O|S\.O|C\.O|R\.S|E\.O)$', caseSensitive: false), '').trim();
              return _toTitleCase(clean);
            }).toSet().toList()..sort();

            _ignoreVillageListener = true;
            setState(() {
              _pinCodeVillages = villages;
              if (talukaVal.isNotEmpty && talukaVal.toUpperCase() != 'NA') {
                _talukaCtrl.text = talukaVal;
              }
              if (districtVal.isNotEmpty && districtVal.toUpperCase() != 'NA') {
                _districtCtrl.text = districtVal;
              }
              if (stateVal.isNotEmpty && stateVal.toUpperCase() != 'NA') {
                _stateCtrl.text = stateVal;
              }
              if (villages.isNotEmpty) {
                _villageCtrl.text = villages[0];
                _villageSuggestions = villages;
                _showVillageDropdown = villages.length > 1;
              }
            });
            _ignoreVillageListener = false;
            fetched = true;
          }
        }
      } catch (e) {
        debugPrint('Custom Pincode API call failed: $e');
      }
    }

    // 2. Try Official data.gov.in API with user's API Key
    if (!fetched && provider == 'datagov') {
      try {
        final apiKey = await PincodeSettings.getApiKey();
        const resourceId = '6176ee09-3d56-4a3b-8115-21841576b2f6';
        final url = 'https://api.data.gov.in/resource/$resourceId?api-key=$apiKey&format=json&limit=50&filters[pincode]=$pinCode';
        
        debugPrint('Pincode datagov fetch URL: $url');
        final res = await Dio().get(url);
        if (res.statusCode == 200 && res.data != null && res.data['records'] != null) {
          final List records = res.data['records'];
          if (records.isNotEmpty) {
            final villagesSet = <String>{};
            String foundTaluk = '';
            String foundDistrict = '';
            String foundState = '';

            for (final r in records) {
              final rawOffice = r['officename']?.toString().trim() ?? '';
              if (rawOffice.isNotEmpty) {
                final cleanName = rawOffice.replaceAll(RegExp(r'\s+(H\.O|B\.O|S\.O|C\.O|R\.S|E\.O)$', caseSensitive: false), '').trim();
                villagesSet.add(_toTitleCase(cleanName));
              }

              if (foundTaluk.isEmpty) {
                final t = r['taluk']?.toString().trim();
                if (t != null && t.isNotEmpty && t.toUpperCase() != 'NA') {
                  foundTaluk = _toTitleCase(t);
                }
              }

              if (foundDistrict.isEmpty) {
                final d = r['districtname']?.toString().trim();
                if (d != null && d.isNotEmpty && d.toUpperCase() != 'NA') {
                  foundDistrict = _toTitleCase(d);
                }
              }

              if (foundState.isEmpty) {
                final st = r['statename']?.toString().trim();
                if (st != null && st.isNotEmpty && st.toUpperCase() != 'NA') {
                  foundState = _toTitleCase(st);
                }
              }
            }

            final villages = villagesSet.toList()..sort();

            _ignoreVillageListener = true;
            setState(() {
              _pinCodeVillages = villages;
              if (foundTaluk.isNotEmpty) _talukaCtrl.text = foundTaluk;
              if (foundDistrict.isNotEmpty) _districtCtrl.text = foundDistrict;
              if (foundState.isNotEmpty) _stateCtrl.text = foundState;

              if (villages.isNotEmpty) {
                _villageCtrl.text = villages[0];
                _villageSuggestions = villages;
                _showVillageDropdown = villages.length > 1;
              }
            });
            _ignoreVillageListener = false;
            fetched = true;
          }
        }
      } catch (e) {
        debugPrint('data.gov.in Pincode API call failed: $e');
      }
    }

    // 3. Fallback to postalpincode.in API if provider is postalpincode OR datagov using default key
    final apiKey = await PincodeSettings.getApiKey();
    final isDefaultKey = apiKey == PincodeSettings.defaultApiKey;
    if (!fetched && (provider == 'postalpincode' || (provider == 'datagov' && isDefaultKey))) {
      try {
        debugPrint('Pincode fallback/postalpincode fetch...');
        final res = await Dio().get('https://api.postalpincode.in/pincode/$pinCode');
        final List records = res.data;
        if (records.isNotEmpty && records[0]['Status'] == 'Success') {
          final postOffices = records[0]['PostOffice'] as List;
          if (postOffices.isNotEmpty) {
            final first = postOffices[0];
            final villages = postOffices.map((p) => p['Name'] as String).toSet().toList()..sort();

            _ignoreVillageListener = true;
            setState(() {
              _pinCodeVillages = villages;
              final rawTaluk = first['Taluk']?.toString().trim();
              final rawBlock = first['Block']?.toString().trim();
              String talukaVal = '';
              if (rawBlock != null && rawBlock.isNotEmpty && rawBlock.toUpperCase() != 'NA') {
                talukaVal = rawBlock;
              } else if (rawTaluk != null && rawTaluk.isNotEmpty && rawTaluk.toUpperCase() != 'NA') {
                talukaVal = rawTaluk;
              }
              _talukaCtrl.text = talukaVal;
              _districtCtrl.text = first['District'] ?? '';
              _stateCtrl.text = first['State'] ?? '';
              if (villages.isNotEmpty) {
                _villageCtrl.text = villages[0];
                _villageSuggestions = villages;
                _showVillageDropdown = villages.length > 1;
              }
            });
            _ignoreVillageListener = false;
          }
        }
      } catch (e) {
        debugPrint('Fallback Pincode API call failed: $e');
      }
    }

    if (mounted) setState(() => _isFetchingPinCode = false);
  }

  void _onVillageChanged() {
    if (_ignoreVillageListener) return;
    final text = _villageCtrl.text;
    if (_pinCodeVillages.isEmpty) {
      setState(() {
        _villageSuggestions = [];
        _showVillageDropdown = false;
      });
      return;
    }
    if (text.isEmpty) {
      setState(() {
        _villageSuggestions = _pinCodeVillages;
        _showVillageDropdown = true;
      });
      return;
    }
    final filtered = _pinCodeVillages
        .where((v) => v.toLowerCase().contains(text.toLowerCase()))
        .toList();
    setState(() {
      _villageSuggestions = filtered;
      _showVillageDropdown = filtered.isNotEmpty;
    });
  }

  void _selectVillage(String village) {
    _ignoreVillageListener = true;
    setState(() {
      _villageCtrl.text = village;
      _showVillageDropdown = false;
    });
    _ignoreVillageListener = false;
  }

  // ── Hijri date ─────────────────────────────────────────────────────────────
  void _updateHijriForJoining(String dateStr) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(dateStr);
      final adj = context.read<HijriCubit>().state.adjustment;
      final hijri = HijriCalendar.fromDate(date.add(Duration(days: adj)));
      _joiningDateHCtrl.text =
          '${hijri.hDay}-${hijri.hMonth}-${hijri.hYear} AH';
    } catch (_) {}
  }

  // ── Date pickers ───────────────────────────────────────────────────────────
  Future<void> _pickDob() async {
    DateTime initial = DateTime.now().subtract(const Duration(days: 365 * 25));
    if (_dobCtrl.text.isNotEmpty) {
      final parsed = DateTime.tryParse(_dobCtrl.text.trim());
      if (parsed != null) initial = parsed;
    }
    final d = await DribbbleDatePickerDialog.show(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      title: 'Date of Birth',
    );
    if (d != null) {
      _dobCtrl.text = DateFormat('yyyy-MM-dd').format(d);
    }
  }

  Future<void> _pickJoiningDate() async {
    DateTime initial = DateTime.now();
    if (_joiningDateCtrl.text.isNotEmpty) {
      final parsed = DateTime.tryParse(_joiningDateCtrl.text.trim());
      if (parsed != null) initial = parsed;
    }
    final d = await DribbbleDatePickerDialog.show(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      title: 'Joining Date',
    );
    if (d != null) {
      final str = DateFormat('yyyy-MM-dd').format(d);
      _joiningDateCtrl.text = str;
      _updateHijriForJoining(str);
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _pickAndUploadPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _isUploadingPhoto = true;
        });

        final filePath = result.files.single.path!;
        final fileName = result.files.single.name;

        final formData = FormData.fromMap({
          'photo': await MultipartFile.fromFile(filePath, filename: fileName),
        });

        final response = await ApiClient().post('/upload-photo', data: formData);
        
        if (!mounted) return;

        if (response.statusCode == 200 && response.data != null) {
          setState(() {
            _photoPath = response.data['photo_path'];
            _isUploadingPhoto = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('photo_uploaded_success'))),
          );
        } else {
          throw Exception('Failed to upload photo');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading photo: $e')),
      );
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final data = {
      'staff_no': _staffNoCtrl.text.trim(),
      'full_name': _fullNameCtrl.text.trim(),
      'father_name': _fatherNameCtrl.text.trim(),
      'surname': _surnameCtrl.text.trim(),
      'date_of_birth': _dobCtrl.text.trim(),
      'gender': _selectedGender,
      'staff_type': _selectedStaffType,
      'qualification': _qualificationCtrl.text.trim(),
      'experience_years': int.tryParse(_experienceCtrl.text) ?? 0,
      'joining_date': _joiningDateCtrl.text.trim(),
      'joining_date_h': _joiningDateHCtrl.text.trim(),
      'salary': double.tryParse(_salaryCtrl.text) ?? 0,
      'mobile_no': _mobileCtrl.text.trim(),
      'aadhaar_no': _aadhaarCtrl.text.trim(),
      'village': _villageCtrl.text.trim(),
      'taluka': _talukaCtrl.text.trim(),
      'district': _districtCtrl.text.trim(),
      'state': _stateCtrl.text.trim(),
      'pin_code': _pinCodeCtrl.text.trim(),
      'emergency_contact': _emergencyCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'is_active': (_selectedStatus.toLowerCase() == 'active' ||
          _selectedStatus.toLowerCase() == 'chalu' ||
          _selectedStatus.toLowerCase() == 'regular'),
      'note': _noteCtrl.text.trim(),
      'photo_path': _photoPath,
    };

    final bloc = context.read<StaffBloc>();
    if (widget.staff == null) {
      bloc.add(AddStaff(data));
    } else {
      bloc.add(UpdateStaff(widget.staff!.id, data));
    }

    Navigator.pop(context);
  }

  Widget _buildPhotoUploader(bool isDark, bool isCompact) {
    return GestureDetector(
      onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
      child: Stack(
        children: [
          Container(
            width: isCompact ? (100 * _scale) : 120,
            height: isCompact ? (136 * _scale) : 140,
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.white10 
                  : (isCompact ? Colors.black.withOpacity(0.02) : Colors.black.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(isCompact ? (12 * _scale) : 16),
              border: Border.all(
                color: isDark ? Colors.white24 : (isCompact ? Colors.grey.shade300 : Colors.black12),
                width: isCompact ? (1.5 * _scale) : 2,
              ),
              image: _photoPath != null
                  ? DecorationImage(
                      image: NetworkImage(
                        '${ApiConstants.baseUrl.replaceAll("/api", "")}$_photoPath',
                      ),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _photoPath == null
                ? Center(
                    child: _isUploadingPhoto
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isCompact ? Icons.add_rounded : Icons.add_a_photo_rounded,
                                size: isCompact ? (24 * _scale) : 32,
                                color: isCompact ? AppTheme.primaryColor : (isDark ? Colors.white70 : Colors.black54),
                              ),
                              SizedBox(height: isCompact ? (6 * _scale) : 8),
                              Text(
                                context.tr('upload_photo'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: isCompact ? (10 * _scale) : 12,
                                  fontWeight: isCompact ? FontWeight.w600 : FontWeight.normal,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                  )
                : null,
          ),
          if (_photoPath != null)
            Positioned(
              bottom: 4 * _scale,
              right: 4 * _scale,
              child: Container(
                padding: EdgeInsets.all(4 * _scale),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.edit,
                  size: 14 * _scale,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.staff != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocListener<StaffBloc, StaffState>(
      listener: (context, state) {
        if (state is StaffOperationSuccess || state is StaffError) {
          setState(() => _isLoading = false);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dialogWidth = constraints.maxWidth;
          final isCompact = dialogWidth < 650;
          _scale = isCompact ? (dialogWidth / 375.0).clamp(0.75, 1.0) : 1.0;

          final formContent = Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section 1 — Basic Info
                            _sectionTitle(context.tr('personal_information'), Icons.person_rounded, isDark),
                            const SizedBox(height: 14),
                            isCompact
                                ? Column(
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildPhotoUploader(isDark, true),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              children: [
                                                _buildField(
                                                  label: context.tr('staff_no_dot'),
                                                  controller: _staffNoCtrl,
                                                  icon: Icons.badge_rounded,
                                                  readOnly: true,
                                                  isDark: isDark,
                                                  isCompact: true,
                                                  flex: 1,
                                                ),
                                                const SizedBox(height: 10),
                                                _buildDropdownField(
                                                  label: context.tr('staff_type_req'),
                                                  value: _selectedStaffType,
                                                  items: _staffTypes,
                                                  icon: Icons.work_rounded,
                                                  isDark: isDark,
                                                  isCompact: true,
                                                  flex: 1,
                                                  onChanged: (v) =>
                                                      setState(() => _selectedStaffType = v),
                                                  validator: (v) =>
                                                      v == null ? 'Required' : null,
                                                ),
                                                const SizedBox(height: 10),
                                                _buildDropdownField(
                                                  label: context.tr('gender'),
                                                  value: _selectedGender,
                                                  items: _genders,
                                                  icon: Icons.wc_rounded,
                                                  isDark: isDark,
                                                  isCompact: true,
                                                  flex: 1,
                                                  onChanged: (v) =>
                                                      setState(() => _selectedGender = v),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      _buildField(
                                        label: context.tr('full_name_req'),
                                        controller: _fullNameCtrl,
                                        icon: Icons.person_outline_rounded,
                                        isDark: isDark,
                                        isCompact: true,
                                        flex: 1,
                                        validator: (v) =>
                                            (v == null || v.isEmpty) ? 'Required' : null,
                                      ),
                                      const SizedBox(height: 14),
                                      _buildField(
                                        label: context.tr('father_name'),
                                        controller: _fatherNameCtrl,
                                        icon: Icons.family_restroom_rounded,
                                        isDark: isDark,
                                        isCompact: true,
                                        flex: 1,
                                      ),
                                      const SizedBox(height: 14),
                                      _buildField(
                                        label: context.tr('surname'),
                                        controller: _surnameCtrl,
                                        icon: Icons.abc_rounded,
                                        isDark: isDark,
                                        isCompact: true,
                                        flex: 1,
                                      ),
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildPhotoUploader(isDark, false),
                                      const SizedBox(width: 20),
                                      Expanded(
                                        child: Column(
                                          children: [
                                            _buildRow(
                                              false,
                                              [
                                                _buildField(
                                                  label: context.tr('staff_no_dot'),
                                                  controller: _staffNoCtrl,
                                                  icon: Icons.badge_rounded,
                                                  readOnly: true,
                                                  isDark: isDark,
                                                  isCompact: false,
                                                  flex: 1,
                                                ),
                                                const SizedBox(width: 16),
                                                _buildDropdownField(
                                                  label: context.tr('staff_type_req'),
                                                  value: _selectedStaffType,
                                                  items: _staffTypes,
                                                  icon: Icons.work_rounded,
                                                  isDark: isDark,
                                                  isCompact: false,
                                                  flex: 2,
                                                  onChanged: (v) =>
                                                      setState(() => _selectedStaffType = v),
                                                  validator: (v) =>
                                                      v == null ? 'Required' : null,
                                                ),
                                                const SizedBox(width: 16),
                                                _buildDropdownField(
                                                  label: context.tr('gender'),
                                                  value: _selectedGender,
                                                  items: _genders,
                                                  icon: Icons.wc_rounded,
                                                  isDark: isDark,
                                                  isCompact: false,
                                                  flex: 1,
                                                  onChanged: (v) =>
                                                      setState(() => _selectedGender = v),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 14),
                                            _buildRow(
                                              false,
                                              [
                                                _buildField(
                                                  label: context.tr('full_name_req'),
                                                  controller: _fullNameCtrl,
                                                  icon: Icons.person_outline_rounded,
                                                  isDark: isDark,
                                                  isCompact: false,
                                                  flex: 2,
                                                  validator: (v) =>
                                                      (v == null || v.isEmpty) ? 'Required' : null,
                                                ),
                                                const SizedBox(width: 16),
                                                _buildField(
                                                  label: context.tr('father_name'),
                                                  controller: _fatherNameCtrl,
                                                  icon: Icons.family_restroom_rounded,
                                                  isDark: isDark,
                                                  isCompact: false,
                                                  flex: 2,
                                                ),
                                                const SizedBox(width: 16),
                                                _buildField(
                                                  label: context.tr('surname'),
                                                  controller: _surnameCtrl,
                                                  icon: Icons.abc_rounded,
                                                  isDark: isDark,
                                                  isCompact: false,
                                                  flex: 1,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: 14),
                            _buildRow(
                              isCompact,
                              [
                                _buildDateField(
                                  label: context.tr('date_of_birth'),
                                  controller: _dobCtrl,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 2,
                                  onTap: _pickDob,
                                ),
                                const SizedBox(width: 16),
                                _buildDropdownField(
                                  label: context.tr('qualification'),
                                  value: _qualificationCtrl.text.isEmpty
                                      ? null
                                      : _qualificationCtrl.text,
                                  items: _qualifications,
                                  icon: Icons.school_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 2,
                                  onChanged: (v) {
                                    setState(() => _qualificationCtrl.text = v ?? '');
                                  },
                                ),
                                const SizedBox(width: 16),
                                _buildField(
                                  label: context.tr('experience_years'),
                                  controller: _experienceCtrl,
                                  icon: Icons.timeline_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 1,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),
                            // Section 2 — Employment
                            _sectionTitle(context.tr('employment_details'), Icons.work_history_rounded, isDark),
                            const SizedBox(height: 14),
                            _buildRow(
                              isCompact,
                              [
                                _buildDateField(
                                  label: context.tr('joining_date'),
                                  controller: _joiningDateCtrl,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 2,
                                  onTap: _pickJoiningDate,
                                ),
                                const SizedBox(width: 16),
                                _buildField(
                                  label: context.tr('joining_date_hijri'),
                                  controller: _joiningDateHCtrl,
                                  icon: Icons.mosque_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 2,
                                  readOnly: true,
                                ),
                                const SizedBox(width: 16),
                                _buildField(
                                  label: context.tr('monthly_salary_inr'),
                                  controller: _salaryCtrl,
                                  icon: Icons.currency_rupee_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 2,
                                  keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*\.?\d*')),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),
                            // Section 3 — Contact
                            _sectionTitle(context.tr('contact_details'), Icons.contact_phone_rounded, isDark),
                            const SizedBox(height: 14),
                            _buildRow(
                              isCompact,
                              [
                                _buildField(
                                  label: context.tr('mobile_no_dot'),
                                  controller: _mobileCtrl,
                                  icon: Icons.phone_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 1,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  validator: (v) {
                                    if (v != null && v.isNotEmpty && v.length != 10) {
                                      return '10 digits required';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(width: 16),
                                _buildField(
                                  label: context.tr('aadhaar_no_dot'),
                                  controller: _aadhaarCtrl,
                                  icon: Icons.credit_card_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 1,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(12),
                                  ],
                                  validator: (v) {
                                    if (v != null && v.isNotEmpty && v.length != 12) {
                                      return '12 digits required';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(width: 16),
                                _buildField(
                                  label: context.tr('emergency_contact'),
                                  controller: _emergencyCtrl,
                                  icon: Icons.emergency_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 1,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),
                            // Section 4 — Address
                            _sectionTitle(context.tr('address'), Icons.location_on_rounded, isDark),
                            const SizedBox(height: 14),
                            _buildRow(
                              isCompact,
                              [
                                isCompact
                                    ? TextFormField(
                                        controller: _addressCtrl,
                                        style: AppTheme.getFontStyle(fontSize: 14),
                                        decoration: _inputDecoration(
                                          'Area / Room No. (Optional)',
                                          Icons.home_rounded,
                                          isDark,
                                        ),
                                      )
                                    : Expanded(
                                        flex: 1,
                                        child: TextFormField(
                                          controller: _addressCtrl,
                                          style: AppTheme.getFontStyle(fontSize: 14),
                                          decoration: _inputDecoration(
                                            'Area / Room No. (Optional)',
                                            Icons.home_rounded,
                                            isDark,
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildRow(
                              isCompact,
                              [
                                // Pincode
                                isCompact
                                    ? TextFormField(
                                        controller: _pinCodeCtrl,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(6),
                                        ],
                                        style: AppTheme.getFontStyle(fontSize: 14),
                                        decoration: _inputDecoration(
                                          context.tr('pincode'),
                                          Icons.pin_drop_rounded,
                                          isDark,
                                          suffix: _isFetchingPinCode
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                      strokeWidth: 2),
                                                )
                                              : null,
                                        ),
                                        onChanged: (v) {
                                          if (v.length == 6) _fetchPinCodeDetails(v);
                                        },
                                      )
                                    : Expanded(
                                        flex: 1,
                                        child: TextFormField(
                                          controller: _pinCodeCtrl,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.digitsOnly,
                                            LengthLimitingTextInputFormatter(6),
                                          ],
                                          style: AppTheme.getFontStyle(fontSize: 14),
                                          decoration: _inputDecoration(
                                            context.tr('pincode'),
                                            Icons.pin_drop_rounded,
                                            isDark,
                                            suffix: _isFetchingPinCode
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child: CircularProgressIndicator(
                                                        strokeWidth: 2),
                                                  )
                                                : null,
                                          ),
                                          onChanged: (v) {
                                            if (v.length == 6) _fetchPinCodeDetails(v);
                                          },
                                        ),
                                      ),
                                const SizedBox(width: 16),
                                // Village with dropdown
                                isCompact
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          TextFormField(
                                            controller: _villageCtrl,
                                            style: AppTheme.getFontStyle(fontSize: 14),
                                            decoration: _inputDecoration(
                                              context.tr('village'),
                                              Icons.location_city_rounded,
                                              isDark,
                                              suffix: _pinCodeVillages.isNotEmpty
                                                  ? GestureDetector(
                                                      onTap: () => setState(() {
                                                        _villageSuggestions =
                                                            _pinCodeVillages;
                                                        _showVillageDropdown =
                                                            !_showVillageDropdown;
                                                      }),
                                                      child: Icon(
                                                        _showVillageDropdown
                                                            ? Icons.arrow_drop_up
                                                            : Icons.arrow_drop_down,
                                                        color: AppTheme.primaryColor,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          if (_showVillageDropdown &&
                                              _villageSuggestions.isNotEmpty)
                                            Container(
                                              constraints:
                                                  const BoxConstraints(maxHeight: 160),
                                              margin: const EdgeInsets.only(top: 4),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? const Color(0xFF2A2A3E)
                                                    : Colors.white,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isDark
                                                      ? Colors.white.withAlpha(20)
                                                      : Colors.grey.shade200,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withAlpha(20),
                                                    blurRadius: 8,
                                                  ),
                                                ],
                                              ),
                                              child: ListView(
                                                shrinkWrap: true,
                                                children: _villageSuggestions
                                                    .map((v) => InkWell(
                                                          onTap: () => _selectVillage(v),
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                    horizontal: 14,
                                                                    vertical: 10),
                                                            child: Text(
                                                              v,
                                                              style: AppTheme.getFontStyle(
                                                                  fontSize: 13),
                                                            ),
                                                          ),
                                                        ))
                                                    .toList(),
                                              ),
                                            ),
                                        ],
                                      )
                                    : Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            TextFormField(
                                              controller: _villageCtrl,
                                              style: AppTheme.getFontStyle(fontSize: 14),
                                              decoration: _inputDecoration(
                                                context.tr('village'),
                                                Icons.location_city_rounded,
                                                isDark,
                                                suffix: _pinCodeVillages.isNotEmpty
                                                    ? GestureDetector(
                                                        onTap: () => setState(() {
                                                          _villageSuggestions =
                                                              _pinCodeVillages;
                                                          _showVillageDropdown =
                                                              !_showVillageDropdown;
                                                        }),
                                                        child: Icon(
                                                          _showVillageDropdown
                                                              ? Icons.arrow_drop_up
                                                              : Icons.arrow_drop_down,
                                                          color: AppTheme.primaryColor,
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                            ),
                                            if (_showVillageDropdown &&
                                                _villageSuggestions.isNotEmpty)
                                              Container(
                                                constraints:
                                                    const BoxConstraints(maxHeight: 160),
                                                margin: const EdgeInsets.only(top: 4),
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? const Color(0xFF2A2A3E)
                                                      : Colors.white,
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: isDark
                                                        ? Colors.white.withAlpha(20)
                                                        : Colors.grey.shade200,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withAlpha(20),
                                                      blurRadius: 8,
                                                    ),
                                                  ],
                                                ),
                                                child: ListView(
                                                  shrinkWrap: true,
                                                  children: _villageSuggestions
                                                      .map((v) => InkWell(
                                                            onTap: () => _selectVillage(v),
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                      horizontal: 14,
                                                                      vertical: 10),
                                                              child: Text(
                                                                v,
                                                                style: AppTheme.getFontStyle(
                                                                    fontSize: 13),
                                                              ),
                                                            ),
                                                          ))
                                                      .toList(),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                const SizedBox(width: 16),
                                _buildField(
                                  label: context.tr('taluka'),
                                  controller: _talukaCtrl,
                                  icon: Icons.map_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 1,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildRow(
                              isCompact,
                              [
                                _buildField(
                                  label: context.tr('district'),
                                  controller: _districtCtrl,
                                  icon: Icons.location_on_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 1,
                                ),
                                const SizedBox(width: 16),
                                _buildField(
                                  label: context.tr('state'),
                                  controller: _stateCtrl,
                                  icon: Icons.flag_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 1,
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),
                            // Section 5 — Others
                            _sectionTitle(context.tr('other_details'), Icons.notes_rounded, isDark),
                            const SizedBox(height: 14),
                            _buildRow(
                              isCompact,
                              [
                                // Status dropdown from Students settings
                                _buildDropdownField(
                                  label: context.tr('status'),
                                  value: _selectedStatus,
                                  items: _statuses,
                                  icon: Icons.toggle_on_rounded,
                                  isDark: isDark,
                                  isCompact: isCompact,
                                  flex: 1,
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() {
                                        _selectedStatus = v;
                                        final sLower = v.toLowerCase();
                                        _isActive = sLower == 'active' ||
                                            sLower == 'chalu' ||
                                            sLower == 'regular';
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(width: 16),
                                isCompact
                                    ? TextFormField(
                                        controller: _noteCtrl,
                                        style: AppTheme.getFontStyle(fontSize: 14),
                                        maxLines: 1,
                                        decoration: _inputDecoration(
                                          context.tr('note'),
                                          Icons.edit_note_rounded,
                                          isDark,
                                        ),
                                      )
                                    : Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: _noteCtrl,
                                          style: AppTheme.getFontStyle(fontSize: 14),
                                          maxLines: 1,
                                          decoration: _inputDecoration(
                                            context.tr('note'),
                                            Icons.edit_note_rounded,
                                            isDark,
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                            const SizedBox(height: 28),
                          ],
                        ),
                      );

          if (context.isMobile) {
            return Scaffold(
              backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
              appBar: AppBar(
                backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                elevation: 0,
                leadingWidth: 80,
                leading: TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF0D6B4E), size: 24),
                  label: Text(
                    'Back',
                    style: AppTheme.getFontStyle(
                      color: const Color(0xFF0D6B4E),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
                centerTitle: true,
                title: Text(
                  isEdit ? 'Edit Staff' : 'Add New Staff',
                  style: AppTheme.getFontStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),
              ),
              body: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      child: formContent,
                    ),
                  ),
                  _buildFooter(isDark, isEdit),
                ],
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              width: min(900.0, MediaQuery.of(context).size.width - 32),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.92,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 100 : 40),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(isDark, isEdit),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                      child: formContent,
                    ),
                  ),
                  _buildFooter(isDark, isEdit),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark, bool isEdit) {
    return Container(
      padding: EdgeInsets.fromLTRB(24 * _scale, 20 * _scale, 16 * _scale, 16 * _scale),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF043927), Color(0xFF0D6B4E)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24 * _scale)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10 * _scale),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withAlpha(25),
            ),
            child: Icon(Icons.badge_rounded, color: Colors.white, size: 22 * _scale),
          ),
          SizedBox(width: 14 * _scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? context.tr('edit_staff') : context.tr('add_new_staff'),
                  style: AppTheme.getFontStyle(
                    fontSize: 18 * _scale,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  isEdit
                      ? context.tr('update_staff_details_below')
                      : context.tr('fill_in_the_staff_information'),
                  style: AppTheme.getFontStyle(
                      fontSize: 12 * _scale, color: Colors.white.withAlpha(180)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: Colors.white, size: 24 * _scale),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────
  Widget _buildFooter(bool isDark, bool isEdit) {
    return Container(
      padding: EdgeInsets.fromLTRB(24 * _scale, 16 * _scale, 24 * _scale, 20 * _scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
          ),
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24 * _scale)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, size: 18 * _scale),
            label: Text(context.tr('cancel'), style: AppTheme.getFontStyle(fontSize: 13 * _scale)),
          ),
          const Spacer(),
          if (_isLoading)
            SizedBox(
              width: 24 * _scale,
              height: 24 * _scale,
              child: CircularProgressIndicator(strokeWidth: 2 * _scale),
            )
          else
            FilledButton.icon(
               onPressed: _submit,
               icon: Icon(isEdit ? Icons.save_rounded : Icons.add_rounded, size: 18 * _scale),
               label: Text(
                 isEdit ? context.tr('update_staff') : context.tr('add_staff'),
                 style: AppTheme.getFontStyle(fontSize: 14 * _scale, fontWeight: FontWeight.w600),
               ),
               style: FilledButton.styleFrom(
                 backgroundColor: AppTheme.primaryColor,
                 padding: EdgeInsets.symmetric(
                     horizontal: 24 * _scale, vertical: 14 * _scale),
                 shape: RoundedRectangleBorder(
                     borderRadius: BorderRadius.circular(12 * _scale)),
               ),
            ),
        ],
      ),
    );
  }

  // ── Section Title ──────────────────────────────────────────────────────────
  Widget _sectionTitle(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Container(
          width: 3 * _scale,
          height: 18 * _scale,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(4 * _scale),
          ),
        ),
        SizedBox(width: 10 * _scale),
        Icon(icon, size: 17 * _scale, color: AppTheme.primaryColor),
        SizedBox(width: 8 * _scale),
        Text(
          title,
          style: AppTheme.getFontStyle(
            fontSize: 14 * _scale,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        SizedBox(width: 12 * _scale),
        Expanded(
          child: Divider(
            color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
          ),
        ),
      ],
    );
  }

  Widget _buildRow(bool isCompact, List<Widget> children) {
    if (isCompact) {
      final cleanChildren = children.where((c) => c is! SizedBox).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(cleanChildren.length, (idx) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: idx < cleanChildren.length - 1 ? 14 : 0,
            ),
            child: cleanChildren[idx],
          );
        }),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // ── Generic field builder ──────────────────────────────────────────────────
  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isDark,
    required bool isCompact,
    required int flex,
    bool readOnly = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    final field = TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: AppTheme.getFontStyle(fontSize: 14 * _scale),
      validator: validator,
      decoration: _inputDecoration(label, icon, isDark),
    );
    if (isCompact) return field;
    return Expanded(flex: flex, child: field);
  }

  Widget _buildDateField({
    required String label,
    required TextEditingController controller,
    required bool isDark,
    required bool isCompact,
    required int flex,
    required VoidCallback onTap,
  }) {
    final field = TextFormField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      style: AppTheme.getFontStyle(fontSize: 14 * _scale),
      decoration: _inputDecoration(
        label,
        Icons.calendar_today_rounded,
        isDark,
      ),
    );
    if (isCompact) return field;
    return Expanded(flex: flex, child: field);
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required bool isDark,
    required bool isCompact,
    required int flex,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
  }) {
    // Ensure the current value exists in the items list to avoid crash
    final safeItems = List<String>.from(items);
    if (value != null && value.isNotEmpty && !safeItems.contains(value)) {
      safeItems.add(value);
    }
    final safeValue = (value != null && safeItems.contains(value)) ? value : null;

    final field = DropdownButtonFormField<String>(
      value: safeValue,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      style: AppTheme.getFontStyle(
        fontSize: 14 * _scale,
        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
      ),
      decoration: _inputDecoration(label, icon, isDark),
      dropdownColor: isDark ? const Color(0xFF2A2A3E) : Colors.white,
      items: safeItems
          .map((i) => DropdownMenuItem(value: i, child: Text(i)))
          .toList(),
    );
    if (isCompact) return field;
    return Expanded(flex: flex, child: field);
  }

  InputDecoration _inputDecoration(
      String label, IconData icon, bool isDark, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: AppTheme.getFontStyle(
        fontSize: 13 * _scale,
        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
      ),
      prefixIcon: Icon(icon, size: 18 * _scale, color: AppTheme.primaryColor),
      suffixIcon: suffix != null ? Padding(
        padding: EdgeInsets.only(right: 8 * _scale),
        child: suffix,
      ) : null,
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12 * _scale),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12 * _scale),
        borderSide: BorderSide(
          color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12 * _scale),
        borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12 * _scale),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      contentPadding:
          EdgeInsets.symmetric(horizontal: 14 * _scale, vertical: 14 * _scale),
      isDense: true,
    );
  }
}
