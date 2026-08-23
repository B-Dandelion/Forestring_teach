import 'package:flutter/foundation.dart';

import '../../auth/domain/current_profile.dart';
import '../data/lesson_repository.dart';
import '../domain/lesson.dart';

class LessonController extends ChangeNotifier {
  LessonController(
    this._repository,
    this._profile,
  );

  final LessonRepository _repository;
  final CurrentProfile _profile;

  bool _isLoading = false;
  String? _errorMessage;
  List<Lesson> _lessons = const [];
  List<VisibleTeacher> _teachers = const [];
  Map<String, List<TeacherWorkHour>> _workHours = const {};
  String? _selectedTeacherId;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Lesson> get lessons => _lessons;
  List<VisibleTeacher> get teachers => _teachers;
  Map<String, List<TeacherWorkHour>> get workHours => _workHours;
  String? get selectedTeacherId => _selectedTeacherId;

  bool get isMaster => _profile.role == AppRole.master;

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
        ]);

        _lessons = results[0] as List<Lesson>;
        _teachers = results[1] as List<VisibleTeacher>;
        _workHours =
            results[2] as Map<String, List<TeacherWorkHour>>;

        if (_selectedTeacherId == null && _teachers.isNotEmpty) {
          _selectedTeacherId = _teachers.first.id;
        }
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
          ),
        ];
        _selectedTeacherId = _profile.id;
      }
    } on LessonFailure catch (error) {
      _errorMessage = error.message;
    } catch (_) {
      _errorMessage = '수업 정보를 불러오지 못했습니다.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectTeacher(String teacherId) {
    if (_selectedTeacherId == teacherId) {
      return;
    }

    _selectedTeacherId = teacherId;
    notifyListeners();
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

  Future<List<LessonBookingOption>> getBookingOptions({
    required Lesson lesson,
    required DateTime selectedDate,
  }) async {
    final rightId = lesson.lessonRightId;
    if (rightId == null || rightId.isEmpty) {
      throw const LessonFailure(
        '이 수업에는 다시 예약할 수 있는 수업권이 없습니다.',
      );
    }

    return _repository.getBookingOptions(
      rightId: rightId,
      selectedDate: selectedDate,
    );
  }

  Future<bool> bookLessonRight({
    required Lesson lesson,
    required LessonBookingOption option,
  }) async {
    final rightId = lesson.lessonRightId;
    if (rightId == null || rightId.isEmpty) {
      _errorMessage = '이 수업에는 다시 예약할 수 있는 수업권이 없습니다.';
      notifyListeners();
      return false;
    }

    try {
      await _repository.bookLessonRight(
        rightId: rightId,
        startsAt: option.startsAt,
      );
      await reload();
      return true;
    } on LessonFailure catch (error) {
      _errorMessage = error.message;
      notifyListeners();
      return false;
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
