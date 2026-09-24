class SponsoredStudent {
  final String id;
  final String? grNo;
  final String fullName;
  final String? fatherName;
  final String? surname;
  final String? className;
  final String? conditionType;
  final double contributorAmount;

  SponsoredStudent({
    required this.id,
    this.grNo,
    required this.fullName,
    this.fatherName,
    this.surname,
    this.className,
    this.conditionType,
    required this.contributorAmount,
  });

  factory SponsoredStudent.fromJson(Map<String, dynamic> json) {
    return SponsoredStudent(
      id: json['id'] ?? '',
      grNo: json['gr_no'],
      fullName: json['full_name'] ?? '',
      fatherName: json['father_name'],
      surname: json['surname'],
      className: json['class_name'],
      conditionType: json['condition_type'],
      contributorAmount: json['contributor_amount'] != null
          ? (json['contributor_amount'] as num).toDouble()
          : 0.0,
    );
  }
}

class Contributor {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? createdAt;
  final String? updatedAt;
  final List<SponsoredStudent> sponsoredStudents;
  final int totalStudentsHelped;
  final double totalContributionAmount;

  Contributor({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.createdAt,
    this.updatedAt,
    this.sponsoredStudents = const [],
    this.totalStudentsHelped = 0,
    this.totalContributionAmount = 0.0,
  });

  factory Contributor.fromJson(Map<String, dynamic> json) {
    return Contributor(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'],
      email: json['email'],
      address: json['address'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      sponsoredStudents: json['sponsoredStudents'] != null
          ? (json['sponsoredStudents'] as List)
              .map((i) => SponsoredStudent.fromJson(i))
              .toList()
          : const [],
      totalStudentsHelped: json['totalStudentsHelped'] ?? 0,
      totalContributionAmount: json['totalContributionAmount'] != null
          ? (json['totalContributionAmount'] as num).toDouble()
          : 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
    };
  }
}
