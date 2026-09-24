import 'package:shared_preferences/shared_preferences.dart';

class PincodeSettings {
  static const String _keyProvider = 'pincode_provider'; // 'datagov' | 'postalpincode' | 'custom'
  static const String _keyApiKey = 'pincode_api_key';
  static const String _keyCustomUrl = 'pincode_custom_url';
  
  static const String _keyMapTaluka = 'pincode_map_taluka';
  static const String _keyMapDistrict = 'pincode_map_district';
  static const String _keyMapState = 'pincode_map_state';
  static const String _keyMapVillage = 'pincode_map_village';

  static const String defaultApiKey = '579b464db66ec23bdd000001a3fe2cad70794829586e02d6268c2b46';
  static const String defaultDataGovUrl = 'https://api.data.gov.in/resource/6176ee09-3d56-4a3b-8115-21841576b2f6?api-key={apiKey}&format=json&limit=50&filters[pincode]={pincode}';

  static Future<String> getProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyProvider) ?? 'datagov';
  }

  static Future<void> setProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProvider, provider);
  }

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_keyApiKey);
    if (key == null || key.trim().isEmpty) {
      return defaultApiKey;
    }
    return key.trim();
  }

  static Future<bool> setApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.setString(_keyApiKey, apiKey.trim());
  }

  static Future<String> getCustomUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCustomUrl) ?? '';
  }

  static Future<void> setCustomUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomUrl, url.trim());
  }

  // Mappings for Custom API JSON Parsing
  static Future<String> getMapTaluka() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMapTaluka) ?? 'taluk';
  }
  static Future<void> setMapTaluka(String val) async => (await SharedPreferences.getInstance()).setString(_keyMapTaluka, val.trim());

  static Future<String> getMapDistrict() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMapDistrict) ?? 'district';
  }
  static Future<void> setMapDistrict(String val) async => (await SharedPreferences.getInstance()).setString(_keyMapDistrict, val.trim());

  static Future<String> getMapState() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMapState) ?? 'state';
  }
  static Future<void> setMapState(String val) async => (await SharedPreferences.getInstance()).setString(_keyMapState, val.trim());

  static Future<String> getMapVillage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMapVillage) ?? 'office';
  }
  static Future<void> setMapVillage(String val) async => (await SharedPreferences.getInstance()).setString(_keyMapVillage, val.trim());

  static Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyProvider);
    await prefs.remove(_keyApiKey);
    await prefs.remove(_keyCustomUrl);
    await prefs.remove(_keyMapTaluka);
    await prefs.remove(_keyMapDistrict);
    await prefs.remove(_keyMapState);
    await prefs.remove(_keyMapVillage);
  }

  // Smart Recursive JSON Parser
  static dynamic findKeyInJson(dynamic json, String targetKey) {
    if (json == null) return null;
    final cleanTarget = targetKey.trim().toLowerCase();
    
    if (json is Map) {
      for (final key in json.keys) {
        if (key.toString().toLowerCase() == cleanTarget) {
          return json[key];
        }
      }
      for (final value in json.values) {
        final res = findKeyInJson(value, targetKey);
        if (res != null) return res;
      }
    } else if (json is List) {
      for (final item in json) {
        final res = findKeyInJson(item, targetKey);
        if (res != null) return res;
      }
    }
    return null;
  }

  // Smart Recursive Village Extractor
  static List<String> extractVillages(dynamic json, String villageKey) {
    final list = <String>{};
    final cleanKey = villageKey.trim().toLowerCase();

    void traverse(dynamic current) {
      if (current == null) return;
      if (current is Map) {
        for (final entry in current.entries) {
          if (entry.key.toString().toLowerCase() == cleanKey) {
            if (entry.value is String) {
              list.add(entry.value);
            } else if (entry.value is List) {
              for (final v in entry.value) {
                if (v is String) {
                  list.add(v);
                } else if (v is Map) {
                  // If it's a list of objects, e.g. [{officename: Palanpur}]
                  final nameVal = findKeyInJson(v, villageKey) ?? findKeyInJson(v, 'name');
                  if (nameVal != null) list.add(nameVal.toString());
                }
              }
            }
          } else {
            traverse(entry.value);
          }
        }
      } else if (current is List) {
        for (final item in current) {
          if (item is Map) {
            // Check if this map contains the key directly
            final nameVal = findKeyInJson(item, villageKey);
            if (nameVal != null) {
              list.add(nameVal.toString());
            }
          }
          traverse(item);
        }
      }
    }

    traverse(json);
    return list.toList();
  }
}
