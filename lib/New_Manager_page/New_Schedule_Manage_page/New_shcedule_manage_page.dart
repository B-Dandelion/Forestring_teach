import 'dart:core';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/New_Data/new_constant.dart';
import 'package:forestring_teacher_2/New_Manager_page/Manager_data/New_lesson_sheet.dart';
import 'package:forestring_teacher_2/New_Manager_page/New_Manager_Home_page.dart';
import 'package:forestring_teacher_2/New_Manager_page/New_Schedule_Manage_page/Break.dart';
import 'package:forestring_teacher_2/New_Manager_page/New_Schedule_Manage_page/New_schedule_modify_page.dart';
import 'package:forestring_teacher_2/New_Manager_page/New_Schedule_Manage_page/New_semester_page.dart';

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

class New_Schedule_Manage_page extends StatefulWidget {
  const New_Schedule_Manage_page({super.key});

  @override
  State<New_Schedule_Manage_page> createState() => _New_Schedule_Manage_page();
}
Map<String,List> Semester1 = {};
Map<String,List> Semester2 = {};
Map<int,List<DateTime>> BreakDays = {};
class _New_Schedule_Manage_page extends State<New_Schedule_Manage_page> {
  Duration duration = const Duration(hours: 10, minutes: 0);
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
            child: const Icon(Icons.arrow_back_rounded, color: PRIMARY_COLOR),
            onPressed: () {
              Navigator.of(context).push(
                _createRoute(const New_Manager_Home_page()),
              );
            }),
        body: Container(
            padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
            child: ListView(
              children: [
                ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: PRIMARY_COLOR,
                        child: Icon(Icons.post_add,
                            color: Colors.white)),
                    title: const Text(
                      '보강 등록하기',
                      style: TextStyle(
                          fontFamily: 'ELAND',
                          fontWeight: FontWeight.w300,
                          color: Colors.black),
                    ),
                    tileColor: Colors.white,
                    trailing:
                    const Icon(Icons.navigate_next_rounded, color: Colors.grey),
                    onTap: () {
                      showModalBottomSheet(
                          context: context,
                          isDismissible: true,
                          builder: (_) => const New_lesson_sheet(),
                          isScrollControlled: true);
                    }),
                ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: PRIMARY_COLOR,
                        child: Icon(Icons.inventory_rounded,
                            color: Colors.white)),
                    title: const Text(
                      '모든 수업 보기',
                      style: TextStyle(
                          fontFamily: 'ELAND',
                          fontWeight: FontWeight.w300,
                          color: Colors.black),
                    ),
                    tileColor: Colors.white,
                    shape: const Border(
                      top: BorderSide(color: Colors.grey),
                    ),
                    trailing:
                    const Icon(Icons.navigate_next_rounded, color: Colors.grey),
                    onTap: () async {
                      Navigator.of(context)
                          .push(_createRoute(const New_Schedule_modify_page()));
                    }),
                ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: PRIMARY_COLOR,
                        child: Icon(Icons.calendar_today_rounded,
                            color: Colors.white)),
                    title: const Text(
                      '학기 정보 확인하기',
                      style: TextStyle(
                          fontFamily: 'ELAND',
                          fontWeight: FontWeight.w300,
                          color: Colors.black),
                    ),
                    tileColor: Colors.white,
                    shape: const Border(
                      top: BorderSide(color: Colors.grey),
                    ),
                    trailing:
                    const Icon(Icons.navigate_next_rounded, color: Colors.grey),
                    onTap: () async {
                      await semester();
                      Navigator.of(context)
                          .push(_createRoute(const New_Semester_page()));
                    }),
                ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: PRIMARY_COLOR,
                        child: Icon(Icons.pending_actions,
                            color: Colors.white)),
                    title: const Text(
                      '휴원 기간 확인하기',
                      style: TextStyle(
                          fontFamily: 'ELAND',
                          fontWeight: FontWeight.w300,
                          color: Colors.black),
                    ),
                    tileColor: Colors.white,
                    shape: const Border(
                      top: BorderSide(color: Colors.grey),
                    ),
                    trailing:
                    const Icon(Icons.navigate_next_rounded, color: Colors.grey),
                    onTap: () async {
                      await getBreakDates(BreakDays);
                      Navigator.of(context)
                          .push(_createRoute(const Break()));
                    }),
              ],
            )));
  }
}

//
// Future<Map<int, List<DateTime>>> getSemesterDates() async {
//   int currentYear = nowsemester.year; // 올해 연도
//   int nextYear = currentYear + 1; // 내년 연도
//
//   // Firebase Firestore에서 Class 컬렉션에 접근하여 학기 데이터를 가져옴
//   var currentYearDoc = await FirebaseFirestore.instance
//       .collection('Class')
//       .doc('$currentYear')
//       .get();
//
//   var nextYearDoc = await FirebaseFirestore.instance
//       .collection('Class')
//       .doc('$nextYear')
//       .get();
//
//   // 학기 시작과 끝 날짜를 배열로 추출
//   List<DateTime> currentYearSemesters = _getSemestersFromDoc(currentYearDoc);
//   List<DateTime> nextYearSemesters = _getSemestersFromDoc(nextYearDoc);
//
//   // 연도별 학기 정보를 Map 형태로 반환
//   return {
//     currentYear: currentYearSemesters,
//     nextYear: nextYearSemesters,
//   };
// }
// Future<Map<int, List<DateTime>>> getBreakDates() async {
//   // 현재 연도와 다음 연도를 계산
//   int currentYear = nowsemester.year;
//   int nextYear = currentYear + 1;
//
//   // Firestore에서 해당 연도의 휴일 정보를 불러옵니다.
//   Future<List<DateTime>> fetchHolidaysForYear(int year) async {
//     final snapshot = await FirebaseFirestore.instance
//         .collection('Class')
//         .doc(year.toString())
//         .get();
//
//     // 휴일 정보가 없을 경우 빈 리스트 반환
//     if (!snapshot.exists || snapshot.data()?['Holiday'] == null) {
//       return [];
//     }
//
//     // Firestore 데이터에서 휴일 리스트 생성
//     return (snapshot.data()?['Holiday'] as List)
//         .map((timestamp) => (timestamp as Timestamp).toDate())
//         .toList();
//   }
//
//   // 두 연도에 대한 휴일 데이터 가져오기
//   List<DateTime> currentYearHolidays = await fetchHolidaysForYear(currentYear);
//   List<DateTime> nextYearHolidays = await fetchHolidaysForYear(nextYear);
//
//   // 모든 휴일 리스트를 합치기
//   List<DateTime> allHolidays = [...currentYearHolidays, ...nextYearHolidays];
//
//   // 휴일 날짜 리스트 확장: 각 휴일 날짜로부터 7일간의 날짜를 포함
//   List<DateTime> getHolidayRange(DateTime holiday) {
//     DateTime start = holiday;
//     DateTime end = holiday.add(const Duration(days: 6));
//     List<DateTime> range = [];
//     for (DateTime date = start;
//     date.isBefore(end) || date.isAtSameMomentAs(end);
//     date = date.add(const Duration(days: 1))) {
//       range.add(date);
//     }
//     return range;
//   }
//
//   // 각 연도별로 휴일 범위를 정리
//   Map<int, List<DateTime>> holidayMap = {};
//   for (var holiday in allHolidays) {
//     int year = holiday.year;
//
//     // 해당 연도의 기존 리스트에 휴일 날짜 추가
//     holidayMap.putIfAbsent(year, () => []);
//     holidayMap[year]!.addAll(getHolidayRange(holiday));
//   }
//
//   // 각 연도별 리스트에서 중복 제거 후 정렬
//   holidayMap.forEach((key, value) {
//     holidayMap[key] = value.toSet().toList()..sort((a, b) => a.compareTo(b));
//   });
//
//   return holidayMap;
// }

Future<void> getBreakDates(Map<int, List<DateTime>> breakDays) async {
  // Firestore에서 휴일 정보를 가져오기
  final holidaySnapshot = await FirebaseFirestore.instance
      .collection('Class')
      .doc(nowsemester.year.toString())
      .get();
  final holidaySnapshot2 = await FirebaseFirestore.instance
      .collection('Class')
      .doc((nowsemester.year+1).toString())
      .get();
  // 현재 연도 및 다음 연도의 휴일 리스트 생성
  List<DateTime> currentYearHolidays = (holidaySnapshot.data()?['Holiday'] as List)
      .map((timestamp) => (timestamp as Timestamp).toDate())
      .toList();
  List<DateTime> nextYearHolidays = (holidaySnapshot2.data()?['Holiday'] as List)
      .map((timestamp) => (timestamp as Timestamp).toDate())
      .toList();
  // 모든 휴일 리스트 합치기
  List<DateTime> allHolidays = [...currentYearHolidays, ...nextYearHolidays];
  // 휴일 시작 날짜만 Map에 추가
  Map<int, List<DateTime>> generatedBreakDays = {};
  for (var holiday in allHolidays) {
    int semesterKey = holiday.year; // 연도로 학기 구분
    generatedBreakDays.putIfAbsent(semesterKey, () => []);
    // 시작 날짜 추가
    if (!generatedBreakDays[semesterKey]!.contains(holiday)) {
      generatedBreakDays[semesterKey]!.add(holiday);
    }
  }
  breakDays.clear();
  breakDays.addAll(generatedBreakDays);
  breakDays.forEach((year, holidays) {
    print('Year: $year');
    for (var holiday in holidays) {
      print(' - Holiday Start Date: ${holiday.toLocal()}');
    }
  });
}

//
// List<DateTime> _getSemestersFromDoc(DocumentSnapshot doc) {
//   List<DateTime> semesters = [];
//
//   if (doc.exists) {
//     // 각 월(1, 2, 3, ...)에 해당하는 필드를 가져옴
//     for (int month = 1; month <= 12; month++) {
//       String fieldName = '$month'; // 필드명 (1, 2, 3, ...)
//       if (doc.data() != null) {
//         List<dynamic> semesterDates = doc[fieldName]; // 필드에 저장된 학기 날짜 배열
//         if (semesterDates.length >= 2) {
//           DateTime start = (semesterDates[0] as Timestamp).toDate();
//           DateTime end = (semesterDates[1] as Timestamp).toDate();
//           semesters.add(start);
//           semesters.add(end);
//         }
//       }
//     }
//   }
//   return semesters;
// }
Future<void> semester() async {
  try {
    //학기 정보 저장할 리스트 생성, 그리고 저장.
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