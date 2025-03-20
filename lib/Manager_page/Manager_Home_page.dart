import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Data/constant.dart';
import 'package:forestring_teacher_2/Data/schedule_model.dart';
import 'package:forestring_teacher_2/Data/student_model.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

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

class Manager_Home_page extends StatefulWidget {
  const Manager_Home_page({super.key});

  @override
  State<Manager_Home_page> createState() => _Manager_Home_page();
}
String Teachername = TeacherNameMap[AllTeacherList[0].id]!;
String Teacher = AllTeacherList[0].id;

class _Manager_Home_page extends State<Manager_Home_page> {
  DateTime selectedDate = DateTime.utc(
    //선택된 날짜를 관리할 변수
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime focusedDate = DateTime.now();
  DateTime tmp1 = DateTime(DateTime.now().year,DateTime.now().month,1).subtract(const Duration(days: 10));
  DateTime tmp2 = DateTime(DateTime.now().year,DateTime.now().month,20).add(const Duration(days: 60));

  List<ScheduleModel> TMP1 = [];
  List<ScheduleModel> TMP2 = [];


  @override
  void initState() {
    super.initState();
    // GETWorkHour(Teacher);
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
              await GETstudents(context);
              await GETschedule(context);
              await GETWorkHour(Teacher);
              Navigator.of(context).push(
                _createRoute(const Manager_Home_page()),
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
                    OutlinedButton(
                      onPressed: () => _showDialog(
                          CupertinoPicker.builder(
                            itemExtent: 30,
                            childCount: AllTeacherList.length,
                            onSelectedItemChanged: (i) async {
                              setState(() {
                                Teacher = AllTeacherList[i].id;
                                Teachername = AllTeacherList[i].name;
                              });
                              await GETstudents(context);
                              await GETschedule(context);
                              await GETWorkHour(Teacher);
                            },
                            itemBuilder: (context, index){
                              return Text('${AllTeacherList[index].name} 선생님',
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
                      child: Text('$Teachername 선생님 시간표',
                          style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20)
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: SfCalendar(
                    minDate: DateTime(tmp1.year,tmp1.month,1),
                    maxDate: DateTime(tmp2.year, tmp2.month, 1),
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
Future<void> GETWorkHour(String teacherID) async {
  bantime = [];
  BanTime = {};

  //선생님의 근무 시간을 불러와 저장해 주는 함수.
  DocumentReference<Map<String, dynamic>> DocumentRef =
  FirebaseFirestore.instance.collection('teacher').doc(teacherID);
  DocumentSnapshot<Map<String, dynamic>> DocumentSnap = await DocumentRef.get();

  var tmp = await FirebaseFirestore.instance
      .collection('teacher')
      .doc(teacherID)
      .collection('BanTime')
      .get();
  for (var doc in tmp.docs) {
    //벤타임 업데이트
    bantime.add(doc.id);
    BanTime.addAll({
      doc.id: [doc.data()['0'].toDate(), doc.data()['1'].toDate()]
    });
  }
  Map<String, dynamic>? doc = DocumentSnap.data();
  if (doc != null) {
    WorkTime = {
      'Mon': [doc['Mon'][0].toDate(), doc['Mon'][1].toDate()],
      'Tue': [doc['Tue'][0].toDate(), doc['Tue'][1].toDate()],
      'Wed': [doc['Wed'][0].toDate(), doc['Wed'][1].toDate()],
      'Thu': [doc['Thu'][0].toDate(), doc['Thu'][1].toDate()],
      'Fri': [doc['Fri'][0].toDate(), doc['Fri'][1].toDate()],
      'Sat': [doc['Sat'][0].toDate(), doc['Sat'][1].toDate()],
    };
  }
}

Future<void> GETstudents(BuildContext context) async {
  StudentList = [];
  AllStudentList = [];
  TextStyle style = const TextStyle(
      color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);
  try {
    var List = [];
    DocumentReference<Map<String, dynamic>> DocumentRef =
    FirebaseFirestore.instance.collection('teacher').doc(Teacher);
    DocumentSnapshot<Map<String, dynamic>> tmp = await DocumentRef.get();
    List = tmp.data()!['students'];
    // 특정 선생님의 학생 리스트를 저장함(id만 저장됨)

    CollectionReference<Map<String, dynamic>> CollectionRef =
    FirebaseFirestore.instance.collection('student');
    QuerySnapshot<Map<String, dynamic>> querySnap = await CollectionRef.get();

    for (var doc in querySnap.docs) {
      AllStudentList.add(StudentModel.fromJson(json: doc.data()));
      if(List.contains(doc.id)){
        StudentList.add(StudentModel.fromJson(json: doc.data()));
      }
    }
    // print('학생 리스트 길이 ${StudentList.length}');
    //선생님의 학생들 리스트 불러오기
  } catch (e) {
    print(e);
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Container(
                child: Text(
                  '오류',
                  style: style.copyWith(
                    color: PRIMARY_COLOR,
                    fontSize: 17,
                  ),
                  textAlign: TextAlign.center,
                )),
            content: Text('학생 정보를 불러오는 과정에서 오류가 발생했습니다',
                style: style.copyWith(fontSize: 15)),
          );
        });
  }
}

Future<void> GETschedule(BuildContext context) async {
  // 본인이 담당하는 학생들의 스케쥴을 모두 불러옴.
  Schedules = [];
  List<ScheduleModel> TmpClass1 = [];
  List<ScheduleModel> TmpClass2 = [];
  List<ScheduleModel> TmpClass3 = [];

  TextStyle style = const TextStyle(
      color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);
  try {
    for (int i = 0; i < StudentList.length; i++) {
      DocumentReference<Map<String, dynamic>> DocRef =
      FirebaseFirestore.instance.collection('Class').doc(StudentList[i].id);
      DocumentSnapshot<Map<String, dynamic>> tmp = await DocRef.get();
      for (var sche in tmp.data()!['class']) {
        TmpClass1.add(ScheduleModel(id: StudentList[i].id, name: StudentList[i].name, date: sche.toDate(), teacher: Teacher, rebook: false));
      }
      for (var shce in tmp.data()!['rebooked']) {
        if(shce.toDate().isAfter(semesterduration[thissemester[0]][0])){
          TmpClass2.add(ScheduleModel(id: StudentList[i].id, name: StudentList[i].name,
              date: shce.toDate(), teacher: Teacher, rebook: true));
        }

      }
      for (var shce in tmp.data()!['canceled']) {
        if(shce.toDate().isAfter(semesterduration[thissemester[0]][0])){
          TmpClass3.add(ScheduleModel(id: StudentList[i].id, name: StudentList[i].name,
              date: shce.toDate(), teacher: Teacher, rebook: false));
        }
      }
    }
  } catch (e) {
    print(e);
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Container(
                child: Text(
                  '오류',
                  style: style.copyWith(
                    color: PRIMARY_COLOR,
                    fontSize: 17,
                  ),
                  textAlign: TextAlign.center,
                )),
            content: Text('스케쥴을 불러오는데 오류가 발생했습니다',
                style: style.copyWith(fontSize: 15)),
          );
        });
  }
  Schedules = TmpClass1;
  Rebooked = TmpClass2;
  Canceled = TmpClass3;
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