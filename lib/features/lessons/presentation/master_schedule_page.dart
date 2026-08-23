import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../branches/presentation/branch_management_page.dart';
import '../../students/presentation/student_management_page.dart';
import '../domain/lesson.dart';
import 'lesson_controller.dart';
import 'widgets/lesson_action_dialog.dart';
import 'widgets/lesson_calendar_appointment.dart';

class MasterSchedulePage extends StatelessWidget {
  const MasterSchedulePage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LessonController>();
    final selectedBranchId = controller.selectedBranchId;
    final selectedTeacherId = controller.selectedTeacherId;
    final meetings = controller.visibleLessons
        .where((lesson) => !lesson.isCanceled)
        .map((lesson) => _MasterMeeting(lesson))
        .toList();

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: controller.isLoading ? null : controller.reload,
            icon: controller.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: ForestringDrawer(
        displayName: profile.displayName,
        nameSuffix: profile.isManager ? '지점장님' : '선생님',
        roleLabel: profile.isMaster ? '전체 관리자' : '환영합니다',
        showHeart: profile.isMaster,
        items: [
          ForestringDrawerItem(
            icon: Icons.home,
            label: '메인 페이지',
            onTap: () => Navigator.of(context).pop(),
          ),
          ForestringDrawerItem(
            icon: Icons.calendar_month_outlined,
            label: '수업 관리',
            onTap: () => Navigator.of(context).pop(),
          ),
          ForestringDrawerItem(
            icon: Icons.people_alt_outlined,
            label: '수강생 관리',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StudentManagementPage(
                    profile: profile,
                  ),
                ),
              );
            },
          ),
          if (profile.isMaster)
            ForestringDrawerItem(
              icon: Icons.storefront_outlined,
              label: '지점 관리',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BranchManagementPage(
                      profile: profile,
                    ),
                  ),
                );
              },
            ),
        ],
        onLogout: () async {
          Navigator.of(context).pop();
          await context.read<AuthController>().signOut();
        },
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(10),
            children: [
              if (controller.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    controller.errorMessage!,
                    style: forestringTextStyle.copyWith(
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedBranchId,
                      decoration: _selectorDecoration('지점 선택'),
                      items: controller.branches
                          .map(
                            (branch) => DropdownMenuItem<String>(
                              value: branch.id,
                              child: Text(
                                branch.name,
                                overflow: TextOverflow.ellipsis,
                                style: forestringTextStyle.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: profile.isManager
                          ? null
                          : (value) {
                              if (value != null) {
                                controller.selectBranch(value);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: selectedTeacherId,
                      decoration: _selectorDecoration('선생님 선택'),
                      items: controller.branchTeachers
                          .map(
                            (teacher) => DropdownMenuItem<String>(
                              value: teacher.id,
                              child: Text(
                                teacher.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: forestringTextStyle.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          controller.selectTeacher(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: MediaQuery.of(context).size.height - 180,
                child: controller.isLoading && controller.lessons.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : selectedTeacherId == null
                        ? Center(
                            child: Text(
                              selectedBranchId == null
                                  ? '등록된 지점이 없습니다.'
                                  : '선택한 지점에 선생님이 없습니다.',
                              style: forestringTextStyle,
                            ),
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
                            dataSource: _MasterDataSource(meetings),
                            appointmentBuilder: (context, details) {
                              if (details.appointments.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              final meeting = details.appointments.first;
                              if (meeting is! _MasterMeeting) {
                                return const SizedBox.shrink();
                              }

                              return LessonCalendarAppointment(
                                lesson: meeting.lesson,
                              );
                            },
                            specialRegions: _timeRegions(
                              controller.workHoursFor(
                                selectedTeacherId,
                              ),
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
                                fontFamily: 'OpenSans',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            timeSlotViewSettings:
                                const TimeSlotViewSettings(
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
                              if (appointments == null ||
                                  appointments.isEmpty) {
                                return;
                              }

                              final meeting = appointments.first;
                              if (meeting is! _MasterMeeting) {
                                return;
                              }

                              showLessonActionDialog(
                                context: context,
                                lesson: meeting.lesson,
                                controller:
                                    context.read<LessonController>(),
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

  InputDecoration _selectorDecoration(String label) {
    return InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: forestringTextStyle.copyWith(
        color: primaryColor,
        fontSize: 12,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 12,
      ),
      border: const OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(
          color: primaryColor.withValues(alpha: 0.35),
        ),
      ),
      filled: true,
      fillColor: Colors.white,
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

class _MasterMeeting {
  const _MasterMeeting(this.lesson);

  final Lesson lesson;
}

class _MasterDataSource extends CalendarDataSource {
  _MasterDataSource(List<_MasterMeeting> source) {
    appointments = source;
  }

  _MasterMeeting _meeting(int index) {
    return appointments![index] as _MasterMeeting;
  }

  @override
  DateTime getStartTime(int index) => _meeting(index).lesson.startsAt;

  @override
  DateTime getEndTime(int index) => _meeting(index).lesson.endsAt;

  @override
  String getSubject(int index) {
    return _meeting(index).lesson.studentName ?? '학생';
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
