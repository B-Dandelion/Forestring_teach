import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/lesson.dart';

class LessonFailure implements Exception {
  const LessonFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class LessonRepository {
  LessonRepository({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Lesson>> fetchVisibleLessons({
    DateTime? from,
    DateTime? to,
    String? teacherId,
  }) async {
    try {
      dynamic query = _client.from('lessons').select(
            'id, student_id, teacher_id, occurrence_at, starts_at, '
            'duration_minutes, ends_at, lesson_type, status, branch_id, '
            'lesson_right_id, rescheduled_by',
          );

      if (from != null) {
        query = query.gte(
          'starts_at',
          from.toUtc().toIso8601String(),
        );
      }

      if (to != null) {
        query = query.lt(
          'starts_at',
          to.toUtc().toIso8601String(),
        );
      }

      if (teacherId != null && teacherId.isNotEmpty) {
        query = query.eq('teacher_id', teacherId);
      }

      final rows = await query.order('starts_at');
      final lessons = (rows as List)
          .map(
            (row) => Lesson.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();

      final names = await _fetchVisibleProfileNames();

      return lessons
          .map(
            (lesson) => lesson.copyWithNames(
              studentName: names[lesson.studentId],
              teacherName: names[lesson.teacherId],
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(error.message),
      );
    } catch (error) {
      throw LessonFailure(
        '수업 정보를 불러오지 못했습니다.\n$error',
      );
    }
  }

  Future<List<VisibleTeacher>> fetchVisibleTeachers() async {
    try {
      final rows = await _client
          .from('profiles')
          .select('id, display_name, branch_id, role, is_active')
          .inFilter('role', ['teacher', 'manager'])
          .eq('is_active', true)
          .order('display_name');

      return (rows as List)
          .map(
            (row) => VisibleTeacher(
              id: row['id'] as String,
              displayName: row['display_name'] as String,
              branchId: row['branch_id'] as String?,
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(error.message),
      );
    }
  }

  Future<Map<String, List<TeacherWorkHour>>>
      fetchVisibleWorkHours({
    String? teacherId,
  }) async {
    try {
      dynamic query = _client.from('teacher_work_hours').select(
            'teacher_id, weekday, start_time, end_time',
          );

      if (teacherId != null && teacherId.isNotEmpty) {
        query = query.eq('teacher_id', teacherId);
      }

      final rows = await query.order('weekday');
      final result = <String, List<TeacherWorkHour>>{};

      for (final raw in rows as List) {
        final workHour = TeacherWorkHour.fromJson(
          Map<String, dynamic>.from(raw as Map),
        );
        result
            .putIfAbsent(workHour.teacherId, () => [])
            .add(workHour);
      }

      return result;
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(error.message),
      );
    }
  }

  Future<void> cancelLesson({
    required String lessonId,
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'cancel_lesson',
        params: {
          'p_lesson_id': lessonId,
          'p_reason': _nullIfBlank(reason),
        },
      );
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(error.message),
      );
    }
  }

  Future<LessonMutationResult> updateLessonOnce({
    required String lessonId,
    required DateTime startsAt,
    required int durationMinutes,
    bool confirmWarnings = false,
    String? reason,
  }) async {
    try {
      final data = await _client.rpc(
        'update_lesson_once',
        params: {
          'p_lesson_id': lessonId,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_duration_minutes': durationMinutes,
          'p_confirm_warnings': confirmWarnings,
          'p_reason': _nullIfBlank(reason),
        },
      );

      if (data is! Map) {
        throw const LessonFailure(
          '수업 수정 결과를 확인하지 못했습니다.',
        );
      }

      return LessonMutationResult.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on LessonFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw LessonFailure(
        _friendlyDatabaseMessage(error.message),
      );
    }
  }

  Future<Map<String, String>> _fetchVisibleProfileNames() async {
    final rows = await _client
        .from('profiles')
        .select('id, display_name');

    return {
      for (final row in rows as List)
        row['id'] as String: row['display_name'] as String,
    };
  }

  String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _friendlyDatabaseMessage(String message) {
    if (message.contains('FORESTRING_EFFECTIVE_ACCESS_REQUIRED')) {
      return '현재 계정은 더 이상 사용할 수 없습니다.';
    }
    if (message.contains('FORESTRING_TEACHER_LESSON_OVERLAP') ||
        message.contains('FORESTRING_STUDENT_LESSON_OVERLAP') ||
        message.contains('FORESTRING_LESSON_TIME_CONFLICT')) {
      return '겹치는 수업이 있어 해당 시간으로 변경할 수 없습니다.';
    }
    if (message.contains('FORESTRING_ONLY_SCHEDULED_LESSON_EDITABLE')) {
      return '예정된 수업만 수정할 수 있습니다.';
    }
    if (message.contains('FORESTRING_INVALID_LESSON_DURATION')) {
      return '수업 시간은 15분 단위로 입력해주세요.';
    }
    if (message.contains('FORESTRING_CANCEL')) {
      return '현재 정책상 이 수업을 취소할 수 없습니다.';
    }
    if (message.contains('FORESTRING_LESSON_NOT_FOUND')) {
      return '수업을 찾을 수 없습니다.';
    }
    if (message.contains('FORESTRING_')) {
      return '요청을 처리할 수 없습니다. ($message)';
    }
    return '요청 처리 중 오류가 발생했습니다.';
  }
}
