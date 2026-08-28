import 'package:flutter/material.dart';

import '../../auth/domain/current_profile.dart';
import 'student_management_v2_page.dart';

/// Compatibility entry point used by the master/manager navigation.
///
/// Student management now uses a dedicated full-page detail flow instead of
/// the previous bottom sheet so additional management actions remain stable
/// as the feature set grows.
class StudentManagementPage extends StatelessWidget {
  const StudentManagementPage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(BuildContext context) {
    return StudentManagementV2Page(profile: profile);
  }
}
