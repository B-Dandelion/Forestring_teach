import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

class Manage extends StatefulWidget {
  const Manage({super.key});

  @override
  State<Manage> createState() => _Manage();
}

class _Manage extends State<Manage> {
  String selectedTeacherId = ""; // 선택된 선생님 ID
  String selectedTeacherName = ""; // 선택된 선생님 이름
  DateTime selectedDate = DateTime.utc(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime focusedDate = DateTime.now();
  DateTime tmp1 = DateTime(2024, 1, 1);
  DateTime tmp2 = DateTime(2030, 12, 31);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final provider = Provider.of<MasterProvider>(context, listen: false);
      if (provider.teachers.isNotEmpty) {
        setState(() {
          selectedTeacherId = provider.teachers[0]['id'];
          selectedTeacherName = provider.teachers[0]['name'];
        });
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MasterProvider>(context);
    final schedules = provider.bookedSlots[selectedTeacherId] ?? {};

    return Scaffold(
      appBar: ManagerAppBar(
        appBar: AppBar(),
        selectedTeacherId: selectedTeacherId, // 현재 선택된 선생님 ID 전달
        onTeacherChanged: (newTeacherId) { // 선생님 변경 시 실행될 콜백 함수
          setState(() {
            selectedTeacherId = newTeacherId;
            selectedTeacherName = provider.teachers.firstWhere((t) => t['id'] == newTeacherId)['name'];
          });
        },
      ),
      drawer: const ManagerDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
            await provider.fetchUsers();
            await provider.fetchAllAvailableSlots();
            await provider.fetchLessons();
            },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              // 스케줄 캘린더
              Expanded(
                child: SfCalendar(
                  minDate: tmp1,
                  maxDate: tmp2,
                  timeZone: 'Korea Standard Time',
                  specialRegions: _getTimeRegions(context,selectedTeacherId),
                  view: CalendarView.week,
                  cellBorderColor: Colors.black12,
                  todayHighlightColor: PRIMARY_COLOR,
                  showNavigationArrow: true,
                  cellEndPadding: 0,
                  dataSource: MeetingDataSource(_getMeetings(schedules)),
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
                  onTap: (CalendarTapDetails details) {
                    if (details.appointments != null && details.appointments!.isNotEmpty) {
                      _showBookingDialog(context, details);
                    }
                  },
                  headerStyle: const CalendarHeaderStyle(
                    backgroundColor: Colors.transparent,
                    textAlign: TextAlign.center,
                    textStyle: TextStyle(
                      fontFamily: 'OpenSans',
                      fontWeight: FontWeight.w500,
                      fontSize: 20.0,
                    ),
                  ),
                ),
              ),
            ],
          )
        ),
      ),
    );
  }

  // 캘린더에 표시할 예약된 슬롯 변환
  List<Meeting> _getMeetings(Map<String, Map<String, dynamic>> schedules) {
    final List<Meeting> meetings = <Meeting>[];
    final provider = Provider.of<MasterProvider>(context, listen: false);

    // 학생 리스트를 Map으로 변환 (id -> name 매칭)
    final Map<String, String> studentNames = {
      for (var student in provider.students) student['id']: student['name']
    };

    for (var entry in schedules.entries) {
      Map<String, dynamic> lesson = entry.value;

      String status = lesson['status'];
      if (status == "canceled") continue; // 취소된 수업은 스킵

      DateTime startTime = lesson["date"];
      DateTime endTime = startTime.add(Duration(minutes: lesson["duration"]));
      bool isRescheduled = lesson['isRescheduled'];

      // 학생 이름 조회 (없으면 기본값 "알 수 없음")
      String studentName = studentNames[lesson["studentId"]] ?? "알 수 없음";

      // 상태에 따른 색상 설정
      Color lessonColor = PRIMARY_COLOR;
      if (status == 'ban') {
        studentName = 'X';
        lessonColor = Colors.black54;
      } else if (isRescheduled) {
        lessonColor = Color(0xff708C7A);
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
  List<TimeRegion> _getTimeRegions(BuildContext context, String teacherId) {
    final provider = Provider.of<MasterProvider>(context, listen: false);
    List<TimeRegion> regions = [];

    if (!provider.workSchedule.containsKey(teacherId)) return regions; // 근무 일정이 없으면 빈 리스트 반환

    var workSchedule = provider.workSchedule[teacherId];

    for (var day in workSchedule!.keys) {
      var slot = workSchedule[day];
      if (slot != null && slot["startTime"] != null && slot["endTime"] != null) {
        DateTime startTime = DateTime(
            2024, 1, 1,
            int.parse(slot["startTime"].split(":")[0]),
            int.parse(slot["startTime"].split(":")[1])
        );
        DateTime endTime = DateTime(
            2024, 1, 1,
            int.parse(slot["endTime"].split(":")[0]),
            int.parse(slot["endTime"].split(":")[1])
        );

        regions.add(TimeRegion(
          startTime: startTime,
          endTime: endTime,
          recurrenceRule: 'FREQ=WEEKLY;BYDAY=$day', // Firestore에서 가져온 요일 그대로 사용!
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

    // status가 confirmed이면 아무 것도 표시하지 않고, makeup이면 보강수업 표시
    if (meeting.status == 'makeup') {
      statusDisplay = " 보강 수업";
    } else if (meeting.status == 'ban'){
      // 예약 금지 시간인 경우 표시
      statusDisplay = " 예약 불가";
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
// 캘린더 데이터 소스 (예약된 수업을 캘린더에 표시)
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

  Meeting _getMeetingData(int index) => appointments![index] as Meeting;
}

// 예약된 수업 모델
class Meeting {
  Meeting(this.eventName, this.from, this.to, this.background, this.status , this.isRescheduled);
  String eventName;
  DateTime from;
  DateTime to;
  Color background;
  String status;
  bool isRescheduled;
}