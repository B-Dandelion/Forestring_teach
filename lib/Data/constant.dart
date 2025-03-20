import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Data/schedule_model.dart';
import 'package:forestring_teacher_2/Data/student_model.dart';
import 'package:forestring_teacher_2/Data/teacher_model.dart';
import 'package:forestring_teacher_2/Intro_page/Auth_page.dart';
import 'package:forestring_teacher_2/Main_page/Class_page.dart';
import 'package:forestring_teacher_2/Main_page/Home_page.dart';
import 'package:forestring_teacher_2/Main_page/Schedule_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:forestring_teacher_2/Manager_page/Manager_Home_page.dart';
import 'package:forestring_teacher_2/Manager_page/Schedule_Manage_page/Schedule_Manage_page.dart';
import 'package:forestring_teacher_2/Manager_page/Student_Manage_page/Student_Manage_page.dart';
import 'package:forestring_teacher_2/Manager_page/Teacher_Manage_page/Teacher_Manage_page.dart';

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

List<int> thissemester = [0,0,0];
Map<int, dynamic> semesterduration = {};

Map<String, dynamic> BanTime = {};
List<String> bantime = [];
Map<String, dynamic> WorkTime = {};

//스케쥴 정보와 바뀐 스케쥴, 취소한 스케쥴 리스트
List<ScheduleModel> Schedules = [];
List<ScheduleModel> Rebooked = [];
List<ScheduleModel> Canceled = [];

//담당하는 모든 학생들의 id 정보가 저장된 리스트.
List<StudentModel> StudentList = [];

//관리자 페이지용 변수
List<StudentModel> AllStudentList = [];
List<TeacherModel> AllTeacherList = [];
Map<String,String> TeacherNameMap = {};
Map<String,List> Semester1 = {};
Map<String,List> Semester2 = {};
Map<String,List> AllTeacherCount = {};

//스케쥴용 변수
List<ScheduleModel> AllScheduleList = [];
List<ScheduleModel> AllRebookedList = [];
List<ScheduleModel> AllCanceledList = [];


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
                  MaterialPageRoute(builder: (BuildContext context) => const Home_page()),
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
                _createRoute(const Schedule_page()),
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
                _createRoute(const Class_page()),
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
              Schedules = [];
              StudentList = [];
              Rebooked = [];
              Canceled = [];
              WorkTime = {};
              bantime = [];
              BanTime = {};

              //저장된 유저 이름과 pw 초기값 변경

              UserID = '';
              UserName = '';
              Userpw = '';

              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (BuildContext context) => const Auth_page()),
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
                  MaterialPageRoute(builder: (BuildContext context) => const Manager_Home_page()),
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
              await getallstudents();
              Navigator.of(context).push(
                _createRoute(const Student_Manage_page()),
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
                _createRoute(const Teacher_Manage_page()),
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
              await getallsemester();
              Navigator.of(context).push(
                _createRoute(const Schedule_Manage_page()),
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
              Schedules = [];
              StudentList = [];
              Rebooked = [];
              Canceled = [];
              WorkTime = {};
              bantime = [];
              BanTime = {};

              //저장된 유저 이름과 pw 초기값 변경

              UserID = '';
              UserName = '';
              Userpw = '';

              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (BuildContext context) => const Auth_page()),
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

Future<void> getMyModel() async {
  try {
    CollectionReference<Map<String, dynamic>> collectionReference =
    FirebaseFirestore.instance.collection('teacher');
    QuerySnapshot<Map<String, dynamic>> querySnapshot =
    await collectionReference.get();
    for (var doc in querySnapshot.docs) {
      if (UserID == doc.id) {
        UserName = doc.data()['name'];
      }
    }
    print('-- 메인 페이지 UserModel, 선생님 id, 성함, pw 저장됨 -- ');
  } catch (e) {
    print('-- 메인 페이지 UserModel 오류');
  }


}
Future<void> getWorkHour(String teacherID) async {
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
Future<void> semester() async {
  DateTime tmp1 = DateTime(DateTime.now().year, DateTime.now().month, 1)
      .subtract(const Duration(days: 15));
  DateTime tmp2 = DateTime(DateTime.now().year, DateTime.now().month, 28)
      .add(const Duration(days: 15));
  DateTime now = DateTime.now();

  //12월, 1월 사이에 걸친 경우를 위한 변수 선언
  DocumentSnapshot<Map<String, dynamic>> tmp = await FirebaseFirestore.instance
      .collection('Class')
      .doc(DateTime.now().year.toString())
      .get();
  DateTime TMP1 = tmp[DateTime.now().month.toString()][0].toDate();
  DateTime TMP2 = tmp[DateTime.now().month.toString()][1].toDate();
  int year = DateTime.now().year;

  //지금 시간 기준 이번 달 이 이번 학기인지 확인하기
  if (TMP2.isAfter(DateTime.now()) && TMP1.isBefore(DateTime.now())) {
    //이번 학기가 맞다
    thissemester[1] = DateTime.now().month;
  } else if (TMP1.isAfter(DateTime.now())) {
    //만약 지금 10월인데 아직 10월 학기가 아니다
    thissemester[1] = tmp1.month;
    now = tmp1;
    tmp1 = now.subtract(const Duration(days: 30));
    tmp2 = now.add(const Duration(days: 30));
  } else {
    //만약 지금 10월인데 10월 학기가 끝났다
    thissemester[1] = tmp2.month;
    now = tmp2;
    tmp1 = now.subtract(const Duration(days: 30));
    tmp2 = now.add(const Duration(days: 30));
  }
  thissemester[0] = tmp1.month;
  thissemester[2] = tmp2.month;

  tmp = await FirebaseFirestore.instance
      .collection('Class')
      .doc(now.year.toString())
      .get();
  semesterduration[thissemester[1]] = [
    tmp[thissemester[1].toString()][0].toDate(),
    tmp[thissemester[1].toString()][1].toDate(),
  ];

  tmp = await FirebaseFirestore.instance
      .collection('Class')
      .doc(tmp1.year.toString())
      .get();
  semesterduration[thissemester[0]] = [
    tmp[thissemester[0].toString()][0].toDate(),
    tmp[thissemester[0].toString()][1].toDate(),
  ];

  tmp = await FirebaseFirestore.instance
      .collection('Class')
      .doc(tmp2.year.toString())
      .get();
  semesterduration[thissemester[2]] = [
    tmp[thissemester[2].toString()][0].toDate(),
    tmp[thissemester[2].toString()][1].toDate(),
  ];
  // print('---------$thissemester------------');
  // print('---------${semesterduration[thissemester[0]][0]}------------');
}
Future<void> getstudents(BuildContext context) async {
  StudentList = [];
  TextStyle style = const TextStyle(
      color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);
  try {
    var List = [];
    DocumentReference<Map<String, dynamic>> DocumentRef =
    FirebaseFirestore.instance.collection('teacher').doc(UserID);
    DocumentSnapshot<Map<String, dynamic>> tmp = await DocumentRef.get();
    List = tmp.data()!['students'];

    CollectionReference<Map<String, dynamic>> CollectionRef =
    FirebaseFirestore.instance.collection('student');
    QuerySnapshot<Map<String, dynamic>> querySnap = await CollectionRef.get();

    for (var doc in querySnap.docs) {
      AllStudentList.add(StudentModel.fromJson(json: doc.data()));
      if(List.contains(doc.id)){
        StudentList.add(StudentModel.fromJson(json: doc.data()));
      }
    }


    print('학생 리스트 길이 ${StudentList.length}');
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
Future<void> getschedule(BuildContext context) async {
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
        TmpClass1.add(ScheduleModel(id: StudentList[i].id, name: StudentList[i].name, date: sche.toDate(), teacher: UserID, rebook: false));
      }
      for (var shce in tmp.data()!['rebooked']) {
        if(shce.toDate().isAfter(semesterduration[thissemester[0]][0])){
          TmpClass2.add(ScheduleModel(id: StudentList[i].id, name: StudentList[i].name,
              date: shce.toDate(), teacher: UserID, rebook: true));
        }

      }
      for (var shce in tmp.data()!['canceled']) {
        if(shce.toDate().isAfter(semesterduration[thissemester[0]][0])){
          TmpClass3.add(ScheduleModel(id: StudentList[i].id, name: StudentList[i].name,
              date: shce.toDate(), teacher: UserID, rebook: false));
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
Future<void> getallstudents() async {
  AllStudentList = [];
  try{
    CollectionReference<Map<String, dynamic>> CollectionRef =
    FirebaseFirestore.instance.collection('student');
    QuerySnapshot<Map<String, dynamic>> querySnap = await CollectionRef.get();
    for (var doc in querySnap.docs) {
      AllStudentList.add(StudentModel.fromJson(json: doc.data()));
    }
  } catch (e) {
    print('get all students 에서 발생한 오류 $e');
  }
}
Future<void> getallteachers() async {
  AllTeacherList = [];
  try {
    CollectionReference<Map<String, dynamic>> CollectionRef =
    FirebaseFirestore.instance.collection('teacher');
    QuerySnapshot<Map<String, dynamic>> querySnap = await CollectionRef.get();
    for (var doc in querySnap.docs) {
      AllTeacherList.add(TeacherModel.fromJson(json: doc.data()));
      TeacherNameMap.addAll({doc.id : TeacherModel.fromJson(json: doc.data()).name});
      AllTeacherCount.addAll({doc.id : [0,0,0]});
    }
  } catch (e){
    print('get all teachers 에서 발생한 오류 $e');
  }
}
Future<void> getallschedules() async {
  AllScheduleList = [];
  AllRebookedList = [];
  AllCanceledList = [];
  List<DateTime> TmpClass = [];
  try {
    for(int i=0;i<AllStudentList.length;i++){
      var tmp = AllStudentList[i];
      DocumentReference<Map<String, dynamic>> DocumentRef =
      FirebaseFirestore.instance.collection('Class').doc(tmp.id);
      DocumentSnapshot<Map<String, dynamic>> docSnap = await DocumentRef.get();
      for (var sche in docSnap.data()!['class']){
        if(sche.toDate().isBefore(semesterduration[thissemester[0]][0])){
          //이전 학기보다 더 과거의 수업은 자동 삭제됨
          print(sche.toDate());
        } else {
          AllScheduleList.add(ScheduleModel(id: tmp.id, name: tmp.name,
              date: sche.toDate(), teacher: tmp.teacherID, rebook: false));
          TmpClass.add(sche.toDate());
        }
      }
      TmpClass.sort((a,b) => a.compareTo(b));
      await FirebaseFirestore.instance.collection('Class').doc(tmp.id).update({'class': TmpClass});
      TmpClass = [];

      for (var sche in docSnap.data()!['rebooked']){
        if(sche.toDate().isBefore(semesterduration[thissemester[0]][0])){
          //이전 학기보다 더 과거의 수업은 자동 삭제됨
          print(sche.toDate());
        } else {
          AllRebookedList.add(ScheduleModel(id: tmp.id, name: tmp.name,
              date: sche.toDate(), teacher: tmp.teacherID, rebook: true));
          TmpClass.add(sche.toDate());
        }
      }
      TmpClass.sort((a,b) => a.compareTo(b));
      await FirebaseFirestore.instance.collection('Class').doc(tmp.id).update({'rebooked': TmpClass});
      TmpClass = [];
      for (var sche in docSnap.data()!['canceled']){
        if(sche.toDate().isBefore(semesterduration[thissemester[0]][0])){
          //이전 학기보다 더 과거의 수업은 자동 삭제됨
          print(sche.toDate());
        } else {
          AllCanceledList.add(ScheduleModel(id: tmp.id, name: tmp.name,
              date: sche.toDate(), teacher: tmp.teacherID, rebook: false));
          TmpClass.add(sche.toDate());
        }
        TmpClass.sort((a,b) => a.compareTo(b));
        await FirebaseFirestore.instance.collection('Class').doc(tmp.id).update({'canceled': TmpClass});
        TmpClass = [];
      }
    }
    AllScheduleList.sort((a,b) => a.date.compareTo(b.date));
    AllRebookedList.sort((a,b) => a.date.compareTo(b.date));
    AllCanceledList.sort((a,b) => a.date.compareTo(b.date));
    //모든 스케줄 리스트를 날짜 순으로 정렬합니다.
  } catch (e) {
    print('get all schedules 에서 발생한 오류 $e');
  }
}
Future<void> addschedule() async{
  // 현재 학기 마지막 주에 실행되는 함수.
  // 현재 학기 기준 다음 달까지 저장되어있음.
  // 만약 이미 저장되었다면 이 함수는 실행되지 않음.
  // 다다음 학기 수업 추가하기.
  DateTime semesterStartDate = semesterduration[thissemester[1]][1].add(const Duration(days: 1));
  //다다음 학기 기간 시작일 (일요일임. 확정적으로)

  List<DateTime> Holiday = [];
  List<DateTime> holiday = [];
  var ref = await FirebaseFirestore.instance.collection('Class')
      .doc(semesterStartDate.year.toString()).get();
  var snap = ref.data();
  Holiday = snap!['Holiday'];
  //휴일 정보를 저장합니다.

  for(int i=0;i<Holiday.length;i++){
    if(Holiday[i].isAfter(semesterStartDate) && Holiday[i].isBefore(semesterStartDate.add(const Duration(days: 50)))){
      holiday.add(Holiday[i]);
    }
  }
  //만약 다다음 학기에 휴원 기간이 있다면 휴원 기간 정보를 저장해줍니다.

  for(int i=0;i<AllStudentList.length;i++){
    List<DateTime> newscheduleList = [];
    //추가할 수업을 저장할 변수.
    DateTime tempDate = semesterStartDate;
    //루프를 돌 날짜 변수.

    //모든 학생을 대상으로,
    var tmp = AllStudentList[i];
    DocumentReference<Map<String, dynamic>> DocumentRef =
    FirebaseFirestore.instance.collection('Class').doc(tmp.id);
    DocumentSnapshot<Map<String, dynamic>> docSnap = await DocumentRef.get();
    var tmplist = docSnap.data()!['class'];
    //학생의 정규 수업 정보 리스트.
    int classDay = tmplist[0].weekday;
    //정규 수업 요일 반환. (예: 월요일 = 1, 일요일 = 7)
    tempDate = tempDate.add(Duration(days: classDay));
    //루프의 시작점을 지정합니다.
    while(newscheduleList.length < 4){
      if(holiday.isNotEmpty){
        if(tempDate.isAfter(holiday[0]) && tempDate.isBefore(holiday[0].add(const Duration(days: 8)))){
          //휴원 기간에 걸린다면
          //그냥 패스
          //왜 7일이 아니라 8일임 ? 시간이 오전 12시로 되어있기 때문임.
        }else {
          newscheduleList.add(tempDate);
          tempDate.add(const Duration(days: 7));
        }
      }else{
        newscheduleList.add(tempDate);
        tempDate.add(const Duration(days: 7));
      }
    }
    tmplist.addAll(tempDate);
    //새로운 리스트를 저장해줍니다.
  }
}
Future<void> getallsemester() async {
  try {
    //학기 정보 저장할 리스트 생성, 그리고 저장.
    Semester1 = {};
    Semester2 = {};

    var tmp = await FirebaseFirestore.instance.collection('Class')
        .doc(DateTime.now().year.toString()).get();
    var snap = tmp.data();
    for(int i=1;i<13;i++){
      Semester1.addAll({i.toString(): [snap![i.toString()][0], snap[i.toString()][1]]});
    }
    tmp = await FirebaseFirestore.instance.collection('Class')
        .doc((DateTime.now().year + 1).toString()).get();
    snap = tmp.data();
    for(int i=1;i<13;i++){
      Semester2.addAll({i.toString(): [snap![i.toString()][0], snap[i.toString()][1]]});
    }
  } catch (e) {
    print('get all semester 에서 발생한 오류 $e');
  }
}
Future<void> getallcount() async {
  int tmp = 0;
  for(int i=0;i<AllScheduleList.length;i++){
    if(AllScheduleList[i].date.isAfter(semesterduration[thissemester[1]][0]) &&
        AllScheduleList[i].date.isBefore(semesterduration[thissemester[1]][1])
    ){ // 현재 학기다
      AllTeacherCount[AllScheduleList[i].teacher]![1] += 1;
    }else if (AllScheduleList[i].date.isAfter(semesterduration[thissemester[0]][0]) &&
        AllScheduleList[i].date.isBefore(semesterduration[thissemester[0]][1])){
      //저번 학기다
      AllTeacherCount[AllScheduleList[i].teacher]![0] += 1;
    } else if (AllScheduleList[i].date.isAfter(semesterduration[thissemester[2]][0]) &&
        AllScheduleList[i].date.isBefore(semesterduration[thissemester[2]][1])){
      // 다음 학기당
      AllTeacherCount[AllScheduleList[i].teacher]![2] += 1;
    }
  }
  for(int i=0;i<AllRebookedList.length;i++){
    if(AllRebookedList[i].date.isAfter(semesterduration[thissemester[1]][0]) &&
        AllRebookedList[i].date.isBefore(semesterduration[thissemester[1]][1])
    ){ // 현재 학기다
      AllTeacherCount[AllRebookedList[i].teacher]![1] += 1;
    }else if (AllRebookedList[i].date.isAfter(semesterduration[thissemester[0]][0]) &&
        AllRebookedList[i].date.isBefore(semesterduration[thissemester[0]][1])){
      //저번 학기다
      AllTeacherCount[AllRebookedList[i].teacher]![0] += 1;
    } else if (AllRebookedList[i].date.isAfter(semesterduration[thissemester[2]][0]) &&
        AllRebookedList[i].date.isBefore(semesterduration[thissemester[2]][1])){
      // 다음 학기당
      AllTeacherCount[AllRebookedList[i].teacher]![2] += 1;
    }
  }
}

