import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:forestring_teacher_2/ver2/Login.dart';
import 'package:forestring_teacher_2/ver2/Master/Manage.dart';
import 'package:forestring_teacher_2/ver2/Master/Schedules/ScheduleM.dart';
import 'package:forestring_teacher_2/ver2/Master/Setting/Menu.dart';
import 'package:forestring_teacher_2/ver2/Master/Students/StudentM.dart';
import 'package:forestring_teacher_2/ver2/Master/Teachers/TeacherM.dart';
import 'package:forestring_teacher_2/ver2/Teacher/Home.dart';
import 'package:forestring_teacher_2/ver2/Teacher/WeekSchedule.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color_list = [
  Color(0xff23288C),
  Color(0xff296CF2),
  Color(0xff343BBF),
  Color(0xff4A88D9),
  Color(0xff0092bd),
  Color(0xffB8D3D9),
  Color(0xff5eabf0),
  Color(0xffA0A4F2),
  Color(0xff54823b),
  Color(0xffbcd15e),
  Color(0xff003654),
  Color(0xff006586),
  Color(0xff24a558),
  Color(0xfff9f871),
  Color(0xff005647),
  Color(0xff007581),
  // 블루 계열 (짙은 파랑, 네이비, 코발트 블루)
  Color(0xff1A237E), // Deep Indigo
  Color(0xff0D47A1), // Dark Blue
  Color(0xff1976D2), // Bright Cobalt
  Color(0xff64B5F6), // Soft Sky Blue
  Color(0xff1565C0), // Ocean Blue

// 시안 & 아쿠아 계열 (청록, 밝은 블루그린)
  Color(0xff00838F), // Deep Teal
  Color(0xff00ACC1), // Bright Aqua
  Color(0xff26C6DA), // Light Cyan Blue
  Color(0xff80DEEA), // Soft Pastel Cyan
  Color(0xff4DD0E1), // Vibrant Cyan

// 그린 계열 (딥 그린, 라임, 올리브)
  Color(0xff2E7D32), // Deep Forest Green
  Color(0xff388E3C), // Bright Green
  Color(0xff66BB6A), // Fresh Leaf Green
  Color(0xff9CCC65), // Soft Lime Green
  Color(0xffC5E1A5), // Pale Green

// 옐로우 & 라임 (포인트 컬러)
  Color(0xffFDD835), // Bright Yellow
  Color(0xffFFEB3B), // Lemon Yellow
  Color(0xffCDDC39), // Lime Yellow
  Color(0xffF4FF81), // Light Lime
  Color(0xffE6EE9C), // Pastel Lime
];
const Colors_list = [
  Color(0xff296CF2),
  Color(0xff006586),
  Color(0xffC5E1A5),
  Color(0xff0D47A1),
  Color(0xffF4FF81),
  Color(0xfff9f871),
  Color(0xff00838F),
  Color(0xff1976D2),
  Color(0xff5eabf0),
  Color(0xffE6EE9C),
  Color(0xff343BBF),
  Color(0xff23288C),
  Color(0xff4DD0E1),
  Color(0xff54823b),
  Color(0xffB8D3D9),
  Color(0xff388E3C),
  Color(0xff4A88D9),
  Color(0xff007581),
  Color(0xff66BB6A),
  Color(0xff003654),
  Color(0xffCDDC39),
  Color(0xff26C6DA),
  Color(0xff64B5F6),
  Color(0xff24a558),
  Color(0xffbcd15e),
  Color(0xffFFEB3B),
  Color(0xff2E7D32),
  Color(0xffFDD835),
  Color(0xff00ACC1),
  Color(0xff0092bd),
  Color(0xff80DEEA),
  Color(0xff9CCC65),
  Color(0xff005647),
  Color(0xff1A237E),
  Color(0xffA0A4F2),
  Color(0xff1565C0)
];

const PRIMARY_COLOR = Color(0xff003717);
const SECONDARY_COLOR = Color(0xff708C7A);
const IBORY = Color(0xffFDF8E7);
const ERROR_COLOR = Colors.red;
const TEXT_FIELD_FILL_COLOR = Colors.black;
//  아이보리 컬러 추천
const IVORY_COLOR = Color(0xffF5F1E8); // 기본 부드러운 아이보리
const WARM_IVORY = Color(0xffFAF3DD); // 따뜻한 느낌 (노란빛)
const COOL_IVORY = Color(0xffEDEAE0); // 차분한 느낌 (중립)
const NEUTRAL_IVORY = Color(0xffF2F3EE); // 뉴트럴한 크림톤
const PALE_IVORY = Color(0xffF6F5EC); // 좀 더 밝고 부드러운 아이보리

TextStyle style = const TextStyle(
    color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);

// (일반 선생님 / 마스터 모두 사용) User Provider
class UserProvider extends ChangeNotifier {
  String _userID = '';
  String _userName = '';
  String _userPw = '';
  String _role = '';

  Map<String, String> _studentNames = {};
  Map<String, List<Map<String, dynamic>>> _studentSchedules = {};
  StreamSubscription? _studentScheduleSubscription;
  Map<String, String> _archivedStudents = {};
  StreamSubscription? _fcmSubscription;

  String get userID => _userID;
  String get userName => _userName;
  String get userPw => _userPw;
  String get role => _role;
  Map<String, String> get studentNames => _studentNames;
  Map<String, List<Map<String, dynamic>>> get studentSchedules => _studentSchedules;
  Map<String, String> get archivedStudents => _archivedStudents; // 삭제된 학생 ID → 이름

  // 마스터일 경우 아이디, 이름, 비번, 역할만 저장.
  // 선생님일 경우 담당 학생들의 이름과 정규 수업 정보(실시간 탐지)를 불러온다.
  Future<void> setUser(String id, String name, String pw, String role) async {
    _userID = id;
    _userName = name;
    _userPw = pw;
    _role = role;

    // 선생님일 경우 학생 목록도 가져옴
    if (role == "teacher") {
      await fetchStudentNames();
      listenToStudentSchedules();
    }
    notifyListeners();
  }

  // Firestore에서 현재 선생님이 담당하는 학생들 불러오기(이름 + 수업 정보)
  Future<void> fetchStudentNames() async {
    try {
      FirebaseFirestore firestore = FirebaseFirestore.instance;
      QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
          .collection('users')
          .where('teacherId', isEqualTo: _userID)  // 현재 로그인한 선생님이 담당하는 학생만 가져옴
          .get();

      Map<String, String> newStudentNames = {};
      Map<String, List<Map<String, dynamic>>> newStudentSchedules = {}; // 학생 ID → weeklySchedule 저장

      for (var doc in snapshot.docs) {
        newStudentNames[doc.id] = doc['name'];
        String studentId = doc.id;
        List<dynamic> weeklySchedule = doc['weeklySchedule'] ?? []; // weeklySchedule이 없을 수도 있으니 기본값 설정
        newStudentSchedules[studentId] = List<Map<String, dynamic>>.from(weeklySchedule);
      }

      _studentSchedules = newStudentSchedules;
      _studentNames = newStudentNames;
      notifyListeners();
      print("학생 정보 불러오기 완료: $_studentNames");
    } catch (e) {
      print("학생 정보 불러오기 중 오류 발생: $e");
    }
  }

  // 탈퇴한 학생 정보 불러오기
  Future<void> fetchArchivedStudents() async {
    try {
      FirebaseFirestore firestore = FirebaseFirestore.instance;
      QuerySnapshot snapshot = await firestore.collection('archivedUsers').get();

      _archivedStudents = {
        for (var doc in snapshot.docs)
          if ((doc.data() as Map)['role'] == 'student')  // 학생 정보만 불러옴!
            doc.id: (doc.data() as Map)['name'] ?? "알 수 없음"
      };
      notifyListeners(); // UI 업데이트
    } catch (e) {
      print("아카이브된 정보 불러오기 실패: $e");
    }
  }

  // 학생 아이디 입력시 학생 + 탈퇴한 학생 아이디 전부 확인 후 이름을 각 상태에 맞게 변환
  String displayStudentName(String id) {
    if (_archivedStudents.containsKey(id)) return '${_archivedStudents[id]}(탈퇴)';
    if (_studentNames.containsKey(id)) return _studentNames[id]!;
    return '알 수 없음';
  }

  // void listenToFcmTokenChanges(BuildContext context) async {
  //   final token = await FirebaseMessaging.instance.getToken();
  //   if (token == null || _userID.isEmpty) return;
  //
  //   _fcmSubscription = FirebaseFirestore.instance
  //       .collection('users')
  //       .doc(_userID)
  //       .snapshots()
  //       .listen((snapshot) {
  //     if (!snapshot.exists) return;
  //
  //     final data = snapshot.data()!;
  //     final dynamic storedToken = data['fcmToken'];
  //
  //     bool shouldLogout = false;
  //
  //     if (_role == 'master') {
  //       // 마스터 계정은 토큰 배열임
  //       if (storedToken is List) {
  //         if (!storedToken.contains(token)) {
  //           shouldLogout = true;
  //         }
  //       } else {
  //         // 혹시라도 단일 문자열로 잘못 저장된 경우
  //         shouldLogout = true;
  //       }
  //     } else {
  //       // 일반 선생님은 단일 토큰
  //       if (storedToken is String) {
  //         if (storedToken != token) {
  //           shouldLogout = true;
  //         }
  //       } else {
  //         shouldLogout = true;
  //       }
  //     }
  //
  //     if (shouldLogout) {
  //       showDialog(
  //         context: context,
  //         barrierDismissible: false,
  //         builder: (_) => AlertDialog(
  //           title: const Text("로그아웃 안내"),
  //           content: const Text("다른 기기에서 로그인되어 자동 로그아웃되었습니다."),
  //           actions: [
  //             TextButton(
  //               onPressed: () {
  //                 clearUser();
  //                 Navigator.of(context).pushAndRemoveUntil(
  //                   MaterialPageRoute(builder: (_) => const Login()),
  //                       (route) => false,
  //                 );
  //               },
  //               child: const Text("확인"),
  //             )
  //           ],
  //         ),
  //       );
  //     }
  //   });
  // }

  void listenToStudentSchedules() {
    FirebaseFirestore firestore = FirebaseFirestore.instance;

    _studentScheduleSubscription = firestore
        .collection('users')
        .where('teacherId', isEqualTo: _userID) // 현재 로그인한 선생님이 담당하는 학생만 추적
        .snapshots()
        .listen((snapshot) {
      Map<String, List<Map<String, dynamic>>> updatedSchedules = {};
      Map<String, String> updatedNames = {};

      for (var doc in snapshot.docs) {
        String studentId = doc.id;
        updatedNames[studentId] = doc['name'];
        List<dynamic> weeklySchedule = doc['weeklySchedule'] ?? [];
        updatedSchedules[studentId] = List<Map<String, dynamic>>.from(weeklySchedule);
      }

      _studentSchedules = updatedSchedules;
      _studentNames = updatedNames;
      notifyListeners();

      print("실시간 업데이트 완료: $_studentSchedules");
    });
  }

  void cancelListeners() {
    _studentScheduleSubscription?.cancel();
    _fcmSubscription?.cancel();
    _studentScheduleSubscription = null;
    _fcmSubscription = null;
  }

  void clearUser() {
    cancelListeners();
    _userID = '';
    _userName = '';
    _userPw = '';
    _role = '';
    _studentNames = {};
    _studentSchedules = {};
    notifyListeners();
    print("UserProvider 초기화 완료");
  }
}

// (일반 선생님만 사용) 레슨 관련 provider 및 함수
class LessonProvider with ChangeNotifier {
  Map<String, Map<String, dynamic>> _lessons = {}; // {lesson_id}: {lesson_data} 형태로 변경
  Map<String, Map<String, dynamic>> get lessons => _lessons;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _lessonListener;

  // Firestore에서 선생님의 수업 불러오기 (변경된 데이터 구조 적용)
  Future<void> fetchTeacherLessons(String teacherId) async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    try {
      DocumentSnapshot<Map<String, dynamic>> doc =
      await firestore.collection('availableSlots').doc(teacherId).get();

      if (doc.exists) {
        Map<String, Map<String, dynamic>> bookedLessons = {};

        if (doc.data()!['bookedSlots'] != null) {
          Map<String, dynamic> bookedSlots = doc.data()!['bookedSlots'];

          bookedLessons = bookedSlots.map((lessonId, lessonData) {
            final data = lessonData as Map<String, dynamic>;
            return MapEntry(lessonId, {
              "date": (data["date"] as Timestamp).toDate(),
              "duration": data["duration"],
              "studentId": data["studentId"],
              "status" : data["status"],
              "isRescheduled" : data['isRescheduled'],
            });
          });
        }

        _lessons = bookedLessons;
        notifyListeners();
        print("수업 정보 불러오기 완료: ${_lessons.length}개");
      }
    } catch (e) {
      print("수업 정보 불러오기 실패: $e");
    }
  }

  // Firestore `snapshots()`로 실시간 수업 정보 감지
  void listenToTeacherLessons(String teacherId) {
    FirebaseFirestore firestore = FirebaseFirestore.instance;

    _lessonListener = firestore
        .collection('availableSlots')
        .doc(teacherId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        Map<String, Map<String, dynamic>> updatedLessons = {};

        if (snapshot.data()!['bookedSlots'] != null) {
          Map<String, dynamic> bookedSlots = snapshot.data()!['bookedSlots'];

          updatedLessons = bookedSlots.map((lessonId, lessonData) {
            final data = lessonData as Map<String, dynamic>;
            return MapEntry(lessonId, {
              "date": (data["date"] as Timestamp).toDate(),
              "duration": data["duration"],
              "studentId": data["studentId"],
              "status" : data["status"],
              "isRescheduled" : data['isRescheduled'],
            });
          });
        }

        _lessons = updatedLessons;
        notifyListeners();
        print("실시간 수업 업데이트 완료 (${updatedLessons.length}개)");
      }
    }, onError: (error) {
      print("실시간 수업 감지 오류: $error");
    });
  }
  // Firestore 실시간 감지 해제 함수
  void cancelLessonListener() {
    _lessonListener?.cancel();
    _lessonListener = null;
    print("실시간 수업 감지 해제됨");
  }

  // 로그아웃 시 Firestore 리스너 해제 및 데이터 초기화
  void clearLessons() {
    _lessons = {};
    _lessonListener?.cancel();
    notifyListeners();
    print("LessonProvider 초기화 완료");
  }
}

// 근무 시간 프로바이더
class SlotProvider with ChangeNotifier {
  Map<String, Map<String, String>> _workSchedule = {};
  Map<String, Map<String, String>> get workSchedule => _workSchedule;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _slotListener;

  // Firestore에서 선생님의 요일별 근무 시간 불러오기 (최초 1회 실행)
  Future<void> fetchTeacherSlots(String teacherId) async {
    try {
      FirebaseFirestore firestore = FirebaseFirestore.instance;
      DocumentSnapshot<Map<String, dynamic>> snapshot =
      await firestore.collection('availableSlots').doc(teacherId).get();

      if (snapshot.exists && snapshot.data() != null) {
        _updateWorkSchedule(snapshot.data()!);
      }
    } catch (e) {
      print("근무 시간 불러오기 중 오류 발생: $e");
    }
  }

  // 실시간으로 Firestore 변경 사항 감지 (listen)
  void listenToTeacherSlotsUpdates(String teacherId) {
    FirebaseFirestore firestore = FirebaseFirestore.instance;

    _slotListener = firestore
        .collection('availableSlots')
        .doc(teacherId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        _updateWorkSchedule(snapshot.data()!);
        print("근무 시간 실시간 업데이트 완료");
      }
    }, onError: (error) {
      print("근무 시간 실시간 감지 오류: $error");
    });
  }

  // Firestore 데이터를 변환하여 `_workSchedule`에 저장
  void _updateWorkSchedule(Map<String, dynamic> rawData) {
    Map<String, dynamic> workData = rawData['workSchedule'] ?? {};
    _workSchedule = workData.map((key, value) {
      return MapEntry(
        key, // 요일 ("MO", "WE" 등)
        Map<String, String>.from(value as Map), // 내부 Map 변환
      );
    });

    notifyListeners();
  }

  // Firestore 실시간 감지 해제
  void cancelSlotListener() {
    _slotListener?.cancel();
    _slotListener = null;
    print("실시간 근무 시간 감지 해제됨");
  }

  // 로그아웃 시 데이터 초기화
  void clearSlots() {
    _workSchedule = {};
    _slotListener?.cancel();
    notifyListeners();
    print("SlotProvider 초기화 완료");
  }
}

//학기 관련 전역 변수와 함수

// 전년도 부터 내년도 학기 정보 불러오기 2025-12-30 수정
Future<void> fetchSemesterInfo() async {
  FirebaseFirestore firestore = FirebaseFirestore.instance;

  try {
    DateTime now = DateTime.now();
    String currentYear = now.year.toString();
    String previousYear = (now.year - 1).toString();
    String nextYear = (now.year + 1).toString();

    List<String> yearRange = [
      "$previousYear-01", "$previousYear-12",
      "$currentYear-01", "$currentYear-12",
      "$nextYear-01", "$nextYear-12"
    ];

    QuerySnapshot<Map<String, dynamic>> snapshot = await firestore
        .collection('semesters')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: yearRange[0]) // 이전 년도 1월부터
        .where(FieldPath.documentId, isLessThanOrEqualTo: yearRange[5]) // 내년 12월까지
        .get();

    // Map<String, List<DateTime>> semesterData = {};
    Map<String, Map<String, dynamic>> semesterData = {}; // 학기 정보 저장


    for (var doc in snapshot.docs) {
      String semesterId = doc.id;  // 예: "2024-01"
      DateTime startDate = (doc['startDate'] as Timestamp).toDate();
      DateTime endDate = (doc['endDate'] as Timestamp).toDate();
      List<Map<String, DateTime>> holidayList = [];
      if (doc.data().containsKey('holidayPeriods') && doc['holidayPeriods'] != null) {
        for (var holiday in List.from(doc['holidayPeriods'])) {
          holidayList.add({
            "startDate": (holiday['startDate'] as Timestamp).toDate(),
            "endDate": (holiday['endDate'] as Timestamp).toDate(),
          });
        }
      }
      semesterData[semesterId] = {"startDate": startDate, "endDate": endDate, "holidays": holidayList};
    }

    // 기존 데이터 초기화 후 업데이트
    SemesterTerm.clear();
    SemesterTerm.addAll(semesterData);

    // 현재 학기 설정
    nowsemester = now;

    for (final entry in semesterData.entries) {
      final semesterId = entry.key; // "2026-01"
      final start = entry.value['startDate'] as DateTime;
      final end = entry.value['endDate'] as DateTime;

      // endDate가 00:00으로 저장된 케이스까지 포함하려고 +1day
      final endExclusive = end.add(const Duration(days: 1));

      if (!now.isBefore(start) && now.isBefore(endExclusive)) {
        final parts = semesterId.split('-');
        final y = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        nowsemester = DateTime(y, m, 1);
        break;
      }
    }

    // 이전/다음 학기 설정 (DateTime은 month overflow 자동 처리됨)
    previoussemester = DateTime(nowsemester.year, nowsemester.month - 1, 1);
    nextsemester     = DateTime(nowsemester.year, nowsemester.month + 1, 1);
    print("학기 정보 불러오기 완료!");

  } catch (e) {
    print("학기 정보 불러오기 중 오류 발생: $e");
  }
}

// 학기별 시작일과 종료일 저장 (key: "YYYY-MM", value: [시작일, 종료일, 휴일리스트])
Map<String, Map<String, dynamic>> SemesterTerm = {};

// 현재 학기, 이전 학기, 다음 학기
DateTime now = DateTime.now();
DateTime nowsemester = now;
DateTime previoussemester = DateTime(now.year, now.month - 1, 1);
DateTime nextsemester = DateTime(now.year, now.month + 1, 1);

class LessonCard extends StatelessWidget {
  final DateTime startTime;
  final DateTime endTime;
  final int month;
  final int date;
  final String student;
  final String teacher;

  const LessonCard({
    required this.startTime,
    required this.endTime,
    required this.month,
    required this.date,
    required this.student,
    required this.teacher,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          border: Border.all(
            width: 1.5,
            color: PRIMARY_COLOR,
          ),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Padding(
            padding: const EdgeInsets.all(13.0),
            child: IntrinsicHeight(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 55, // 날짜 영역 고정 크기
                    child: _Date(month: month, date: date),
                  ),
                  const SizedBox(width: 10.0),
                  SizedBox(
                    width: 45, // 시간 영역 고정 크기
                    child: _Time(startTime: startTime, endTime: endTime),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: _Content(studentID: student, teacher: teacher), // 내용은 남은 공간 차지
                  ),
                ],
              ),
            )));
  }
}
class _Date extends StatelessWidget {
  final int month;
  final int date;

  const _Date({
    required this.month,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontFamily: 'OpenSans',
      fontWeight: FontWeight.w500,
      color: PRIMARY_COLOR,
      fontSize: 20.0,
    );

    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            month.toString(),
            style: textStyle,
          ),
          const Text(
            '/',
            style: textStyle,
          ),
          Text(
            date.toString(),
            style: textStyle,
          ),
        ]);
  }
}
class _Time extends StatelessWidget {
  final DateTime startTime;
  final DateTime endTime;

  const _Time({
    required this.startTime,
    required this.endTime
  });

  @override
  Widget build(BuildContext context) {

    const textStyle = TextStyle(
      fontFamily: 'ELAND',
      fontWeight: FontWeight.w300,
      color: Colors.black,
      fontSize: 13.0,
    );

    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(
        '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
        style: textStyle,
      ),
      Text(
          '~ ${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
          style: textStyle.copyWith(fontSize: 10.0))
    ]);
  }
}
class _Content extends StatelessWidget {
  final String studentID;
  final String teacher;

  const _Content({
    required this.studentID,
    required this.teacher,
  });

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontFamily: 'ELAND',
      fontWeight: FontWeight.w300,
      color: Colors.black,
      fontSize: 16.0,
    );

    return Expanded(
      child: Text(
        '$studentID / $teacher 선생님',
        style: textStyle,
      ),
    );
  }
}


// AppBar, Drawer
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
class KoAppBar extends StatelessWidget implements PreferredSizeWidget {
  const KoAppBar(
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
            fontFamily: 'ELAND',
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
    final userProvider = Provider.of<UserProvider>(context);
    return Drawer(
      child: ListView(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              '${userProvider.userName} 선생님',
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
                  MaterialPageRoute(builder: (BuildContext context) => Home()),
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
            onTap: () async {
              Navigator.of(context).push(
                _createRoute(WeekSchedule()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          // ListTile(
          //   leading: const Icon(Icons.account_circle),
          //   iconColor: PRIMARY_COLOR,
          //   focusColor: IBORY,
          //   title: const Text(
          //     '마이페이지',
          //     style: TextStyle(
          //       color: Colors.black,
          //       fontFamily: 'ELAND',
          //       fontWeight: FontWeight.w300,
          //     ),
          //   ),
          //   onTap: () {
          //     Navigator.of(context).push(
          //       _createRoute(MyPage()),
          //     );
          //   },
          //   trailing: const Icon(Icons.navigate_next_rounded),
          // ),
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
            onTap: () async {
              final storage = const FlutterSecureStorage();
              final userProvider = Provider.of<UserProvider>(context, listen: false);
              final lessonProvider = Provider.of<LessonProvider>(context, listen: false);
              final workProvider = Provider.of<SlotProvider>(context, listen: false);

              // 1. 자동 로그인 정보 삭제
              await storage.delete(key: "auto_id.ver2");
              await storage.delete(key: "auto_pw.ver2");

              // 2. `UserProvider`의 사용자 정보 초기화
              userProvider.clearUser();
              userProvider.cancelListeners();

              // 3. `LessonProvider`의 수업 데이터 초기화
              lessonProvider.clearLessons();
              lessonProvider.cancelLessonListener();

              workProvider.clearSlots();
              workProvider.cancelSlotListener();

              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (BuildContext context) => const Login()),
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


// Banner
class TodayBanner extends StatelessWidget {
  final DateTime selectedDate;
  final int count;

  const TodayBanner({
    required this.selectedDate,
    required this.count,
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
      e = '예정된 수업';
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

// Master 전용 변수 함수 객체
class ManagerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ManagerAppBar({
    super.key,
    required this.appBar,
    required this.selectedTeacherId,
    required this.onTeacherChanged,
  });

  final AppBar appBar;
  final String selectedTeacherId;
  final Function(String) onTeacherChanged;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MasterProvider>(context);
    final teachers = provider.teachers;

    return AppBar(
      backgroundColor: PRIMARY_COLOR,
      iconTheme: const IconThemeData(color: Colors.white),
      centerTitle: true,
      elevation: 0.0,
      title: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedTeacherId.isNotEmpty ? selectedTeacherId : null,
          hint: Text("선생님 선택", style: style.copyWith(color: Colors.white, fontSize: 16)),
          dropdownColor: SECONDARY_COLOR.withOpacity(0.4),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
          style: style.copyWith(color: Colors.white, fontSize: 16),
          items: teachers.map<DropdownMenuItem<String>>((teacher) {
            return DropdownMenuItem<String>(
              value: teacher['id'],
              child: Text('${teacher['name']} 선생님', style: const TextStyle(fontSize: 18)),
            );
          }).toList(),
          onChanged: (newTeacherId) {
            if (newTeacherId != null) {
              onTeacherChanged(newTeacherId); // 선택한 선생님을 업데이트하는 콜백 실행
            }
          },
        ),
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(appBar.preferredSize.height);
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
              '메인 페이지',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (BuildContext context) => const Manage()),
                      (route) => false);
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.contact_mail),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '수강생 관리',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () async {
              Navigator.of(context).push(
                _createRoute(const StudentM()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.school),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '선생님 관리',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              Navigator.of(context).push(
                _createRoute(const TeacherM()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.today),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '수업 관리',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () async {
              Navigator.of(context).push(
                _createRoute(const ScheduleM()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '기타 설정',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () async {
              Navigator.of(context).push(
                _createRoute(const SettingsPage()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '로그 아웃',
              style: TextStyle(
                color: Colors.red,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () async {
              final storage = const FlutterSecureStorage();
              final userProvider = Provider.of<UserProvider>(context, listen: false);
              final masterProvider = Provider.of<MasterProvider>(context, listen: false);
              // 1. 자동 로그인 정보 삭제
              await storage.delete(key: "auto_id.ver2");
              await storage.delete(key: "auto_pw.ver2");

              // 2. `UserProvider`의 사용자 정보 초기화
              userProvider.clearUser();
              userProvider.cancelListeners();

              // 마스터 로그아웃 시 clear 로직.
              masterProvider.cancelAllListeners();

              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (BuildContext context) => const Login()),
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

class MasterProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _lessons = [];
  // 선생님별 예약된 슬롯을 저장하는 변수 변경
  final Map<String, Map<String, Map<String, dynamic>>> _bookedSlots = {}; // {teacherId: {lessonId: {lessonData}}}
  final Map<String, Map<String, dynamic>> _workSchedule = {}; // 선생님별 근무 일정
  Map<String, String> _archivedUsers = {};
  Map<String, String> _teacherNames = {}; // 선생님 ID → 이름
  Map<String, String> _studentNames = {}; // 학생 ID → 이름

  // 실시간 감지 리스너 추적용 변수
  StreamSubscription? _lessonsSubscription;
  StreamSubscription? _usersSubscription;
  StreamSubscription? _availableSlotsSubscription;

  List<Map<String, dynamic>> get teachers => _teachers;
  List<Map<String, dynamic>> get students => _students;
  List<Map<String, dynamic>> get lessons => _lessons;
  Map<String, Map<String, Map<String, dynamic>>> get bookedSlots => _bookedSlots;
  Map<String, Map<String, dynamic>> get workSchedule => _workSchedule;
  Map<String, String> get archivedUsers => _archivedUsers; // 아카이브된 학생 ID → 이름 매핑
  Map<String, String> get teacherNames => _teacherNames;
  Map<String, String> get studentNames => _studentNames;

  Future<void> initialize() async {
    await fetchUsers();
    await fetchAllAvailableSlots();
    await fetchLessons();
    await fetchArchivedUsers();
    listenToAvailableSlotsUpdates();
    listenToLessonsUpdates();
    listenToUserCollectionUpdates();
  }

  // Firestore에서 선생님과 학생 데이터 불러오기 (로그인 시 실행)
  Future<void> fetchUsers() async {
    try {
      QuerySnapshot usersSnapshot = await _firestore.collection('users').get();

      List<Map<String, dynamic>> teachers = [];
      List<Map<String, dynamic>> students = [];
      Map<String, String> newTeacherNames = {};
      Map<String, String> newStudentNames = {};

      for (var doc in usersSnapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        if (data['role'] == 'teacher') {
          teachers.add({...data, 'id': doc.id});
          newTeacherNames[doc.id] = data['name'] ?? '알 수 없음';
        } else if (data['role'] == 'student') {
          // 학생 정보를 가져올 때, lessons 서브컬렉션도 가져오기
          List<Map<String, dynamic>> studentLessons = await fetchStudentLessons(doc.id);
          students.add({
            ...data, // 기존 학생 정보
            'id': doc.id,
            'lessons': studentLessons // 해당 학생의 수업 목록 추가
          });
          newStudentNames[doc.id] = data['name'] ?? '알 수 없음';
        }
      }

      _teachers = teachers;
      _students = students;
      _teacherNames = newTeacherNames;
      _studentNames = newStudentNames;
      notifyListeners();
      print("선생님 & 학생 데이터 로드 완료");
    } catch (e) {
      print("Firestore에서 사용자 정보 불러오기 실패: $e");
    }
  }

  // 특정 학생의 lessons 서브컬렉션을 가져오는 함수
  Future<List<Map<String, dynamic>>> fetchStudentLessons(String studentId) async {
    try {
      QuerySnapshot lessonSnapshot = await _firestore
          .collection('users')
          .doc(studentId)
          .collection('lessons')
          .get();

      List<Map<String, dynamic>> lessons = lessonSnapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        DateTime lessonDate = (data['date'] as Timestamp).toDate();
        DateTime createdAt = (data['createdAt'] as Timestamp).toDate();
        DateTime updatedAt = (data['updatedAt'] as Timestamp).toDate();

        return {
          ...data,
          'id': doc.id,
          'date': lessonDate,
          'createdAt': createdAt,
          'updatedAt': updatedAt,
        };
      }).toList();

      return lessons;
    } catch (e) {
      print("학생 ($studentId) 수업 데이터 불러오기 실패: $e");
      return [];
    }
  }

  // Firestore에서 전체 수업 데이터를 가져옴 (로그인 시 실행)
  Future<void> fetchLessons() async {
    try {
      QuerySnapshot lessonSnapshot =
      await _firestore.collection('lessons').get();

      List<Map<String, dynamic>> lessons = lessonSnapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        DateTime lessonDate = (data['date'] as Timestamp).toDate();
        DateTime createdAt = (data['createdAt'] as Timestamp).toDate();
        DateTime updatedAt = (data['updatedAt'] as Timestamp).toDate();
        return {
          ...data,
          'id': doc.id,
          'date': lessonDate,
          'createdAt': createdAt,
          'updatedAt': updatedAt,
        };
      }).toList();

      _lessons = lessons;
      notifyListeners();
      print("전체 수업 데이터 로드 완료");
    } catch (e) {
      print("Firestore에서 수업 정보 불러오기 실패: $e");
    }
  }

  // 모든 선생님의 bookedSlots & workSchedule을 한 번에 불러오기
  Future<void> fetchAllAvailableSlots() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('availableSlots').get();

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        String teacherId = doc.id;

        // 예약된 슬롯 저장 (Map<String, Map<String, dynamic>> 형식)
        Map<String, Map<String, dynamic>> bookedLessons = {};
        if (data.containsKey('bookedSlots') && data['bookedSlots'] != null) {
          Map<String, dynamic> bookedSlots = data['bookedSlots'];

          bookedLessons = bookedSlots.map((lessonId, lessonData) {
            final entry = lessonData as Map<String, dynamic>;
            return MapEntry(lessonId, {
              "date": (entry["date"] as Timestamp).toDate(),
              "duration": entry["duration"],
              "studentId": entry["studentId"],
              "status" : entry["status"],
              "isRescheduled" : entry["isRescheduled"],
            });
          });
        }
        _bookedSlots[teacherId] = bookedLessons; // 데이터 구조 업데이트

        // 근무 일정 저장
        if (data.containsKey('workSchedule')) {
          _workSchedule[teacherId] = Map<String, dynamic>.from(data['workSchedule']);
        } else {
          _workSchedule[teacherId] = {};
        }
      }

      notifyListeners();
      print("모든 선생님의 예약된 슬롯 & 근무 일정 불러오기 완료");
    } catch (e) {
      print("availableSlots 데이터 불러오기 실패: $e");
    }
  }

  // Firestore에서 아카이브된 users 정보를 불러와 `archivedStudents`에 저장
  Future<void> fetchArchivedUsers() async {
    try {
      FirebaseFirestore firestore = FirebaseFirestore.instance;
      QuerySnapshot archivedSnapshot = await firestore.collection('archivedUsers').get();

      // 아카이브된 user ID → 이름 맵핑 저장
      _archivedUsers = {
        for (var doc in archivedSnapshot.docs)
          doc.id: doc['name'] ?? "알 수 없음"
      };

      notifyListeners(); // UI 업데이트
    } catch (e) {
      print("아카이브된 정보 불러오기 실패: $e");
    }
  }

  // 모든 선생님의 bookedSlots & workSchedule을 실시간 감지하여 자동 업데이트
  void listenToAvailableSlotsUpdates() {
    _availableSlotsSubscription = _firestore.collection('availableSlots').snapshots().listen((snapshot) {
      for (var doc in snapshot.docs) {
        var data = doc.data();
        String teacherId = doc.id;

        // 예약된 슬롯 실시간 업데이트 (3중 Map 유지)
        Map<String, Map<String, dynamic>> bookedLessons = {};
        if (data.containsKey('bookedSlots') && data['bookedSlots'] != null) {
          Map<String, dynamic> bookedSlots = data['bookedSlots'];

          bookedLessons = bookedSlots.map((lessonId, lessonData) {
            final entry = lessonData as Map<String, dynamic>;
            return MapEntry(lessonId, {
              "date": (entry["date"] as Timestamp).toDate(),
              "duration": entry["duration"],
              "studentId": entry["studentId"],
              "status" : entry["status"],
              "isRescheduled" : entry['isRescheduled'],
            });
          });
        }
        _bookedSlots[teacherId] = bookedLessons;

        // 근무 일정 실시간 업데이트
        if (data.containsKey('workSchedule')) {
          _workSchedule[teacherId] = Map<String, dynamic>.from(data['workSchedule']);
        } else {
          _workSchedule[teacherId] = {};
        }
      }

      notifyListeners();
      print("실시간 예약된 슬롯 & 근무 일정 업데이트 감지됨");
    });
  }

  // 실시간으로 수업 변경사항을 감지하여 업데이트
  void listenToLessonsUpdates() {
    _lessonsSubscription = _firestore.collection('lessons').snapshots().listen((snapshot) {
      List<Map<String, dynamic>> updatedLessons = snapshot.docs.map((doc) {
        var data = doc.data();
        DateTime lessonDate = (data['date'] as Timestamp).toDate();
        DateTime createdAt = (data['createdAt'] as Timestamp).toDate();
        DateTime updatedAt = (data['updatedAt'] as Timestamp).toDate();
        return {
          ...data,
          'id': doc.id,
          'date': lessonDate,
          'createdAt': createdAt,
          'updatedAt': updatedAt,
        };
      }).toList();

      _lessons = updatedLessons;
      notifyListeners();
      print("실시간 수업 업데이트 감지됨");
    });
  }

  // 선생님과 학생 정보 실시간 동기화
  void listenToUserCollectionUpdates() {
    _usersSubscription = _firestore.collection('users').snapshots().listen((snapshot) async {
      List<Map<String, dynamic>> updatedTeachers = [];
      List<Map<String, dynamic>> updatedStudents = [];
      Map<String, String> newTeacherNames = {};
      Map<String, String> newStudentNames = {};

      for (var doc in snapshot.docs) {
        var data = doc.data();
        String role = data['role'] ?? '';

        if (role == 'teacher') {
          updatedTeachers.add({...data, 'id': doc.id});
          newTeacherNames[doc.id] = data['name'] ?? '알 수 없음';
        } else if (role == 'student') {
          // 실시간 감지에서도 lessons 데이터 불러오기 추가
          List<Map<String, dynamic>> studentLessons = await fetchStudentLessons(doc.id);
          updatedStudents.add({
            ...data,
            'id': doc.id,
            'lessons': studentLessons, // lessons 서브컬렉션 포함
          });
          newStudentNames[doc.id] = data['name'] ?? '알 수 없음';
        }
      }

      // 리스트 갱신
      _teachers = updatedTeachers;
      _students = updatedStudents;
      _teacherNames = newTeacherNames;
      _studentNames = newStudentNames;

      notifyListeners();
      print("실시간 유저 컬렉션 업데이트 감지됨 (총 선생님 ${_teachers.length}명, 학생 ${_students.length}명)");
    });
  }

  String getDisplayName(String id, {required bool isTeacher}) {
    if (_archivedUsers.containsKey(id)) {
      return '${_archivedUsers[id]}(탈퇴)';
    }

    if (isTeacher) {
      return _teacherNames[id] ?? "알 수 없음";
    } else {
      return _studentNames[id] ?? "알 수 없음";
    }
  }

  void cancelAllListeners() {
    _lessonsSubscription?.cancel();
    _usersSubscription?.cancel();
    _availableSlotsSubscription?.cancel();

    _lessonsSubscription = null;
    _usersSubscription = null;
    _availableSlotsSubscription = null;

    print("모든 실시간 감지 리스너 종료됨 (로그아웃)");
  }
}

class HeartButton extends StatelessWidget {
  final VoidCallback onPressed;

  const HeartButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    double buttonSize = MediaQuery.of(context).size.width / 2.3; // 화면 1/2 크기

    return Center(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(buttonSize / 2),
        child: Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xff3E6F58), // 부드러운 녹색 (PRIMARY_COLOR 계열)
            boxShadow: [
              // 바깥쪽 그림자 (빛을 받은 느낌)
              BoxShadow(
                color: Colors.white.withOpacity(0.8),
                offset: const Offset(-4, -4),
                blurRadius: 6,
              ),
              // 안쪽 그림자 (눌린 느낌)
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                offset: const Offset(4, 4),
                blurRadius: 6,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.favorite, // 하트 아이콘 ❤️
              size: buttonSize * 0.6, // 버튼 크기의 40%
              color: const Color(0xffF2F3EE), // 아이보리 색상 (IVORY_COLOR)
            ),
          ),
        ),
      ),
    );
  }
}
class SchoolButton extends StatelessWidget {
  final VoidCallback onPressed;

  const SchoolButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    double buttonSize = MediaQuery.of(context).size.width / 2.3; // 화면 1/2 크기
// 기존 색상보다 짙은 녹색 계열 추천
    const Color darkGreen1 = Color(0xff2E5A45); // 약간 더 어두운 녹색
    const Color darkGreen2 = Color(0xff26503C); // 차분하고 깊은 녹색
    const Color darkGreen3 = Color(0xff1F4534); // 더욱 짙고 차분한 녹색
    const Color darkGreen4 = Color(0xff183A2B); // 거의 어두운 녹색 계열
    const Color darkGreen5 = Color(0xff123026); // 매우 어두운 녹색 (딥 그린)

    return Center(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(buttonSize / 2),
        child: Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xff1F4534), // 부드러운 녹색 (PRIMARY_COLOR 계열)
            boxShadow: [
              // 바깥쪽 그림자 (빛을 받은 느낌)
              BoxShadow(
                color: Colors.white.withOpacity(0.8),
                offset: const Offset(-4, -4),
                blurRadius: 6,
              ),
              // 안쪽 그림자 (눌린 느낌)
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                offset: const Offset(4, 4),
                blurRadius: 6,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.school_rounded,
              size: buttonSize * 0.6, // 버튼 크기의 40%
              color: const Color(0xffF2F3EE), // 아이보리 색상 (IVORY_COLOR)
            ),
          ),
        ),
      ),
    );
  }
}
class ScheduleButton extends StatelessWidget {
  final VoidCallback onPressed;

  const ScheduleButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    double buttonSize = MediaQuery.of(context).size.width / 2.3; // 화면 1/2 크기
    const Color darkGreen5 = Color(0xff123026); // 매우 어두운 녹색 (딥 그린)

    return Center(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(buttonSize / 2),
        child: Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xff123026), // 부드러운 녹색 (PRIMARY_COLOR 계열)
            boxShadow: [
              // 바깥쪽 그림자 (빛을 받은 느낌)
              BoxShadow(
                color: Colors.white.withOpacity(0.8),
                offset: const Offset(-4, -4),
                blurRadius: 6,
              ),
              // 안쪽 그림자 (눌린 느낌)
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                offset: const Offset(4, 4),
                blurRadius: 6,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.edit_calendar_rounded,
              size: buttonSize * 0.6, // 버튼 크기의 40%
              color: const Color(0xffF2F3EE), // 아이보리 색상 (IVORY_COLOR)
            ),
          ),
        ),
      ),
    );
  }
}

class LessonCardM extends StatelessWidget {
  final DateTime startTime;
  final DateTime endTime;
  final int month;
  final int date;
  final String student;
  final String teacher;
  final VoidCallback onEdit; // "수정" 버튼 클릭 시 실행할 콜백 함수

  const LessonCardM({
    required this.startTime,
    required this.endTime,
    required this.month,
    required this.date,
    required this.student,
    required this.teacher,
    required this.onEdit, // onEdit 파라미터 추가
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          border: Border.all(
            width: 1.5,
            color: PRIMARY_COLOR,
          ),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: IntrinsicHeight(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 55, // 날짜 영역 고정 크기
                    child: _Date(month: month, date: date),
                  ),
                  const SizedBox(width: 8.0),
                  SizedBox(
                    width: 40, // 시간 영역 고정 크기
                    child: _Time(startTime: startTime, endTime: endTime),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, // 내용과 버튼을 양쪽으로 정렬
                      children: [
                        _Content(studentID: student, teacher: teacher),
                        TextButton(
                          onPressed: onEdit, // 수정 버튼 클릭 시 실행할 콜백
                          child: const Text(
                            "수정",
                            style: TextStyle(
                              fontFamily: 'ELAND',
                              fontWeight: FontWeight.w500,
                              color: Colors.red,
                              fontSize: 13.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )));
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

// 새로운 레슨들을 3 장소에 저장하는 함수
Future<void> saveLessonsToFirestore(String studentId, String teacherId, List<Map<String, dynamic>> lessons) async {
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  WriteBatch batch = firestore.batch();

  // 서버 타임스탬프를 위한 변수 (생성, 수정시 모두 사용)
  FieldValue serverTimestamp = FieldValue.serverTimestamp();

  // 1. lesson 컬렉션 주소
  CollectionReference LessonsRef = firestore.collection('lessons');
  // 2. 선생님 availableSlots 문서 참조
  DocumentReference teacherSlotRef = firestore.collection('availableSlots').doc(teacherId);
  // 3. 학생 레슨 컬렉션 참조
  CollectionReference studentLessonsCollection =
  firestore.collection('users').doc(studentId).collection('lessons');

  for (var lesson in lessons) {
    // lessons 컬렉션에 새 문서 생성 (Firestore Auto ID)
    DocumentReference lessonDocRef = LessonsRef.doc();
    String lessonId = lessonDocRef.id;

    // 저장할 레슨 데이터 구성 (공통 필드) 1,3
    Map<String, dynamic> lessonData = {
      'code': lesson['code'],
      'date': lesson['date'],
      'duration': lesson['duration'],
      'isRescheduled': lesson['isRescheduled'],
      'studentId': lesson['studentId'],
      'teacherId': teacherId,
      'status': lesson['status'],
      'createdAt': lesson['createdAt'] ?? serverTimestamp,
      'updatedAt': lesson['updatedAt'] ?? serverTimestamp,
    };

    // 1. lessons 컬렉션에 레슨 데이터 저장
    batch.set(lessonDocRef, lessonData);

    // 2. 선생님의 availableSlots 문서의 bookedSlots 맵에 해당 레슨 추가
    // merge 옵션을 사용해 기존 필드와 병합합니다.
    batch.set(
        teacherSlotRef,
        {
          'bookedSlots': {
            lessonId: {
              'date': lesson['date'],
              'duration': lesson['duration'],
              'isRescheduled': lesson['isRescheduled'],
              'status': lesson['status'],
              'studentId': studentId,
            }
          }
        },
        SetOptions(merge: true)
    );

    // 3. 학생 레슨 컬렉션 참조
    DocumentReference studentLessonDocRef = studentLessonsCollection.doc(lessonId);
    batch.set(studentLessonDocRef, lessonData);

  }
  await batch.commit();
}

// HH:mm 형식의 String을 DateTime으로 변환
// 년도 / 월 / 일 설정 안되어 있으니 각별히 유의하길 바람
DateTime parseTime(String time) {
  List<String> parts = time.split(":");
  return DateTime(0, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
}
// 주어진 시간 범위 안에 있는지 확인하는 함수
bool isWithinTimeRange(String startTime, int duration, String rangeStart, String rangeEnd) {
  DateTime lessonStart = parseTime(startTime);
  DateTime lessonEnd = lessonStart.add(Duration(minutes: duration));
  DateTime workStart = parseTime(rangeStart);
  DateTime workEnd = parseTime(rangeEnd);
  return (lessonStart.isAtSameMomentAs(workStart) || lessonStart.isAfter(workStart)) &&
      (lessonEnd.isAtSameMomentAs(workEnd) || lessonEnd.isBefore(workEnd));
}
// 두 수업 시간이 겹치는지 확인하는 함수
bool isOverlapping(String start1, int duration1, String start2, int duration2) {
  DateTime startTime1 = parseTime(start1);
  DateTime endTime1 = startTime1.add(Duration(minutes: duration1));
  DateTime startTime2 = parseTime(start2);
  DateTime endTime2 = startTime2.add(Duration(minutes: duration2));

  return startTime1.isBefore(endTime2) && startTime2.isBefore(endTime1);
}
// 휴일 검사 함수 (1일 추가해서 작동함)
bool isHoliday(DateTime date, List<Map<String, DateTime>> holidays) {
  for (var holiday in holidays) {
    DateTime holidayStart = holiday["startDate"]!;
    DateTime holidayEnd = holiday["endDate"]!.add(const Duration(days: 1));

    if (date.isAfter(holidayStart) && date.isBefore(holidayEnd)) {
      return true;
    }
  }
  return false;
}

// 로딩창 보여주기
void showLoadingDialog(BuildContext context, String content) {
  showDialog(
    context: context,
    barrierDismissible: false, // 로딩 중 다이얼로그 닫기 방지
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          '로딩 중...',
          style: style.copyWith(color: PRIMARY_COLOR, fontSize: 17),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(PRIMARY_COLOR)),
            const SizedBox(height: 10),
            Text(
              content,
              style: style.copyWith(fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    },
  );
}

// 알람 동의 팝업창
Future<void> showNotificationPermissionDialog(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  bool? alreadyAsked = prefs.getBool("notification_permission_requested");

  if (alreadyAsked == true) return;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: Text(
          "알림을 허용하시겠어요?",
          style: style.copyWith(fontWeight: FontWeight.bold),
        ),
        content: Text(
          "수업 일정, 변경 사항 등을 실시간으로 받아보시려면\n"
              "알림을 켜 주세요.\n\n"
              "설정에서 언제든지 변경 가능합니다.",
          style: style, // 폰트 두께 건드리지 않음
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: Text(
              "다음에",
              style: style.copyWith(color: Colors.black54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: PRIMARY_COLOR,
            ),
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: Text("허용", style: style.copyWith(color: Colors.white)),
          ),
        ],
      );
    },
  );

  prefs.setBool("notification_permission_requested", true);

  final userProvider = Provider.of<UserProvider>(context, listen: false);
  final userId = userProvider.userID;

  await FirebaseFirestore.instance.collection('users')
      .doc(userId)
      .update({'notificationPermission': result == true});

  if (result == true) {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      sound: true,
    );
  }
}

// 11.17일 오류 확인용 함수
// Future<void> debugInvalidStudentIdLessons() async {
//   final firestore = FirebaseFirestore.instance;
//
//   // lessons 컬렉션 전체 조회
//   final snap = await firestore.collection('lessons').get();
//
//   print('--- studentId 값이 이상한 문서들 ---');
//   for (final doc in snap.docs) {
//     final data = doc.data() as Map<String, dynamic>;
//
//     // studentId 값 꺼내기 (없으면 null)
//     final studentId = data['studentId'];
//
//     // 이상한 경우:
//     // 1) 필드 없음 / null
//     // 2) String 타입이 아님
//     // 3) 빈 문자열("") 이거나 공백뿐인 문자열
//     final isInvalid =
//         studentId == null ||
//             studentId is! String ||
//             (studentId as String).trim().isEmpty;
//
//     if (isInvalid) {
//       print('lesson ${doc.id} => $data');
//     }
//   }
// }

