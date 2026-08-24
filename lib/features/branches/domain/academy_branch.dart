class AcademyBranch {
  const AcademyBranch({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory AcademyBranch.fromJson(
    Map<String, dynamic> json,
  ) {
    return AcademyBranch(
      id: json['id'] as String,
      name: json['name'] as String,
      isActive: json['is_active'] as bool,
    );
  }
}

class BranchManagementDetails {
  const BranchManagementDetails({
    required this.branchId,
    required this.name,
    required this.isActive,
    required this.activeManagerCount,
    required this.activeTeacherCount,
    required this.activeStudentCount,
    required this.openAssignmentCount,
    required this.activeSeriesCount,
    required this.remainingLessonCount,
    required this.canDeactivate,
  });

  final String branchId;
  final String name;
  final bool isActive;
  final int activeManagerCount;
  final int activeTeacherCount;
  final int activeStudentCount;
  final int openAssignmentCount;
  final int activeSeriesCount;
  final int remainingLessonCount;
  final bool canDeactivate;

  int get activeProfileCount =>
      activeManagerCount + activeTeacherCount + activeStudentCount;

  int get operationalBlockerCount =>
      openAssignmentCount + activeSeriesCount + remainingLessonCount;

  factory BranchManagementDetails.fromJson(
    Map<String, dynamic> json,
  ) {
    return BranchManagementDetails(
      branchId: json['branchId'] as String,
      name: json['name'] as String,
      isActive: json['isActive'] == true,
      activeManagerCount: (json['activeManagerCount'] as num).toInt(),
      activeTeacherCount: (json['activeTeacherCount'] as num).toInt(),
      activeStudentCount: (json['activeStudentCount'] as num).toInt(),
      openAssignmentCount: (json['openAssignmentCount'] as num).toInt(),
      activeSeriesCount: (json['activeSeriesCount'] as num).toInt(),
      remainingLessonCount: (json['remainingLessonCount'] as num).toInt(),
      canDeactivate: json['canDeactivate'] == true,
    );
  }
}
