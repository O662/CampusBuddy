import 'dart:convert';

class Course {
  final String id;
  final String name;
  final double credits;
  final double gradePercent;
  final String? institutionId;
  final String? semesterId;
  final bool includeInGpa;

  Course({
    required this.id,
    required this.name,
    required this.credits,
    required this.gradePercent,
    this.institutionId,
    this.semesterId,
    this.includeInGpa = true,
  });

  String get letterGrade {
    if (gradePercent >= 93) return 'A';
    if (gradePercent >= 90) return 'A-';
    if (gradePercent >= 87) return 'B+';
    if (gradePercent >= 83) return 'B';
    if (gradePercent >= 80) return 'B-';
    if (gradePercent >= 77) return 'C+';
    if (gradePercent >= 73) return 'C';
    if (gradePercent >= 70) return 'C-';
    if (gradePercent >= 67) return 'D+';
    if (gradePercent >= 63) return 'D';
    if (gradePercent >= 60) return 'D-';
    return 'F';
  }

  // Standard 4.0-scale GPA points — used for cumulative GPA
  double get gpaPoints {
    if (gradePercent >= 93) return 4.0;
    if (gradePercent >= 90) return 3.7;
    if (gradePercent >= 87) return 3.3;
    if (gradePercent >= 83) return 3.0;
    if (gradePercent >= 80) return 2.7;
    if (gradePercent >= 77) return 2.3;
    if (gradePercent >= 73) return 2.0;
    if (gradePercent >= 70) return 1.7;
    if (gradePercent >= 67) return 1.3;
    if (gradePercent >= 63) return 1.0;
    if (gradePercent >= 60) return 0.7;
    return 0.0;
  }

  // GPA points scaled to the institution's GPA scale (e.g. 5.0)
  double gpaPointsForScale(double scale) =>
      gpaPoints * (scale / 4.0);

  Course copyWith({
    String? id,
    String? name,
    double? credits,
    double? gradePercent,
    Object? institutionId = _sentinel,
    Object? semesterId = _sentinel,
    bool? includeInGpa,
  }) {
    return Course(
      id: id ?? this.id,
      name: name ?? this.name,
      credits: credits ?? this.credits,
      gradePercent: gradePercent ?? this.gradePercent,
      institutionId: institutionId == _sentinel
          ? this.institutionId
          : institutionId as String?,
      semesterId:
          semesterId == _sentinel ? this.semesterId : semesterId as String?,
      includeInGpa: includeInGpa ?? this.includeInGpa,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'credits': credits,
        'gradePercent': gradePercent,
        'institutionId': institutionId,
        'semesterId': semesterId,
        'includeInGpa': includeInGpa,
      };

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as String,
        name: json['name'] as String,
        credits: (json['credits'] as num).toDouble(),
        gradePercent: (json['gradePercent'] as num).toDouble(),
        institutionId: json['institutionId'] as String?,
        semesterId: json['semesterId'] as String?,
        includeInGpa: (json['includeInGpa'] as bool?) ?? true,
      );

  static List<Course> listFromJson(String source) {
    final list = jsonDecode(source) as List;
    return list.map((e) => Course.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<Course> courses) =>
      jsonEncode(courses.map((c) => c.toJson()).toList());
}

// Sentinel for nullable copyWith fields
const Object _sentinel = Object();
