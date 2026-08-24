class SemesterBranchOverride {
  const SemesterBranchOverride({
    required this.branchId,
    required this.semesterId,
    required this.startsOn,
    required this.endsOn,
  });

  final String branchId;
  final String semesterId;
  final DateTime startsOn;
  final DateTime endsOn;

  factory SemesterBranchOverride.fromJson(Map<String, dynamic> json) {
    return SemesterBranchOverride(
      branchId: json['branch_id'] as String,
      semesterId: json['semester_id'] as String,
      startsOn: DateTime.parse(json['starts_on'].toString()),
      endsOn: DateTime.parse(json['ends_on'].toString()),
    );
  }
}

class ManagedSemester {
  const ManagedSemester({
    required this.id,
    required this.code,
    required this.startsOn,
    required this.endsOn,
    required this.branchOverrides,
  });

  final String id;
  final String code;
  final DateTime startsOn;
  final DateTime endsOn;
  final List<SemesterBranchOverride> branchOverrides;

  int get dayCount => endsOn.difference(startsOn).inDays + 1;
  int get weekCount => dayCount ~/ 7;

  bool get isCurrent {
    final today = _dateOnly(DateTime.now());
    return !today.isBefore(startsOn) && !today.isAfter(endsOn);
  }

  bool get isPast => _dateOnly(DateTime.now()).isAfter(endsOn);
  bool get isUpcoming => _dateOnly(DateTime.now()).isBefore(startsOn);

  SemesterBranchOverride? overrideFor(String branchId) {
    for (final override in branchOverrides) {
      if (override.branchId == branchId) return override;
    }
    return null;
  }

  DateTime effectiveStart(String branchId) =>
      overrideFor(branchId)?.startsOn ?? startsOn;

  DateTime effectiveEnd(String branchId) =>
      overrideFor(branchId)?.endsOn ?? endsOn;

  factory ManagedSemester.fromJson(
    Map<String, dynamic> json, {
    List<SemesterBranchOverride> branchOverrides = const [],
  }) {
    return ManagedSemester(
      id: json['id'] as String,
      code: json['code'].toString(),
      startsOn: DateTime.parse(json['starts_on'].toString()),
      endsOn: DateTime.parse(json['ends_on'].toString()),
      branchOverrides: List.unmodifiable(branchOverrides),
    );
  }
}

class SemesterCalendarChange {
  const SemesterCalendarChange({
    required this.semesterId,
    required this.code,
    required this.startsOn,
    required this.endsOn,
  });

  final String semesterId;
  final String code;
  final DateTime startsOn;
  final DateTime endsOn;

  Map<String, dynamic> toJson() => {
        'semesterId': semesterId,
        'code': code,
        'startsOn': _dateText(startsOn),
        'endsOn': _dateText(endsOn),
      };
}

class BranchSemesterChange {
  const BranchSemesterChange._({
    required this.semesterId,
    this.startsOn,
    this.endsOn,
    this.delete = false,
  });

  factory BranchSemesterChange.upsert({
    required String semesterId,
    required DateTime startsOn,
    required DateTime endsOn,
  }) {
    return BranchSemesterChange._(
      semesterId: semesterId,
      startsOn: startsOn,
      endsOn: endsOn,
    );
  }

  factory BranchSemesterChange.delete(String semesterId) {
    return BranchSemesterChange._(
      semesterId: semesterId,
      delete: true,
    );
  }

  final String semesterId;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final bool delete;

  Map<String, dynamic> toJson() {
    if (delete) {
      return {
        'semesterId': semesterId,
        'delete': true,
      };
    }

    return {
      'semesterId': semesterId,
      'startsOn': _dateText(startsOn!),
      'endsOn': _dateText(endsOn!),
    };
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateText(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
