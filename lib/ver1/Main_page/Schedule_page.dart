import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';


class Schedule_page extends StatefulWidget {
  const Schedule_page({super.key});

  @override
  State<Schedule_page> createState() => _Schedule_page();
}

class _Schedule_page extends State<Schedule_page> {
  DateTime selectedDate = DateTime.utc(
    //선택된 날짜를 관리할 변수
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime focusedDate = DateTime.now();
  DateTime tmp1 = DateTime(DateTime.now().year,DateTime.now().month,1).subtract(const Duration(days: 10));
  DateTime tmp2 = DateTime(DateTime.now().year,DateTime.now().month,20).add(const Duration(days: 55));

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
                    maxDate: DateTime(tmp2.year, tmp2.month,1),
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

    for(int i=0;i<Schedules.length;i++){
      final DateTime tmp = Schedules[i].date;
      final DateTime startTime = DateTime(tmp.year,tmp.month,tmp.day, tmp.hour, tmp.minute,0);
      final DateTime endTime = startTime.add(const Duration(minutes: 30));
      meetings.add(Meeting(Schedules[i].name, startTime, endTime, PRIMARY_COLOR.withOpacity(0.9), false));
    }

    for(int i=0;i<Rebooked.length;i++){
      final DateTime tmp = Rebooked[i].date;
      final DateTime startTime = DateTime(tmp.year,tmp.month,tmp.day,tmp.hour, tmp.minute,0);
      final DateTime endTime = startTime.add(const Duration(minutes: 30));
      meetings.add(Meeting(Rebooked[i].name, startTime, endTime, PRIMARY_COLOR.withOpacity(0.9), false));
    }

    for(int i=0;i<BanTime.length;i++){
      meetings.add(Meeting('예약불가',BanTime[bantime[i]][0], BanTime[bantime[i]][1],
          Colors.black45.withOpacity(0.3), false));
    }
    return meetings;
  }
  List<TimeRegion> _getTimeRegions() {
    final List<TimeRegion> regions = <TimeRegion>[];
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 1, WorkTime['Mon'][0].hour, WorkTime['Mon'][0].minute),
        endTime: DateTime(
            2024, 1, 1, WorkTime['Mon'][1].hour, WorkTime['Mon'][1].minute),
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 2, WorkTime['Tue'][0].hour, WorkTime['Tue'][0].minute),
        endTime: DateTime(
            2024, 1, 2, WorkTime['Tue'][1].hour, WorkTime['Tue'][1].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 3, WorkTime['Wed'][0].hour, WorkTime['Wed'][0].minute),
        endTime: DateTime(
            2024, 1, 3, WorkTime['Wed'][1].hour, WorkTime['Wed'][1].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 4, WorkTime['Thu'][0].hour, WorkTime['Thu'][0].minute),
        endTime: DateTime(
            2024, 1, 4, WorkTime['Thu'][1].hour, WorkTime['Thu'][1].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 5, WorkTime['Fri'][0].hour, WorkTime['Fri'][0].minute),
        endTime: DateTime(
            2024, 1, 5, WorkTime['Fri'][1].hour, WorkTime['Fri'][1].minute),
        recurrenceExceptionDates: const [],
        color: PRIMARY_COLOR.withOpacity(0.2),
        recurrenceRule: 'FREQ=DAILY;INTERVAL=7'));
    regions.add(TimeRegion(
        startTime: DateTime(
            2024, 1, 6, WorkTime['Sat'][0].hour, WorkTime['Sat'][0].minute),
        endTime: DateTime(
            2024, 1, 6, WorkTime['Sat'][1].hour, WorkTime['Sat'][1].minute),
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
