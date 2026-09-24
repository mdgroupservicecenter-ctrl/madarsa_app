import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'pincode_settings.dart';

class PincodeResult {
  final List<String> villages;
  final String taluka;
  final String district;
  final String state;
  final String country;

  PincodeResult({
    required this.villages,
    required this.taluka,
    required this.district,
    required this.state,
    this.country = 'India',
  });
}

class PincodeLookupService {
  static String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  static Future<PincodeResult?> lookup(String pinCode) async {
    final cleanPin = pinCode.trim();
    if (cleanPin.length != 6) return null;

    final provider = await PincodeSettings.getProvider();
    bool fetched = false;

    // 1. Custom Provider
    if (provider == 'custom') {
      try {
        final customUrlPattern = await PincodeSettings.getCustomUrl();
        if (customUrlPattern.isNotEmpty) {
          final apiKey = await PincodeSettings.getApiKey();
          final url = customUrlPattern
              .replaceAll('{pincode}', cleanPin)
              .replaceAll('{apiKey}', apiKey);

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

            final villages = rawVillages.map((v) {
              final clean = v.replaceAll(RegExp(r'\s+(H\.O|B\.O|S\.O|C\.O|R\.S|E\.O)$', caseSensitive: false), '').trim();
              return _toTitleCase(clean);
            }).toSet().toList()..sort();

            return PincodeResult(
              villages: villages,
              taluka: rawTaluka != null ? _toTitleCase(rawTaluka.toString()) : '',
              district: rawDistrict != null ? _toTitleCase(rawDistrict.toString()) : '',
              state: rawState != null ? _toTitleCase(rawState.toString()) : '',
              country: 'India',
            );
          }
        }
      } catch (e) {
        debugPrint('Custom Pincode API call failed: $e');
      }
    }

    // 2. Official data.gov.in API
    if (!fetched && provider == 'datagov') {
      try {
        final apiKey = await PincodeSettings.getApiKey();
        const resourceId = '6176ee09-3d56-4a3b-8115-21841576b2f6';
        final url = 'https://api.data.gov.in/resource/$resourceId?api-key=$apiKey&format=json&limit=50&filters[pincode]=$cleanPin';

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
            return PincodeResult(
              villages: villages,
              taluka: foundTaluk,
              district: foundDistrict,
              state: foundState,
              country: 'India',
            );
          }
        }
      } catch (e) {
        debugPrint('data.gov.in Pincode API call failed: $e');
      }
    }

    // 3. Fallback to postalpincode.in API
    try {
      final url = 'https://api.postalpincode.in/pincode/$cleanPin';
      final res = await Dio().get(url);
      if (res.statusCode == 200 && res.data != null && res.data is List && (res.data as List).isNotEmpty) {
        final firstItem = (res.data as List)[0];
        if (firstItem['Status'] == 'Success' && firstItem['PostOffice'] != null) {
          final List postOffices = firstItem['PostOffice'];
          final villagesSet = <String>{};
          String foundTaluk = '';
          String foundDistrict = '';
          String foundState = '';

          for (final po in postOffices) {
            final name = po['Name']?.toString().trim() ?? '';
            if (name.isNotEmpty) villagesSet.add(_toTitleCase(name));

            if (foundTaluk.isEmpty) {
              final t = (po['Taluk'] ?? po['Block'] ?? '').toString().trim();
              if (t.isNotEmpty && t.toUpperCase() != 'NA') foundTaluk = _toTitleCase(t);
            }
            if (foundDistrict.isEmpty) {
              final d = (po['District'] ?? '').toString().trim();
              if (d.isNotEmpty && d.toUpperCase() != 'NA') foundDistrict = _toTitleCase(d);
            }
            if (foundState.isEmpty) {
              final s = (po['State'] ?? '').toString().trim();
              if (s.isNotEmpty && s.toUpperCase() != 'NA') foundState = _toTitleCase(s);
            }
          }

          final villages = villagesSet.toList()..sort();
          return PincodeResult(
            villages: villages,
            taluka: foundTaluk,
            district: foundDistrict,
            state: foundState,
            country: 'India',
          );
        }
      }
    } catch (e) {
      debugPrint('postalpincode.in API call failed: $e');
    }

    return null;
  }
}
