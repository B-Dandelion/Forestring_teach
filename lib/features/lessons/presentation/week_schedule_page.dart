import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/lesson.dart';
import 'lesson_controller.dart';
import 'widgets/lesson_action_dialog.dart';

class WeekSchedulePage extends StatelessWidget {
  const WeekSchedulePage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LessonController>();
    final teacherId = controller.selectedTeacherId ?? profile.id;
    final meetings = controller.visibleLessons
        .where((lesson) => !lesson.isCanceled)
        .map((lesson) => _LessonMeeting(lesson))
        .toList();

    return Scaffold(
      appBar: const ForestringAppBar(),
      drawer: ForestringDrawer(
        displayName: profile.displayName,
        roleLabel: '환영합니다',
        items: [
          ForestringDrawerItem(
            icon: Icons.home,
            label: '메인 페이지',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).maybePop();
            },
          ),
          ForestringDrawerItem(
            icon: Icons.event_note_outlined,
            label: '주간 시간표',
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
        onLogout: () async {
          Navigator.of(context).pop();
          await context.read<AuthController>().signOut();
          if (context.mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height - 100,
                child: controller.isLoading && controller.lessons.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : SfCalendar(
                        minDate: DateTime(
                          DateTime.now().year,
                          DateTime.now().month - 2,
                          1,
                        ),
                        maxDate: DateTime(
                          DateTime.now().year,
                          DateTime.now().month + 4,
                          0,
                        ),
                        timeZone: 'Korea Standard Time',
                        view: CalendarView.week,
                        cellBorderColor: Colors.black12,
                        todayHighlightColor: primaryColor,
                        showNavigationArrow: true,
                        cellEndPadding: 0,
                        dataSource: _LessonDataSource(meetings),
                        specialRegions: _timeRegions(
                          controller.workHoursFor(teacherId),
                        ),
                        viewHeaderHeight: 50,
                        headerDateFormat: 'M월',
                        headerStyle: const CalendarHeaderStyle(
                          backgroundColor: Colors.transparent,
                          textAlign: TextAlign.center,
                          textStyle: TextStyle(
                            color: primaryColor,
                            fontFamily: 'ELAND',
                            fontWeight: FontWeight.w500,
                            fontSize: 20,
                          ),
                        ),
                        viewHeaderStyle: const ViewHeaderStyle(
                          dateTextStyle: TextStyle(
                            color: Colors.black,
                            fontFamily: 'ELAND',
                            fontWeight: FontWeight.w500,
                          ),
                          dayTextStyle: TextStyle(
                            color: Colors.black,
                            fontFamily: 'ELAND',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        timeSlotViewSettings: const TimeSlotViewSettings(
                          dayFormat: 'EEE',
                          timeTextStyle: TextStyle(
                            fontFamily: 'OpenSans',
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                            fontSize: 11,
                          ),
                          timeInterval: Duration(minutes: 15),
                          timeIntervalHeight: 36,
                          timeFormat: 'H:mm',
                          startHour: 7,
                          endHour: 23,
                        ),
                        onTap: (details) {
                          final appointments = details.appointments;
                          if (appointments == null || appointments.isEmpty) {
                            return;
                          }

                          final meeting = appointments.first;
                          if (meeting is! _LessonMeeting) {
                            return;
                          }

                          showLessonActionDialog(
                            context: context,
                            lesson: meeting.lesson,
                            controller: context.read<LessonController>(),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TimeRegion> _timeRegions(
    List<TeacherWorkHour> workHours,
  ) {
    return workHours.map((workHour) {
      final startParts = workHour.startTime.split(':');
      final endParts = workHour.endTime.split(':');

      return TimeRegion(
        startTime: DateTime(
          2024,
          1,
          1,
          int.parse(startParts[0]),
          int.parse(startParts[1]),
        ),
        endTime: DateTime(
          2024,
          1,
          1,
          int.parse(endParts[0]),
          int.parse(endParts[1]),
        ),
        recurrenceRule:
            'FREQ=WEEKLY;BYDAY=${_weekdayCode(workHour.weekday)}',
        color: primaryColor.withValues(alpha: 0.12),
      );
    }).toList();
  }

  String _weekdayCode(int weekday) {
    return switch (weekday) {
      1 => 'MO',
      2 => 'TU',
      3 => 'WE',
      4 => 'TH',
      5 => 'FR',
      6 => 'SA',
      7 => 'SU',
      _ => 'MO',
    };
  }
}

class _LessonMeeting {
  const _LessonMeeting(this.lesson);

  final Lesson lesson;
}

class _LessonDataSource extends CalendarDataSource {
  _LessonDataSource(List<_LessonMeeting> source) {
    appointments = source;
  }

  _LessonMeeting _meeting(int index) {
    return appointments![index] as _LessonMeeting;
  }

  @override
  DateTime getStartTime(int index) => _meeting(index).lesson.startsAt;

  @override
  DateTime getEndTime(int index) => _meeting(index).lesson.endsAt;

  @override
  String getSubject(int index) {
    final lesson = _meeting(index).lesson;
    return lesson.studentName ?? '학생';
  }

  @override
  Color getColor(int index) {
    final lesson = _meeting(index).lesson;
    if (lesson.type == LessonType.makeup) {
      return secondaryColor;
    }
    if (lesson.isRescheduled) {
      return const Color(0xff4F7E67);
    }
    return primaryColor;
  }
}
