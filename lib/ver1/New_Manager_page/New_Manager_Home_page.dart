import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/New_Data/lessonClass.dart';
import 'package:forestring_teacher_2/ver1/New_Data/teacherClass.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import '../New_Data/new_constant.dart';

Route _createRoute(Page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => Page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(0.0, 1.0);
      const end = Offset.zero;
      final tween = Tween(begin: begin, end: end);
      final offsetAnimation = animation.drive(tween);
      return child;
    },
  );
}

class New_Manager_Home_page extends StatefulWidget {
  const New_Manager_Home_page({super.key});

  @override
  State<New_Manager_Home_page> createState() => _New_Manager_Home_page();
}

class _New_Manager_Home_page extends State<New_Manager_Home_page> {
  DateTime selectedDate = DateTime.utc(
    //선택된 날짜를 관리할 변수
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime focusedDate = DateTime.now();
  DateTime tmp1 = DateTime(DateTime.now().year,DateTime.now().month,1).subtract(const Duration(days: 10));
  DateTime tmp2 = DateTime(DateTime.now().year,DateTime.now().month,20).add(const Duration(days: 60));

  List<Lesson> TMP1 = [];
  List<Lesson> TMP2 = [];

  TeacherClass TMPTeacher = Allteachers[0];

  @override
  void initState() {
    super.initState();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: BaseAppBar(
            title: "\u{1F49A} FORESTRING \u{1F49A}",
            center: true,
            appBar: AppBar()),
        drawer: const ManagerDrawer(),
        floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.white,
            shape: const CircleBorder(),
            child: const Icon(Icons.refresh, color: PRIMARY_COLOR),
            onPressed: () async {
              await AllUsers();
              await Alllesson();
              Navigator.of(context).push(
                _createRoute(const New_Manager_Home_page()),
              );
            }),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded( child:
                    OutlinedButton(
                      onPressed: () => _showDialog(
                        CupertinoPicker.builder(
                          itemExtent: 30,
                          childCount: Allteachers.length,
                          onSelectedItemChanged: (i){
                            setState(() {
                              TMPTeacher = Allteachers[i];
                            });
                          },
                          itemBuilder: (context, index){
                            return Text('${Allteachers[index].name} 선생님',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20,));
                          },
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: PRIMARY_COLOR,
                          backgroundColor: Colors.white,
                          side: const BorderSide(
                              color: PRIMARY_COLOR,
                              width: 2
                          ),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)
                          ),
                          elevation: 0
                      ),
                      child: Text('${TMPTeacher.name} 선생님 시간표',
                          style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20)
                      ),
                    ),
                    ),
                  ],
                ),
                Expanded(
                  child: SfCalendar(
                    minDate: DateTime(tmp1.year,tmp1.month-1,1),
                    maxDate: DateTime(tmp2.year, tmp2.month+1, 1),
                    timeZone: 'Korea Standard Time',
                    specialRegions: _getTimeRegions(),
                    view: CalendarView.week,
                    cellBorderColor: Colors.black12,
                    todayHighlightColor: PRIMARY_COLOR,
                    showNavigationArrow: true,
                    cellEndPadding: 0,
                    dataSource: MeetingDataSource(_getDataSource()),
                    scheduleViewSettings: const ScheduleViewSettings(
                        appointmentTextStyle: TextStyle(
                          fontFamily: 'ELAND',
                          fontWeight: FontWeight.w300,
                          fontSize: 1,
                          color: Color(0xff2E8B57),
                        )),
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
                    headerStyle: const CalendarHeaderStyle(
                        backgroundColor: Colors.transparent,
                        textAlign: TextAlign.center,
                        textStyle: TextStyle(
                          fontFamily: 'OpenSans',
                          fontWeight: FontWeight.w500,
                          fontSize: 20.0,
                        )),
                    timeSlotViewSettings: const TimeSlotViewSettings(
                      dayFormat: 'EEE',
                      timeTextStyle: TextStyle(
                          fontFamily: 'openSans',
                          fontWeight: FontWeight.w500,
                          color: Colors.black),
                      timeInterval: Duration(minutes: 30),
                      timeFormat: 'h:mm',
                      startHour: 7,
                      endHour: 23,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ));
  }
  List<Meeting> _getDataSource() {
    final List<Meeting> meetings = <Meeting>[];

    for(int i=0; i<Alllessons.length ; i++) {
      if (TMPTeacher.classList.contains(Alllessons[i].id)) {
        if(Alllessons[i].isValid == true) {
          if(Alllessons[i].id.startsWith('STU')) {
            var student = Allstudents.firstWhere(
                  (student) => student.id == Alllessons[i].id.substring(0, 12), // someId는 찾고자 하는 ID
            );
            var studentName = student.name;
            meetings.add(
                Meeting(studentName,
                    Alllessons[i].time,
                    Alllessons[i].time.add(const Duration(minutes: 30)),
                    PRIMARY_COLOR.withOpacity(0.9), false));
          } else if (Alllessons[i].id.startsWith('BAN')){
            meetings.add(
                Meeting('예약불가', Alllessons[i].time, Alllessons[i].time.add(const Duration(minutes: 30)),
                    Colors.black45.withOpacity(0.3), false)
            );
          }
        }
      }
    }
    return meetings;
  }
  List<TimeRegion> _getTimeRegions() {
    final List<TimeRegion> regions = <TimeRegion>[];
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 1, TMPTeacher.workTime[0].hour, TMPTeacher.workTime[0].minute),
        endTime: DateTime(
            2024, 1, 1, TMPTeacher.workTime[1].hour, TMPTeacher.workTime[1].minute),
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 2, TMPTeacher.workTime[2].hour, TMPTeacher.workTime[2].minute),
        endTime: DateTime(
            2024, 1, 2, TMPTeacher.workTime[3].hour, TMPTeacher.workTime[3].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 3, TMPTeacher.workTime[4].hour, TMPTeacher.workTime[4].minute),
        endTime: DateTime(
            2024, 1, 3, TMPTeacher.workTime[5].hour, TMPTeacher.workTime[5].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 4, TMPTeacher.workTime[6].hour, TMPTeacher.workTime[6].minute),
        endTime: DateTime(
            2024, 1, 4, TMPTeacher.workTime[7].hour, TMPTeacher.workTime[7].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 5, TMPTeacher.workTime[8].hour, TMPTeacher.workTime[8].minute),
        endTime: DateTime(
            2024, 1, 5, TMPTeacher.workTime[9].hour, TMPTeacher.workTime[9].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 6, TMPTeacher.workTime[10].hour, TMPTeacher.workTime[10].minute),
        endTime: DateTime(
            2024, 1, 6, TMPTeacher.workTime[11].hour, TMPTeacher.workTime[11].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    return regions;
  }
  void _showDialog(Widget child){
    showCupertinoModalPopup(context: context, builder: (BuildContext context) =>
        Container(
            color: CupertinoColors.systemBackground.resolveFrom(context),
            height: MediaQuery.of(context).size.height / 3,
            padding: const EdgeInsets.only(top: 4),
            margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SafeArea(top: false,child: child,)
        )
    );
  }
}

class MeetingDataSource extends CalendarDataSource {
  /// Creates a meeting data source, which used to set the appointment
  /// collection to the calendar
  MeetingDataSource(List<Meeting> source) {
    appointments = source;
  }

  @override
  DateTime getStartTime(int index) {
    return _getMeetingData(index).from;
  }

  @override
  DateTime getEndTime(int index) {
    return _getMeetingData(index).to;
  }

  @override
  String getSubject(int index) {
    return _getMeetingData(index).eventName;
  }

  @override
  Color getColor(int index) {
    return _getMeetingData(index).background;
  }

  @override
  bool isAllDay(int index) {
    return _getMeetingData(index).isAllDay;
  }

  Meeting _getMeetingData(int index) {
    final dynamic meeting = appointments![index];
    late final Meeting meetingData;
    if (meeting is Meeting) {
      meetingData = meeting;
    }
    return meetingData;
  }
}

class Meeting {
  Meeting(this.eventName, this.from, this.to, this.background, this.isAllDay);

  /// Event name which is equivalent to subject property of [Appointment].
  String eventName;

  /// From which is equivalent to start time property of [Appointment].
  DateTime from;

  /// To which is equivalent to end time property of [Appointment].
  DateTime to;

  /// Background which is equivalent to color property of [Appointment].
  Color background;

  /// IsAllDay which is equivalent to isAllDay property of [Appointment].
  bool isAllDay;

}