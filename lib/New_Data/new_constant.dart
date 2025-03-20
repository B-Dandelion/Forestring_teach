import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:forestring_teacher_2/New_Data/lessonClass.dart';
import 'package:forestring_teacher_2/New_Data/studentClass.dart';
import 'package:forestring_teacher_2/New_Data/teacherClass.dart';
import 'package:forestring_teacher_2/New_Intro_page/New_Auth_page.dart';
import 'package:forestring_teacher_2/New_Main_page/New_Class_page.dart';
import 'package:forestring_teacher_2/New_Main_page/New_Home_page.dart';
import 'package:forestring_teacher_2/New_Main_page/New_Schedule_page.dart';
import 'package:forestring_teacher_2/New_Manager_page/New_Manager_Home_page.dart';
import 'package:forestring_teacher_2/New_Manager_page/New_Schedule_Manage_page/New_shcedule_manage_page.dart';
import 'package:forestring_teacher_2/New_Manager_page/New_Student_Manage_page/New_student_manage_page.dart';
import 'package:forestring_teacher_2/New_Manager_page/New_Teacher_Manage_page/New_Teacher_Manage_page.dart';
import 'package:intl/intl.dart'
;

const Color_list = [
  Color(0xff005647),Color(0xff007581),
  Color(0xff23288C), Color(0xff296CF2),
  Color(0xff343BBF), Color(0xff4A88D9),
  Color(0xff0092bd), Color(0xffB8D3D9),
  Color(0xff5eabf0), Color(0xffA0A4F2),
  Color(0xff54823b), Color(0xffbcd15e),
  Color(0xff003654), Color(0xff006586),
  Color(0xff24a558), Color(0xfff9f871),];

const PRIMARY_COLOR = Color(0xff003717);
const SECONDARY_COLOR = Color(0xff708C7A);
const IBORY = Color(0xffFDF8E7);
const ERROR_COLOR = Colors.red;
const TEXT_FIELD_FILL_COLOR = Colors.black;


TextStyle style = const TextStyle(
    color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);

String UserID = '';
String UserName = '';
String Userpw = '';
Map<String, String> StudentName = {};
TeacherClass User = TeacherClass(id: 'id', name: 'name', role: 'teacher', password: 'password1111',
    studentList: [], workTime: [], classList: []);
List<Lesson> LessonList = [];
// 나의 수업 리스트를 저장하고 있는 리스트입니다.

//현실 날짜
DateTime now = DateTime.now();
DateTime previousMonth = DateTime(now.year, now.month - 1, now.day);
DateTime nextMonth = DateTime(now.year, now.month + 1, now.day);

//학기 날짜
DateTime nowsemester = now;
DateTime previoussemester = previousMonth;
DateTime nextsemester = nextMonth;

Map<int, dynamic> SemesterTerm = {};

// 관리자 위한 List 선언
List<StudentClass> Allstudents = [];
List<TeacherClass> Allteachers = [];
List<Lesson> Alllessons = [];
Map<String,int> Allcount1 = {};
Map<String,int> Allcount2 = {};
Map<String,int> Allcount3 = {};

//일반 선생님 위한 function
Future<void> MyModel() async {
  DocumentReference<Map<String, dynamic>> DocumentRef =
  FirebaseFirestore.instance.collection('User').doc(UserID);
  DocumentSnapshot<Map<String, dynamic>> DocumentSnap = await DocumentRef.get();

  if (DocumentSnap.exists) {
    // 데이터를 JSON으로 가져와서 User 객체로 변환
    User = TeacherClass.fromJson(json: DocumentSnap.data()!);
    QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore.instance.collection('User').get();
    for (var doc in snapshot.docs) {
      if (User.studentList.contains(doc.id)) {
        StudentName[doc.id] = doc['name'];
      }
    }
  } else {
    print('선생님 문서가 존재하지 않거나 형식이 잘못되었습니다');
  }
  print('TeacherModel function done');
}
Future<void> fetchSemesterInfo() async {
  // 현재 학기 데이터 가져오기
  var currentData = await _getSemesterData(now.year, now.month);
  if (currentData != null) {
    SemesterTerm[now.month] = [currentData[0], currentData[1]];
  }
  // 현재 학기 판별
  if (SemesterTerm[now.month][0] != null &&
      SemesterTerm[now.month][1] != null &&
      SemesterTerm[now.month][0].isBefore(now) &&
      SemesterTerm[now.month][1].isAfter(now)) {
    // 현재 학기 유지
  } else if (SemesterTerm[now.month][0] != null && now.isBefore(SemesterTerm[now.month][0])) {
    previoussemester = DateTime(previousMonth.year, previousMonth.month - 1);
    nowsemester = previousMonth;
    nextsemester = now;
  } else {
    nextsemester = DateTime(nextMonth.year, nextMonth.month + 1);
    nowsemester = nextMonth;
    previoussemester = now;
  }
  var nowData = await _getSemesterData(nowsemester.year, nowsemester.month);
  if (nowData != null) {
    SemesterTerm[nowsemester.month] = [nowData[0], nowData[1]];
  }
  var previousData = await _getSemesterData(previoussemester.year, previoussemester.month);
  if (previousData != null) {
    SemesterTerm[previoussemester.month] = [previousData[0], previousData[1]];
  }
  var nextData = await _getSemesterData(nextsemester.year, nextsemester.month);
  if (nextData != null) {
    SemesterTerm[nextsemester.month] = [nextData[0], nextData[1]];
  }
  print('Semester function Completed');
}
Future<List<DateTime>?> _getSemesterData(int year, int month) async {
  try {
    DocumentSnapshot<Map<String, dynamic>> snapshot =
    await FirebaseFirestore.instance.collection('Class').doc(year.toString()).get();

    if (snapshot.exists && snapshot.data()?[month.toString()] != null) {
      var dates = snapshot.data()![month.toString()];
      return [dates[0].toDate(), dates[1].toDate()];
    }
  } catch (e) {
    print("Error fetching semester data: $e");
  }
  return null;
}
Future<void> GetLesson() async {
  LessonList = [];
  QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore.instance.collection('Class').get();
  for (var doc in snapshot.docs){
    if (User.classList.contains(doc.id)) {
      // 수업 ID가 classList에 포함되어 있으면, 해당 수업의 데이터를 Lesson 객체로 변환하여 추가
      Lesson lesson = Lesson.fromJson(
        json: doc.data(), // Firestore에서 가져온 데이터
        id: doc.id // 외부에서 doc.id를 id로 지정
      );
      LessonList.add(lesson);
    }
  }
  print('Length of my Lesson List : ${LessonList.length}');
  print('GetLesson function completed');
}

// 관리자를 위한 function
Future<void> AllUsers() async {
  Allstudents = [];
  Allteachers = [];
  QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore.instance.collection('User').get();
  //모든 유저를 불러와 선생님과 학생을 나누어 리스트에 저장
  for (var doc in snapshot.docs) {
    String docId = doc.id;
    // doc.id가 "STU"로 시작하면 StudentClass 객체로 Allstudents에 추가
    if (docId.startsWith('STU')) {
      StudentClass studentClass = StudentClass.fromJson(json: doc.data());
      Allstudents.add(studentClass);
    }
    // doc.id가 "TEACHER"로 시작하면 TeacherClass 객체로 Allteachers에 추가
    else if (docId.startsWith('TEACHER')) {
      TeacherClass teacherClass = TeacherClass.fromJson(json: doc.data());
      Allteachers.add(teacherClass);
    }
    // 그 외의 경우는 무시
  }
  print('AllUsers 함수 실행 완료');
  print('Allstudents 길이 ${Allstudents.length}');
  print('Allteachers 길이 ${Allteachers.length}');
}
Future<void> Alllesson() async {
  Alllessons = [];
  QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore.instance.collection('Class').get();
  // 각 문서를 순회하며, ID가 13글자 이상인 문서만 리스트에 추가
  for (var doc in snapshot.docs) {
    String docId = doc.id;
    if (docId.length >= 13) { // 문서 ID가 13글자 이상이면 리스트에 추가
      Lesson lesson = Lesson.fromJson(
        json: doc.data(), // Firestore에서 가져온 데이터
        id: doc.id, // 외부에서 doc.id를 id로 지정
      );
      Alllessons.add(lesson); // 또는 doc.id와 함께 저장 가능
    }
  }
  print('AllLesson 함수 실행 완료');
  print('Alllessons 길이 ${Alllessons.length}');
}

// 기본 위젯

class BaseAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BaseAppBar(
      {super.key,
        required this.appBar,
        required this.title,
        this.center = true});

  final AppBar appBar;
  final String title;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: PRIMARY_COLOR,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Text(
        title,
        style: const TextStyle(
            color: Colors.white,
            fontFamily: 'OpenSans',
            fontWeight: FontWeight.w500,
            fontSize: 20),
      ),
      centerTitle: true,
      elevation: 0.0, //앱바 밑에 그림자
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(appBar.preferredSize.height);
}
class BaseDrawer extends StatelessWidget {
  const BaseDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              '$UserName 선생님',
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'ELAND',
                  fontWeight: FontWeight.w300,
                  fontSize: 25),
            ),
            accountEmail: const Text(
              '환영합니다',
              style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'OpenSans',
                  fontWeight: FontWeight.w300,
                  fontSize: 15),
            ),
            decoration: const BoxDecoration(
                color: PRIMARY_COLOR,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(10.0),
                  bottomRight: Radius.circular(10.0),
                )),
          ),
          ListTile(
            leading: const Icon(Icons.house),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '메인페이지',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (BuildContext context) => const New_Home_page()),
                      (route) => false);
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_rounded),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '주간 일정 확인하기',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              Navigator.of(context).push(
                _createRoute(const New_Schedule_page()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.account_circle),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '마이페이지',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              Navigator.of(context).push(
                _createRoute(const New_Class_page()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '로그아웃',
              style: TextStyle(
                color: Colors.red,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              //delete 함수를 통해 key 이름이 login 인것을 완전히 폐기.
              //다음 로그인 시에는 정보가 없어 정보를 불러올 수가 없게 된다.
              const FlutterSecureStorage().delete(key: "id");
              const FlutterSecureStorage().delete(key: "pw");


              //저장된 유저 이름과 pw 초기값 변경

              UserID = '';
              UserName = '';
              Userpw = '';

              StudentName = {};
              User = TeacherClass(id: 'id', name: 'name', role: 'teacher', password: 'password1111',
                  studentList: [], workTime: [], classList: []);
              LessonList = []; // 나의 수업 리스트를 저장하고 있는 리스트입니다
              SemesterTerm = {};
              // 관리자 위한 List 선언
              Allstudents = [];
              Allteachers = [];
              Alllessons = [];

              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (BuildContext context) => const New_Auth_page()),
                      (route) => false);
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          )
        ],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class ManagerDrawer extends StatelessWidget {
  const ManagerDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const UserAccountsDrawerHeader(
            accountName: Text(
              '김진아 선생님',
              style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'ELAND',
                  fontWeight: FontWeight.w300,
                  fontSize: 25),
            ),
            accountEmail: Text(
                '\u{1F49A}'),
            decoration: BoxDecoration(
                color: PRIMARY_COLOR,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(10.0),
                  bottomRight: Radius.circular(10.0),
                )),
          ),
          ListTile(
            leading: const Icon(Icons.house),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '메인페이지',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (BuildContext context) => const New_Manager_Home_page()),
                      (route) => false);
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.contact_mail),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '학생 관리 페이지',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () async {
              Navigator.of(context).push(
                _createRoute(const New_Student_Manage_page()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.school),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '선생님 관리 페이지',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              Navigator.of(context).push(
                _createRoute(const New_Teacher_Manage_page()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.today),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '수업 관리 페이지',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () async {
              Navigator.of(context).push(
                _createRoute(const New_Schedule_Manage_page()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '로그아웃',
              style: TextStyle(
                color: Colors.red,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              //delete 함수를 통해 key 이름이 login 인것을 완전히 폐기.
              //다음 로그인 시에는 정보가 없어 정보를 불러올 수가 없게 된다.
              const FlutterSecureStorage().delete(key: "id");
              const FlutterSecureStorage().delete(key: "pw");

              //일정 데이터, 학생 리스트 전부 초기값으로 변경

              //저장된 유저 이름과 pw 초기값 변경

              UserID = '';
              UserName = '';
              Userpw = '';
              StudentName = {};
              User = TeacherClass(id: 'id', name: 'name', role: 'teacher', password: 'password1111',
                  studentList: [], workTime: [], classList: []);
              LessonList = [];
              Allstudents = [];
              Allteachers = [];
              Alllessons = [];
              Allcount1 = {};
              Allcount2 = {};
              Allcount3 = {};

              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (BuildContext context) => const New_Auth_page()),
                      (route) => false);
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          )
        ],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TodayBanner extends StatelessWidget {
  final DateTime selectedDate;
  final int count;
  // final int count;

  const TodayBanner({
    required this.selectedDate,
    required this.count,
    // required this.count,
    super.key
  });



  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
        fontFamily: 'ELAND',
        fontWeight: FontWeight.w300,
        color: Colors.white
    );

    String e = '';
    if(selectedDate.isAfter(DateTime.now())){
      e = '예약된 수업';
    }else if(DateFormat('yyyyMMdd').format(selectedDate) == DateFormat('yyyyMMdd').format(DateTime.now())){
      e = '오늘 수업';
    }else{
      e = '완료된 수업';
    }
    return Container(
        color: PRIMARY_COLOR,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${selectedDate.year}년 ${selectedDate.month}월 ${selectedDate.day}일',
                  style: textStyle,
                ),

                Text(
                  '$e $count개',
                  style: textStyle,
                )
              ],
            )
        )
    );
  }
}

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