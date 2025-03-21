import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import '../New_Data/new_constant.dart';


class New_Schedule_page extends StatefulWidget {
  const New_Schedule_page({super.key});

  @override
  State<New_Schedule_page> createState() => _New_Schedule_page();
}

class _New_Schedule_page extends State<New_Schedule_page> {
  DateTime selectedDate = DateTime.utc(
    //선택된 날짜를 관리할 변수
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime focusedDate = DateTime.now();
  DateTime tmp1 = DateTime(DateTime.now().year, DateTime.now().month - 1,1);
  DateTime tmp2 = DateTime(DateTime.now().year, DateTime.now().month + 1,31);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: BaseAppBar(title: "FORESTRING", center: true, appBar: AppBar()),
        drawer: const BaseDrawer(),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
            child: Column(
              children: [
                Expanded(
                  child: SfCalendar(
                    minDate: DateTime(tmp1.year,tmp1.month,1),
                    maxDate: tmp2,
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

    for(int i=0; i<LessonList.length ; i++) {
      if(LessonList[i].isValid == true){
        if(LessonList[i].id.startsWith('STU')){
          meetings.add(Meeting(StudentName[LessonList[i].id.substring(0,12)]!,
              LessonList[i].time, LessonList[i].time.add(const Duration(minutes: 30)), PRIMARY_COLOR.withOpacity(0.9), false));
        } else if (LessonList[i].id.startsWith('BAN')){
          meetings.add(Meeting('예약불가', LessonList[i].time, LessonList[i].time.add(const Duration(minutes: 30)),
              Colors.black45.withOpacity(0.3), false));
        }
      }
    }
    return meetings;
  }
  List<TimeRegion> _getTimeRegions() {
    final List<TimeRegion> regions = <TimeRegion>[];
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 1, User.workTime[0].hour, User.workTime[0].minute),
        endTime: DateTime(
            2024, 1, 1, User.workTime[1].hour, User.workTime[1].minute),
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 2, User.workTime[2].hour, User.workTime[2].minute),
        endTime: DateTime(
            2024, 1, 2, User.workTime[3].hour, User.workTime[3].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 3, User.workTime[4].hour, User.workTime[4].minute),
        endTime: DateTime(
            2024, 1, 3, User.workTime[5].hour, User.workTime[5].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 4, User.workTime[6].hour, User.workTime[6].minute),
        endTime: DateTime(
            2024, 1, 4, User.workTime[7].hour, User.workTime[7].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 5, User.workTime[8].hour, User.workTime[8].minute),
        endTime: DateTime(
            2024, 1, 5, User.workTime[9].hour, User.workTime[9].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 6, User.workTime[10].hour, User.workTime[10].minute),
        endTime: DateTime(
            2024, 1, 6, User.workTime[11].hour, User.workTime[11].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    return regions;
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
