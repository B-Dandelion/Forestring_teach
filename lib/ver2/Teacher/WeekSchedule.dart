import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:provider/provider.dart';

class WeekSchedule extends StatefulWidget {
  const WeekSchedule({super.key});

  @override
  State<WeekSchedule> createState() => _WeekSchedule();
}

class _WeekSchedule extends State<WeekSchedule> {
  DateTime selectedDate = DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime focusedDate = DateTime.now();
  DateTime tmp1 = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
  DateTime tmp2 = DateTime(DateTime.now().year, DateTime.now().month + 1, 31);

  @override
  Widget build(BuildContext context) {
    final lessonProvider = Provider.of<LessonProvider>(context);
    final userProvider = Provider.of<UserProvider>(context);

    return Scaffold(
      appBar: BaseAppBar(title: "FORESTRING", center: true, appBar: AppBar()),
      drawer: const BaseDrawer(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
          child: Column(
            children: [
              Expanded(
                child: Consumer<LessonProvider>(
                  builder: (context, lessonProvider, child) {
                    return SfCalendar(
                      minDate: DateTime(tmp1.year, tmp1.month, 1),
                      maxDate: tmp2,
                      timeZone: 'Korea Standard Time',
                      specialRegions: _getTimeRegions(context),
                      view: CalendarView.week,
                      cellBorderColor: Colors.black12,
                      todayHighlightColor: PRIMARY_COLOR,
                      showNavigationArrow: true,
                      cellEndPadding: 0,
                      dataSource: MeetingDataSource(_getDataSource(lessonProvider, userProvider)),
                      viewHeaderHeight: 50,
                      scheduleViewSettings: const ScheduleViewSettings(
                        appointmentTextStyle: TextStyle(
                          fontFamily: 'ELAND',
                          fontWeight: FontWeight.w300,
                          fontSize: 1,
                          color: Color(0xff2E8B57),
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
                      headerStyle: const CalendarHeaderStyle(
                        backgroundColor: Colors.transparent,
                        textAlign: TextAlign.center,
                        textStyle: TextStyle(
                          fontFamily: 'OpenSans',
                          fontWeight: FontWeight.w500,
                          fontSize: 20.0,
                        ),
                      ),
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
                      // 수업 클릭 시 상세 내용을 보여 준다.
                      onTap: (CalendarTapDetails details) {
                        if (details.appointments != null && details.appointments!.isNotEmpty) {
                          _showBookingDialog(context, details);
                        }
                      },
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
  List<Meeting> _getDataSource(LessonProvider lessonProvider, UserProvider userProvider) {
    final List<Meeting> meetings = <Meeting>[];

    for (var entry in lessonProvider.lessons.entries) { // Map의 entries 사용
      Map<String, dynamic> lesson = entry.value; // lessonData
      bool isRescheduled = lesson['isRescheduled'];
      String status = lesson['status'];
      // 취소된 수업은 스킵
      if (status == "canceled") continue;

      DateTime startTime = lesson["date"]; // Firestore에서 저장된 DateTime
      DateTime endTime = startTime.add(Duration(minutes: lesson["duration"])); // duration 적용
      String studentName = userProvider.studentNames[lesson["studentId"]] ?? "Unknown";

      // 수업 색상 설정 (예약 금지, 재예약 여부에 따라)
      Color lessonColor = PRIMARY_COLOR; // 기본값

      if (status == 'ban') {
        studentName = 'X'; // 예약 금지 시간대
        lessonColor = Colors.black38;
      } else if (isRescheduled) {
        lessonColor = Color(0xff708C7A); // 재예약된 수업 색상
      }
      meetings.add(Meeting(
        studentName,
        startTime,
        endTime,
        lessonColor,
        status,
        isRescheduled,
      ));
    }
    return meetings;
  }
  List<TimeRegion> _getTimeRegions(BuildContext context) {
    final slotProvider = Provider.of<SlotProvider>(context, listen: false);
    List<TimeRegion> regions = [];

    for (var day in slotProvider.workSchedule.keys) {
      var slot = slotProvider.workSchedule[day];
      if (slot != null && slot["startTime"] != null && slot["endTime"] != null) {
        DateTime startTime = DateTime(2024, 1, 1, int.parse(slot["startTime"]!.split(":")[0]), int.parse(slot["startTime"]!.split(":")[1]));
        DateTime endTime = DateTime(2024, 1, 1, int.parse(slot["endTime"]!.split(":")[0]), int.parse(slot["endTime"]!.split(":")[1]));

        regions.add(TimeRegion(
          startTime: startTime,
          endTime: endTime,
          recurrenceRule: 'FREQ=WEEKLY;BYDAY=$day', // Firestore 데이터 그대로 사용
          color: PRIMARY_COLOR.withOpacity(0.2),
        ));
      }
    }
    return regions;
  }
  void _showBookingDialog(BuildContext context, CalendarTapDetails details) {
    Meeting meeting = details.appointments!.first as Meeting;

    // 상세 창에 표시될 문자열 변수인 제목, 수업 유형, 예약 변경 여부 선언
    String statusDisplay = "";
    String lessonType = meeting.isRescheduled ? "변경된 수업" : "정규 수업";
    String title = '${meeting.eventName} 님의 수업';

    if (meeting.status == 'makeup') {
      // 보강 수업인 경우 표시
      statusDisplay = "보강 수업";
    } else if (meeting.status == 'ban'){
      // 예약 금지 시간인 경우 표시
      statusDisplay = "예약 불가";
      title = "예약 금지 시간";
      lessonType = '';
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Container(
            child: Text(
              '예약 정보',
              style: style.copyWith(color: PRIMARY_COLOR),
            ),
          ),
          content: SizedBox(
            height: 110,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 첫 번째 줄: 이벤트 이름 (수업 듣는 학생 이름)
                Row(
                  children: <Widget>[
                    Text(
                      title,
                      style: style.copyWith(fontSize: 20),
                    ),
                  ],
                ),
                // 날짜 표시
                Row(
                  children: <Widget>[
                    Text(
                      DateFormat('yyyy년 M월 dd일').format(meeting.from),
                      style: style.copyWith(fontSize: 15),
                    ),
                  ],
                ),
                // 시작/종료 시간 표시
                Row(
                  children: <Widget>[
                    Text(
                      '${meeting.from.hour.toString().padLeft(2, '0')}:${meeting.from.minute.toString().padLeft(2, '0')} '
                          '~ ${meeting.to.hour.toString().padLeft(2, '0')}:${meeting.to.minute.toString().padLeft(2, '0')}',
                      style: style.copyWith(fontSize: 15),
                    ),
                  ],
                ),
                // status가 confirmed가 아닐 때 보강수업 정보 표시
                // if (statusDisplay.isNotEmpty)
                Row(
                  children: <Widget>[
                    // 수업 변경 여부 표시 (정규 수업 / 변경된 수업)
                    Text(
                      lessonType,
                      style: style.copyWith(fontSize: 18, color: PRIMARY_COLOR),
                    ),
                    Text(
                      statusDisplay,
                      style: style.copyWith(fontSize: 18, color: Colors.red),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          actions: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    '닫기',
                    style: style.copyWith(color: PRIMARY_COLOR),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// `MeetingDataSource` → 캘린더 이벤트 데이터 소스
class MeetingDataSource extends CalendarDataSource {
  MeetingDataSource(List<Meeting> source) {
    appointments = source;
  }

  @override
  DateTime getStartTime(int index) => _getMeetingData(index).from;
  @override
  DateTime getEndTime(int index) => _getMeetingData(index).to;
  @override
  String getSubject(int index) => _getMeetingData(index).eventName;
  @override
  Color getColor(int index) => _getMeetingData(index).background;
  @override
  String status(int index) => _getMeetingData(index).status;
  @override
  bool isRescheduled(int index) => _getMeetingData(index).isRescheduled;

  Meeting _getMeetingData(int index) {
    final dynamic meeting = appointments![index];
    return meeting is Meeting ? meeting : Meeting('', DateTime.now(), DateTime.now(), PRIMARY_COLOR, "confirmed", false);
  }
}
// `Meeting` → 캘린더 일정 모델
class Meeting {
  Meeting(this.eventName, this.from, this.to, this.background, this.status , this.isRescheduled);
  String eventName;
  DateTime from;
  DateTime to;
  Color background;
  String status;
  bool isRescheduled;
}





