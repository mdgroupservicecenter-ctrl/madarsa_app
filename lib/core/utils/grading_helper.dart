import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class GradingRule {
  final String grade;
  final double minPercent;
  final double maxPercent;

  GradingRule({
    required this.grade,
    required this.minPercent,
    required this.maxPercent,
  });

  Map<String, dynamic> toJson() => {
        'grade': grade,
        'minPercent': minPercent,
        'maxPercent': maxPercent,
      };

  factory GradingRule.fromJson(Map<String, dynamic> json) => GradingRule(
        grade: json['grade'] as String,
        minPercent: (json['minPercent'] as num).toDouble(),
        maxPercent: (json['maxPercent'] as num).toDouble(),
      );
}

class GradingHelper {
  static const String _key = 'custom_grading_rules';

  static final List<GradingRule> defaultRules = [
    GradingRule(grade: 'A+', minPercent: 90.0, maxPercent: 100.0),
    GradingRule(grade: 'A', minPercent: 80.0, maxPercent: 89.99),
    GradingRule(grade: 'B', minPercent: 70.0, maxPercent: 79.99),
    GradingRule(grade: 'C', minPercent: 60.0, maxPercent: 69.99),
    GradingRule(grade: 'D', minPercent: 50.0, maxPercent: 59.99),
    GradingRule(grade: 'E', minPercent: 33.0, maxPercent: 49.99),
    GradingRule(grade: 'F', minPercent: 0.0, maxPercent: 32.99),
  ];

  static Future<List<GradingRule>> getRules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_key);
      if (str == null) {
        return List<GradingRule>.from(defaultRules);
      }
      final list = jsonDecode(str) as List;
      return list.map((item) => GradingRule.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return List<GradingRule>.from(defaultRules);
    }
  }

  static Future<void> saveRules(List<GradingRule> rules) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = jsonEncode(rules.map((r) => r.toJson()).toList());
      await prefs.setString(_key, str);
    } catch (_) {}
  }

  static String getGrade(double percentage, List<GradingRule> rules) {
    for (final rule in rules) {
      if (percentage >= rule.minPercent && percentage <= rule.maxPercent) {
        return rule.grade;
      }
    }
    return '-';
  }
}
