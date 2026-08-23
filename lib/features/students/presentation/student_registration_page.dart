import 'package:flutter/material.dart';

import '../../auth/domain/current_profile.dart';
import 'student_management_page.dart';

/// 기존 Drawer/라우트 호환용 진입점.
/// v3-complete에서는 수강생 등록을 수강생 관리 화면 내부 액션으로 통합한다.
class StudentRegistrationPage extends StatelessWidget {
  const StudentRegistrationPage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(BuildContext context) {
    return StudentManagementPage(profile: profile);
  }
}
