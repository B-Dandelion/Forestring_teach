import 'package:flutter/foundation.dart';

import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/lesson_repository.dart';
import '../domain/lesson.dart';

class LessonController extends ChangeNotifier {
  LessonController(
    this._repository,
    this._profile, {
    BranchRepository? branchRepository,
  }) : _branchRepository = branchRepository ?? BranchRepository();

  final LessonRepository _repository;
  final BranchRepository _branchRepository;
  final CurrentProfile _profile;

  bool _isLoading = false;
  String? _errorMessage;
  List<Lesson> _lessons = const [];
  List<VisibleTeacher> _teachers = const [];
  List<AcademyBranch> _branches = const [];
  Map<String, List<TeacherWorkHour>> _workHours = const {};
  String? _selectedBranchId;
  String? _selectedTeacherId;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Lesson> get lessons => _lessons;
  List<VisibleTeacher> get teachers => _teachers;
  List<AcademyBranch> get branches => _branches;
  Map<String, List<TeacherWorkHour>> get workHours => _workHours;
  String? get selectedBranchId => _selectedBranchId;
  String? get selectedTeacherId => _selectedTeacherId;

  bool get isMaster => _profile.role == AppRole.master;

  List<VisibleTeacher> get branchTeachers {
    if (!isMaster || _selectedBranchId == null) {
      return _teachers;
    }

    return _teachers
        .where((teacher) => teacher.branchId == _selectedBranchId)
        .toList();
  }

  List<Lesson> get visibleLessons {
    final teacherId = _selectedTeacherId;
    if (!isMaster || teacherId == null || teacherId.isEmpty) {
      return _lessons;
    }

    return _lessons
        .where((lesson) => lesson.teacherId == teacherId)
        .toList();
  }

  Future<void> initialize() async {
    await reload();
  }

  Future<void> reload() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final from = DateTime(
        now.year,
        now.month - 2,
        1,
      );
      final to = DateTime(
        now.year,
        now.month + 4,
        1,
      );

      if (isMaster) {
        final results = await Future.wait<dynamic>([
          _repository.fetchVisibleLessons(
            from: from,
            to: to,
          ),
          _repository.fetchVisibleTeachers(),
          _repository.fetchVisibleWorkHours(),
          _branchRepository.fetchBranches(),
        ]);

        _lessons = results[0] as List<Lesson>;

        _teachers = List<VisibleTeacher>.from(
          results[1] as List<VisibleTeacher>,
        )..sort(
            (a, b) => a.displayName.compareTo(b.displayName),
          );

        _workHours =
            results[2] as Map<String, List<TeacherWorkHour>>;

        _branches = (results[3] as List<AcademyBranch>)
            .where((branch) => branch.isActive)
            .toList()
          ..sort(
            (a, b) => a.name.compareTo(b.name),
          );

        final branchStillExists = _selectedBranchId != null &&
            _branches.any((branch) => branch.id == _selectedBranchId);

        if (!branchStillExists) {
          _selectedBranchId = _branches.isNotEmpty ? _branches.first.id : null;
        }

        _ensureTeacherSelectionForBranch();
      } else {
        final results = await Future.wait<dynamic>([
          _repository.fetchVisibleLessons(
            from: from,
            to: to,
            teacherId: _profile.id,
          ),
          _repository.fetchVisibleWorkHours(
            teacherId: _profile.id,
          ),
        ]);

        _lessons = results[0] as List<Lesson>;
        _workHours =
            results[1] as Map<String, List<TeacherWorkHour>>;
        _teachers = [
          VisibleTeacher(
            id: _profile.id,
            displayName: _profile.displayName,
            branchId: _profile.branchId,
          ),
        ];
        _selectedBranchId = _profile.branchId;
        _selectedTeacherId = _profile.id;
      }
    } on LessonFailure catch (error) {
      _errorMessage = error.message;
    } on BranchFailure catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = '수업 정보를 불러오지 못했습니다.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectBranch(String branchId) {
    if (_selectedBranchId == branchId) {
      return;
    }

    _selectedBranchId = branchId;
    _selectedTeacherId = null;
    _ensureTeacherSelectionForBranch();
    notifyListeners();
  }

  void selectTeacher(String teacherId) {
    if (_selectedTeacherId == teacherId) {
      return;
    }

    _selectedTeacherId = teacherId;
    notifyListeners();
  }

  void _ensureTeacherSelectionForBranch() {
    final candidates = branchTeachers;

    final teacherStillVisible = _selectedTeacherId != null &&
        candidates.any((teacher) => teacher.id == _selectedTeacherId);

    if (!teacherStillVisible) {
      _selectedTeacherId = candidates.isNotEmpty ? candidates.first.id : null;
    }
  }

  List<Lesson> lessonsOn(DateTime date) {
    return visibleLessons.where((lesson) {
      final local = lesson.startsAt;
      return local.year == date.year &&
          local.month == date.month &&
          local.day == date.day;
    }).toList();
  }

  List<TeacherWorkHour> workHoursFor(String teacherId) {
    return _workHours[teacherId] ?? const [];
  }

  Future<bool> cancelLesson(
    Lesson lesson, {
    String? reason,
  }) async {
    try {
      await _repository.cancelLesson(
        lessonId: lesson.id,
        reason: reason,
      );
      await reload();
      return true;
    } on LessonFailure catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
    }
  }

  Future<LessonMutationResult?> updateLessonOnce({
    required Lesson lesson,
    required DateTime startsAt,
    required int durationMinutes,
    bool confirmWarnings = false,
    String? reason,
  }) async {
    try {
      final result = await _repository.updateLessonOnce(
        lessonId: lesson.id,
        startsAt: startsAt,
        durationMinutes: durationMinutes,
        confirmWarnings: confirmWarnings,
        reason: reason,
      );

      if (!result.requiresConfirmation) {
        await reload();
      }

      return result;
    } on LessonFailure catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return null;
    }
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }
}
