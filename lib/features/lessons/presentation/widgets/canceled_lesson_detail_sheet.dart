import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';

Future<void> showCanceledLessonDetailSheet({
  required BuildContext context,
  required Lesson lesson,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          decoration: const BoxDecoration(
            color: neutralIvory,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: FutureBuilder<_CancellationActor>(
            future: _loadCancellationActor(lesson),
            builder: (context, snapshot) {
              final actor = snapshot.data;
              final canceledAt = lesson.canceledAt;
              final reason = lesson.cancellationReason?.trim();
              final isStudentCancel = actor?.id == lesson.studentId;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '취소 내역',
                          style: forestringTextStyle.copyWith(
                            color: primaryColor,
                            fontSize: 21,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      _pill('취소됨'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${lesson.studentName ?? '학생'} · ${lesson.type.label}',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black87,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '취소된 수업',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${DateFormat('M월 d일 HH:mm').format(lesson.startsAt)} ~ '
                          '${DateFormat('HH:mm').format(lesson.endsAt)}',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black87,
                            fontSize: 16,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        if (lesson.teacherName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${lesson.teacherName} 선생님',
                            style: forestringTextStyle.copyWith(
                              color: Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.055),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailRow(
                          '처리 구분',
                          snapshot.connectionState == ConnectionState.waiting
                              ? '확인 중...'
                              : isStudentCancel
                                  ? '학생 취소'
                                  : '학원 취소',
                        ),
                        const SizedBox(height: 8),
                        _detailRow(
                          '처리자',
                          snapshot.connectionState == ConnectionState.waiting
                              ? '확인 중...'
                              : actor?.displayLabel ?? '확인되지 않음',
                        ),
                        const SizedBox(height: 8),
                        _detailRow(
                          '취소 일시',
                          canceledAt == null
                              ? '기록 없음'
                              : DateFormat('yyyy.MM.dd HH:mm').format(canceledAt),
                        ),
                        if (reason != null && reason.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _detailRow('사유', reason),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('확인'),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

Widget _detailRow(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 72,
        child: Text(
          label,
          style: forestringTextStyle.copyWith(
            color: Colors.black45,
            fontSize: 13,
          ),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: forestringTextStyle.copyWith(
            color: Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

Widget _pill(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: forestringTextStyle.copyWith(
        color: Colors.black54,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

Future<_CancellationActor> _loadCancellationActor(Lesson lesson) async {
  try {
    final client = Supabase.instance.client;
    final lessonRow = await client
        .from('lessons')
        .select('canceled_by')
        .eq('id', lesson.id)
        .maybeSingle();
    final actorId = lessonRow?['canceled_by']?.toString();
    if (actorId == null || actorId.isEmpty) {
      return const _CancellationActor(
        id: '',
        name: null,
        role: null,
      );
    }

    final profileRow = await client
        .from('profiles')
        .select('display_name, role')
        .eq('id', actorId)
        .maybeSingle();

    return _CancellationActor(
      id: actorId,
      name: profileRow?['display_name']?.toString(),
      role: profileRow?['role']?.toString(),
    );
  } catch (_) {
    return const _CancellationActor(
      id: '',
      name: null,
      role: null,
    );
  }
}

class _CancellationActor {
  const _CancellationActor({
    required this.id,
    required this.name,
    required this.role,
  });

  final String id;
  final String? name;
  final String? role;

  String get displayLabel {
    if (id.isEmpty) return '확인되지 않음';

    final roleLabel = switch (role) {
      'master' => '전체 관리자',
      'manager' => '지점장',
      'teacher' => '선생님',
      'student' => '수강생',
      _ => '사용자',
    };
    final displayName = name?.trim();
    return displayName == null || displayName.isEmpty
        ? roleLabel
        : '$displayName · $roleLabel';
  }
}
