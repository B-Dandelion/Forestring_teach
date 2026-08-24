enum BranchClosureKind {
  instructionalBreak('instructional_break'),
  ordinary('ordinary');

  const BranchClosureKind(this.value);

  final String value;

  static BranchClosureKind fromValue(String value) {
    return BranchClosureKind.values.firstWhere(
      (kind) => kind.value == value,
      orElse: () => BranchClosureKind.ordinary,
    );
  }
}

class BranchClosure {
  const BranchClosure({
    required this.id,
    required this.branchId,
    required this.semesterId,
    required this.startsOn,
    required this.endsOn,
    required this.reason,
    required this.kind,
  });

  final String id;
  final String branchId;
  final String? semesterId;
  final DateTime startsOn;
  final DateTime endsOn;
  final String? reason;
  final BranchClosureKind kind;

  factory BranchClosure.fromJson(Map<String, dynamic> json) {
    return BranchClosure(
      id: json['id'] as String,
      branchId: json['branch_id'] as String,
      semesterId: json['semester_id'] as String?,
      startsOn: DateTime.parse(json['starts_on'].toString()),
      endsOn: DateTime.parse(json['ends_on'].toString()),
      reason: json['reason'] as String?,
      kind: BranchClosureKind.fromValue(json['closure_kind'].toString()),
    );
  }
}

class AcademySemester {
  const AcademySemester({
    required this.id,
    required this.code,
    required this.startsOn,
    required this.endsOn,
  });

  final String id;
  final String code;
  final DateTime startsOn;
  final DateTime endsOn;

  bool contains(DateTime start, DateTime end) {
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    final semesterStart = DateTime(startsOn.year, startsOn.month, startsOn.day);
    final semesterEnd = DateTime(endsOn.year, endsOn.month, endsOn.day);

    return !startDate.isBefore(semesterStart) && !endDate.isAfter(semesterEnd);
  }

  factory AcademySemester.fromJson(Map<String, dynamic> json) {
    return AcademySemester(
      id: json['id'] as String,
      code: json['code'] as String,
      startsOn: DateTime.parse(json['starts_on'].toString()),
      endsOn: DateTime.parse(json['ends_on'].toString()),
    );
  }
}
