import 'package:flutter_test/flutter_test.dart';
import 'package:forestring_teacher_2/features/students/data/student_regular_schedule_repository.dart';

void main() {
  group('RegularScheduleSemesterOption', () {
    final currentSemester = RegularScheduleSemesterOption(
      id: 'current',
      code: '2026-09',
      startsOn: DateTime(2026, 8, 31),
      endsOn: DateTime(2026, 10, 4),
    );
    final futureSemester = RegularScheduleSemesterOption(
      id: 'future',
      code: '2026-10',
      startsOn: DateTime(2026, 10, 5),
      endsOn: DateTime(2026, 11, 1),
    );
    final pastSemester = RegularScheduleSemesterOption(
      id: 'past',
      code: '2026-08',
      startsOn: DateTime(2026, 7, 27),
      endsOn: DateTime(2026, 8, 30),
    );
    final today = DateTime(2026, 9, 1, 14, 30);

    test('현재 학기는 추가 목록에만 포함되고 진행 중으로 판정된다', () {
      expect(currentSemester.isSelectableOn(today), isFalse);
      expect(
        currentSemester.isSelectableOn(today, includeCurrent: true),
        isTrue,
      );
      expect(currentSemester.isInProgressOn(today), isTrue);
      expect(currentSemester.effectiveOnFor(today), DateTime(2026, 9, 1));
    });

    test('미래 학기는 기존처럼 학기 시작일을 적용일로 사용한다', () {
      expect(futureSemester.isSelectableOn(today), isTrue);
      expect(
        futureSemester.isSelectableOn(today, includeCurrent: true),
        isTrue,
      );
      expect(futureSemester.isInProgressOn(today), isFalse);
      expect(futureSemester.effectiveOnFor(today), DateTime(2026, 10, 5));
    });

    test('종료된 학기는 현재 학기 포함 목록에서도 제외된다', () {
      expect(
        pastSemester.isSelectableOn(today, includeCurrent: true),
        isFalse,
      );
      expect(pastSemester.isInProgressOn(today), isFalse);
    });
  });
}
