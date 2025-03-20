import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';

class StudentCalendar extends StatefulWidget {
  final String studentId;
  const StudentCalendar({super.key, required this.studentId});

  @override
  State<StudentCalendar> createState() => _StudentCalendarState();
}

class _StudentCalendarState extends State<StudentCalendar> {
  DateTime selectedDate = DateTime.now();
  DateTime focusedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {

    return Consumer<MasterProvider>(
        builder: (context, provider, child){
          final provider = Provider.of<MasterProvider>(context);
          final Map<String, dynamic> teachers = { for (var t in provider.teachers) t['id']: t };
          final Map<String, dynamic> students = { for (var s in provider.students) s['id']: s };
          final student = students[widget.studentId]; // provider에서 직접 가져오기
          final lessons = provider.lessons;

          return Scaffold(
            appBar: AppBar(
              title: Text("${student['name']}님의 캘린더",
                  style: style.copyWith(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
              backgroundColor: PRIMARY_COLOR,
              iconTheme: IconThemeData(color: Colors.white),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  TableCalendar(
                    firstDay: DateTime(2025, 1, 1),
                    lastDay: DateTime(2030, 12, 31),
                    focusedDay: focusedDate,
                    onDaySelected: (DateTime selectedDate, DateTime focusedDate) {
                      setState(() {
                        this.selectedDate = selectedDate;
                        this.focusedDate = focusedDate;
                      });
                    },
                    selectedDayPredicate: (day) => isSameDay(selectedDate, day),
                    eventLoader: (day) {
                      final provider = Provider.of<MasterProvider>(context);
                      final lessons = provider.lessons;
                      return _getEvents(day, lessons);
                    },
                    calendarBuilders: CalendarBuilders(
                      dowBuilder: (context, day) {
                        final text = DateFormat.E().format(day);
                        return Center(
                          child: Text(
                            text,
                            style: TextStyle(
                              fontFamily: 'OpenSans',
                              fontWeight: FontWeight.w500,
                              color: day.weekday == DateTime.sunday
                                  ? Colors.red
                                  : day.weekday == DateTime.saturday
                                  ? Colors.blue
                                  : Colors.black,
                            ),
                          ),
                        );
                      },
                      // 달력 속 날짜 숫자 색상 변경(요일에 맞게)
                      defaultBuilder: (context, day, _) {
                        return Center(
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                                color: day.weekday == 7
                                    ? Colors.red
                                    : day.weekday == 6
                                    ? Colors.blue
                                    : Colors.black),
                          ),
                        );
                      },
                      markerBuilder: (context, date, events) {
                        if (events.isNotEmpty) {
                          return Column(
                            children: [
                              const SizedBox(height: 45),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                    color: Color(0xff2E8B57),
                                    shape: BoxShape.circle),
                              ),
                            ],
                          );
                        }
                        return null;
                      },
                    ),
                    headerStyle: const HeaderStyle(
                      titleCentered: true,
                      formatButtonVisible: false,
                      titleTextStyle: TextStyle(
                        fontFamily: 'OpenSans',
                        fontWeight: FontWeight.w500,
                        fontSize: 20.0,
                      ),
                    ),
                    calendarStyle: const CalendarStyle(
                      isTodayHighlighted: true,
                      todayDecoration: BoxDecoration(
                        color: Color(0xff124736),
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: TextStyle(
                        color: Colors.white,
                        fontFamily: 'openSans',
                        fontWeight: FontWeight.w500,
                      ),
                      weekendDecoration: BoxDecoration(
                        shape: BoxShape.circle,
                      ),
                      weekendTextStyle: TextStyle(
                        color: Colors.red,
                        fontFamily: 'openSans',
                        fontWeight: FontWeight.w300,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: Color(0xff708C7A),
                        shape: BoxShape.circle,
                      ),
                      selectedTextStyle: TextStyle(
                        color: Colors.black,
                        fontFamily: 'openSans',
                        fontWeight: FontWeight.w500,
                      ),
                      defaultTextStyle: TextStyle(
                        fontFamily: 'openSans',
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    onPageChanged: (focusedDate) {
                      focusedDate = focusedDate;
                    },
                  ),
                  const SizedBox(height: 8),
                  TodayBanner(
                      selectedDate: selectedDate,
                      count: _getEvents(selectedDate, lessons).length),
                  const SizedBox(height: 8),
                  Expanded(
                          child: ListView.builder(
                            itemCount: _getEvents(selectedDate, lessons).length,
                            itemBuilder: (context, index) {
                              final lesson = _getEvents(selectedDate, lessons)[index];
                              String teacherName = teachers[lesson['teacherId']]['name'];
                              return Padding(
                                padding:
                                const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                child: Column(
                                  children: [
                                    LessonCardM(
                                      startTime: lesson['date'],
                                      endTime: lesson['date'].add(Duration(minutes: lesson['duration'])),
                                      month: lesson['date'].month,
                                      date: lesson['date'].day,
                                      student: student['name'],
                                      teacher: teacherName,
                                      onEdit: () {
                                        showEditLessonDialog(context, lesson);
                                      },
                                    ),
                                    SizedBox(height: 3,),
                                  ],
                                ),
                              );
                            },
                          ),
                      ),
                ],
              ),
            ),
          );
        });

  }
  // 특정 날짜의 수업을 가져옴
  List<Map<String, dynamic>> _getEvents(DateTime day, List<Map<String, dynamic>> lessons) {
    String formattedDay = DateFormat('yyyyMMdd').format(day);
    return lessons
        .where((lesson) =>
    lesson['studentId'] == widget.studentId &&  // 특정 학생의 수업만 가져오기
        DateFormat('yyyyMMdd').format(lesson['date']) == formattedDay &&
        lesson['status'] != 'canceled') // 'canceled' 상태 제외
        .toList();
  }
  void showEditLessonDialog(BuildContext context, Map<String, dynamic> lesson) {
    DateTime selectedDate = lesson['date'];
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(lesson['date']);
    int selectedDuration = lesson['duration'];
    String teacherId = lesson['teacherId'];
    String studentId = lesson['studentId'];
    String day = _getDayCode(selectedDate.weekday);
    bool applyToAll = false;
    bool isRescheduled = lesson['isRescheduled'] == true; // 수정된 수업(보강 포함)은 이후 일정에 똑같이 적용 불가능 (오류 지림)

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text("수업 수정", style: style.copyWith(fontSize: 20, fontWeight: FontWeight.w500, color: PRIMARY_COLOR)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 날짜 선택
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("날짜: ${DateFormat('yy.MM.dd').format(selectedDate)}", style: style.copyWith(fontSize: 18)),
                    ElevatedButton(
                      onPressed: () async {
                        DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2024, 1, 1),
                          lastDate: DateTime(2030, 12, 31),
                        );
                        if (pickedDate != null) {
                          setState(() {
                            selectedDate = pickedDate;
                            day = _getDayCode(pickedDate.weekday);
                          });
                        }
                      },
                      child: Icon(Icons.calendar_today, color: Colors.white, size: 20),
                      style: ElevatedButton.styleFrom(backgroundColor: Color(0xff3E6F58)),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // 시간 선택
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("시간: ${selectedTime.format(context)}", style: style.copyWith(fontSize: 18)),
                    ElevatedButton(
                      onPressed: () async {
                        TimeOfDay? pickedTime = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (pickedTime != null) {
                          setState(() {
                            selectedTime = pickedTime;
                          });
                        }
                      },
                      child: Icon(Icons.access_time_rounded, color: Colors.white, size: 20),
                      style: ElevatedButton.styleFrom(backgroundColor: Color(0xff3E6F58)),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // 수업 길이 선택
                DropdownButtonFormField<int>(
                  value: selectedDuration,
                  decoration: InputDecoration(border: OutlineInputBorder(), labelText: "수업 길이"),
                  items: [15, 30, 45, 60, 90].map((duration) {
                    return DropdownMenuItem(
                      value: duration,
                      child: Text("$duration 분", style: style),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      selectedDuration = newValue!;
                    });
                  },
                ),
                const SizedBox(height: 10),
                // 1) "이후 일정에도 적용" 체크 아이콘 + 텍스트
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (isRescheduled) {
                          // 이미 재조정된(isRescheduled = true) 수업이면
                          // "이후 일정에도 적용 불가" 안내 메시지만 띄우고, 토글은 안 함
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "이미 재조정된 수업이므로 이후 일정에 적용할 수 없습니다.",
                                style: style.copyWith(color: Colors.black),
                                textAlign: TextAlign.center,
                              ),
                              backgroundColor: IBORY,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        } else {
                          // 정상적으로 토글
                          setState(() {
                            applyToAll = !applyToAll;
                          });
                        }
                      },
                      child: Icon(
                        // 이미 재조정된 수업이면 -> 무조건 grey 아이콘
                        // 아니면 -> applyToAll 여부에 따라 색상/아이콘 변경
                        isRescheduled
                            ? Icons.check_circle_outline // 혹은 다른 아이콘
                            : (applyToAll ? Icons.check_circle : Icons.check_circle_outline),
                        color: isRescheduled
                            ? Colors.grey // 비활성화 색상
                            : (applyToAll ? PRIMARY_COLOR : Colors.grey),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 텍스트도 마찬가지로 회색 표시 or 그대로
                    Text(
                      "이후 일정에도 적용",
                      style: style.copyWith(
                        fontSize: 15,
                        color: isRescheduled ? Colors.grey : Colors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  bool confirm = await _showCancelConfirmationDialog(context);
                  if (confirm) {
                    await cancelLesson(lesson['id'], teacherId, studentId);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "수업이 취소 되었습니다!",
                          style: style.copyWith(color: Colors.black),
                          textAlign: TextAlign.center,
                        ),
                        backgroundColor: IBORY,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Text("수업 취소", style: style.copyWith(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
              ),
              // 취소 버튼
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("취소", style: style.copyWith(color: Colors.black)),
              ),

              // 저장 버튼 -> 적용 버튼 보이게 전환
              TextButton(
                onPressed: () async {

                  if (applyToAll) {
                    // 새로 바꿀 날짜/시간을 문자열 형식으로
                    final String day = _getDayCode(selectedDate.weekday);
                    final String formattedTime =
                        "${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}";

                    bool canProceed = canAddLessons_1(
                        studentId,
                        teacherId,
                        [{'day' : day, 'time': formattedTime, 'duration': selectedDuration, 'code': lesson['code']}]);
                    if (!canProceed) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "겹치는 정규 수업 일정이 존재 합니다 / 근무 시간이 아닙니다.",
                            style: style.copyWith(color: Colors.black),
                            textAlign: TextAlign.center,
                          ),
                          backgroundColor: IBORY,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      return;
                    }

                    // ─────────────────────────────────────────────────────────────
                    //  3) 모든 체크 통과 → 실제 업데이트 로직 (batch.update 등)
                    // ─────────────────────────────────────────────────────────────
                    await _updateLesson(
                      context,
                      lesson['id'],
                      teacherId,
                      studentId,
                      selectedDate,
                      selectedTime,
                      selectedDuration,
                      lesson['code'],
                      applyToAll: true,
                    );
                    Navigator.pop(context);
                  }
                  else {
                    // 현재 수업만 변경
                    // 변경하려는 날짜의 수업 예약만 확인해서 중복 제외함
                    bool canProceedBooked = canAddLessons_2(teacherId, [
                      // 새로 바꾸려는 이 수업에 대한 "날짜+시간+duration" 정보를 넣어야 함.
                      // 아래는 예시. lesson['date'] / selectedTime / selectedDuration
                      // 로직에 맞춰서 Map 구성
                      {
                        "id": lesson['id'],
                        "date": selectedDate,
                        "time": "${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}",
                        "duration": selectedDuration,
                      }
                    ]);
                    if (canProceedBooked) {
                      // 최종적으로 변경 로직( batch.update ) 실행
                      await _updateLesson(
                        context,
                        lesson['id'],
                        teacherId,
                        studentId,
                        selectedDate,
                        selectedTime,
                        selectedDuration,
                        lesson['code'],
                        applyToAll: applyToAll,
                      );
                      Navigator.pop(context);
                    }
                    else{
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "겹치는 수업이 존재하여 수정사항 적용이 불가능합니다.",
                            style: style.copyWith(color: Colors.black),
                            textAlign: TextAlign.center,
                          ),
                          backgroundColor: IBORY,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                },
                child: Text("저장", style: style.copyWith(color: PRIMARY_COLOR)),
              ),
            ],
          );
        });
      },
    );
  }
  // 수업이 이미 예약된 수업과 겹치지 않는지 확인
  bool canAddLessons_2(String teacherId, List<Map<String, dynamic>> lessons) {
    final provider = Provider.of<MasterProvider>(context, listen: false);
    final bookedSlots = provider.bookedSlots;
    if (!bookedSlots.containsKey(teacherId)) return true; // 예약된 수업 없음 → 추가 가능

    for (var lesson in lessons) {
      DateTime lessonDate = lesson["date"];
      int duration = lesson["duration"];
      String? lessonId = lesson["id"]; // 자기 자신 제외할 때 사용

      // 해당 선생님의 예약된 슬롯 가져오기
      final teacherLessons = bookedSlots[teacherId]!;

      // 1. 같은 날짜의 예약된 수업만 필터링 (자기 자신 제외)
      final filteredLessons = teacherLessons.entries.where((entry) {
        final String existingLessonId = entry.key;
        final DateTime bookedStart = entry.value['date'];

        if (existingLessonId == lessonId) return false; // 자기 자신 제외
        return bookedStart.year == lessonDate.year &&
            bookedStart.month == lessonDate.month &&
            bookedStart.day == lessonDate.day;
      }).toList();

      // 2. 필터링된 수업들과 겹치는지 검사
      for (var entry in filteredLessons) {
        final DateTime bookedStart = entry.value['date'];
        final int bookedDuration = entry.value['duration'];
        final DateTime bookedEnd = bookedStart.add(Duration(minutes: bookedDuration));

        // (lessonDate ~ lessonEnd) vs (bookedStart ~ bookedEnd)
        final DateTime lessonEnd = lessonDate.add(Duration(minutes: duration));
        if (lessonDate.isBefore(bookedEnd) && lessonEnd.isAfter(bookedStart)) {
          return false; // 겹침 발생
        }
      }
    }

    return true; // 모든 수업이 문제없으면 true
  }
  // 선생님 근무 시간, 담당 학생 정규 수업 시간 검사
  bool canAddLessons_1(String SID, String teacherId, List<Map<String, dynamic>> schedules) {
    final provider = Provider.of<MasterProvider>(context, listen: false);
    final Map<String, dynamic> teachers = { for (var t in provider.teachers) t['id']: t };
    final Map<String, dynamic> students = { for (var s in provider.students) s['id']: s };
    final workSchedule = provider.workSchedule;
    var teacher = teachers[teacherId];
    if (teacher == null) {
      debugPrint("선생님 ID $teacherId 없음.");
      return false;
    }
    var teacherWorkDays = workSchedule[teacherId];
    if (teacherWorkDays == null) {
      debugPrint("선생님 $teacherId의 근무 스케줄이 없음.");
      return false;
    }

    for (var lesson in schedules) {
      String day = lesson["day"];
      String startTime = lesson["time"];
      int duration = lesson["duration"];
      String code = lesson["code"];

      // ────────────────────────────────
      // 1. 교사 근무 시간 확인
      // ────────────────────────────────
      var teacherWorkTime = teacherWorkDays[day];
      if (teacherWorkTime == null) {
        debugPrint("선생님 $teacherId, 요일 $day에 근무 일정 없음.");
        return false;
      }

      if (!isWithinTimeRange(startTime, duration, teacherWorkTime["startTime"], teacherWorkTime["endTime"])) {
        debugPrint("수업 시간이 선생님의 근무 시간과 겹치지 않음 ($day, $startTime).");
        return false;
      }

      // ────────────────────────────────
      // 2. 학생 정규(주간) 수업과 겹침 검사
      // ────────────────────────────────

      List<String> studentIds = (teacher['studentIds'] as List<dynamic>?)?.cast<String>() ?? [];
      for (String studentId in studentIds) {
        var student = students[studentId];
        if (student == null) continue;

        List<Map<String, dynamic>> weeklySchedule = List<
            Map<String, dynamic>>.from(student['weeklySchedule'] ?? []);
        for (var studentLesson in weeklySchedule) {
          // 자기 자신의 기존 수업은 검사 제외
          if ( SID == studentId && studentLesson['code'] == code) continue;
          if (studentLesson['day'] == day) {
            if (isOverlapping(startTime, duration, studentLesson['startTime'],
                studentLesson['duration'])) {
              debugPrint("학생 $studentId의 기존 수업과 겹침 ($day, $startTime).");
              return false;
            }
          }
        }
      }
    }
    return true;
  }

}

String _getDayCode(int weekday) {
  Map<int, String> dayMap = {
    1: "MO", // 월요일
    2: "TU", // 화요일
    3: "WE", // 수요일
    4: "TH", // 목요일
    5: "FR", // 금요일
    6: "SA", // 토요일
    7: "SU", // 일요일
  };
  return dayMap[weekday] ?? "MO"; // 기본값은 "MO" (예외 방지)
}
// 수업 업데이트 함수
Future<void> _updateLesson(
    BuildContext context,
    String lessonId,
    String teacherId,
    String studentId,
    DateTime newDate,
    TimeOfDay newTime,
    int newDuration,
    String lessonCode,{
      required bool applyToAll,
    }) async
{
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  FieldValue UpdateTime = FieldValue.serverTimestamp();

  // ① 글로벌 lessons 컬렉션 참조
  CollectionReference globalLessonsRef = firestore.collection('lessons');
  // ② 선생님 availableSlots 문서 참조 (선생님 아이디를 문서 ID로 사용)
  DocumentReference teacherSlotRef = firestore.collection('availableSlots').doc(teacherId);
  // ③ 학생 레슨 하위 컬렉션 참조
  CollectionReference studentLessonsCollection =
  firestore.collection('users').doc(studentId).collection('lessons');

  // newDate와 newTime을 결합한 새로운 날짜 시간
  DateTime updatedDateTime = DateTime(
    newDate.year,
    newDate.month,
    newDate.day,
    newTime.hour,
    newTime.minute,
  );

  WriteBatch batch = firestore.batch();

  if (applyToAll) {

    // 0. 'users' 컬렉션에 있는 기본 수업 정보도 변경
    DocumentReference userDocRef = firestore.collection('users').doc(studentId);
    DocumentSnapshot userDoc = await userDocRef.get();
    // 캐스팅: DocumentSnapshot의 data()는 Object? 형태이므로 Map<String, dynamic>?로 변환
    Map<String, dynamic>? userData = userDoc.data() as Map<String, dynamic>?;

    // 널 세이프티 적용: userData가 null이면 빈 리스트를, 아니면 weeklySchedule을 가져오기
    List<dynamic> weeklySchedule = userData?['weeklySchedule'] as List<dynamic>? ?? [];

    // TimeOfDay를 HH:mm 형식의 문자열로 변환
    final String formattedTime = "${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}";

    // 특정 코드 값만 찾아 업데이트
    for (var scheduleItem in weeklySchedule) {
      if (scheduleItem['code'] == lessonCode) {
        scheduleItem['day'] = _getDayCode(updatedDateTime.weekday);
        scheduleItem['startTime'] = formattedTime;
        scheduleItem['duration'] = newDuration;
      }
    }

    // weeklySchedule 업데이트
    batch.update(userDocRef, {
      'weeklySchedule': weeklySchedule,
    });

    // 먼저 업데이트 대상 수업(lessonId)의 기존 날짜와 code 값을 가져옴
    DocumentSnapshot updatedLessonDoc = await globalLessonsRef.doc(lessonId).get();
    Map<String, dynamic> lessonData = updatedLessonDoc.data() as Map<String, dynamic>;

    // 기존 날짜 및 code 값 저장
    DateTime originalUpdatedLessonDate = (lessonData['date'] as Timestamp).toDate();

    // 먼저 업데이트 대상 수업(lessonId)의 기존 날짜를 가져와 offset을 계산합니다.
    Duration offset = updatedDateTime.difference(originalUpdatedLessonDate);

    // 학생의 lessons 하위 컬렉션에서,
    // 1 'date'가 변경 기준 날짜 이후
    // 2 'code'가 같은 수업
    // 3 'isRescheduled'가 false (이미 변경된 수업 제외)
    QuerySnapshot snapshot = await studentLessonsCollection
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(originalUpdatedLessonDate))
        .where('code', isEqualTo: lessonCode) // 동일한 'code' 값인 수업만 가져오기
        .where('isRescheduled', isEqualTo: false) // 기존 변경된 수업 제외
        .get();

    // 선생님 문서 업데이트를 위한 맵 구성
    Map<String, dynamic> teacherSlotUpdates = {};

    for (var doc in snapshot.docs) {
      String docId = doc.id;
      // 기존 레슨의 날짜
      DateTime originalLessonDate = (doc.data() as Map<String, dynamic>)['date'].toDate();
      // 각 레슨에 offset을 적용하여 새로운 날짜 계산
      DateTime newLessonDate = originalLessonDate.add(offset);
      // 학생의 lessons 하위 컬렉션 업데이트
      batch.update(studentLessonsCollection.doc(docId), {
        'date': Timestamp.fromDate(newLessonDate),
        'duration': newDuration,
        'updatedAt': UpdateTime,
      });
      // 글로벌 lessons 컬렉션 업데이트
      batch.update(globalLessonsRef.doc(docId), {
        'date': Timestamp.fromDate(newLessonDate),
        'duration': newDuration,
        'updatedAt': UpdateTime,
      });

      // 선생님 bookedSlots 맵 업데이트를 teacherSlotUpdates에 추가
      teacherSlotUpdates['bookedSlots.$docId.date'] = Timestamp.fromDate(newLessonDate);
      teacherSlotUpdates['bookedSlots.$docId.duration'] = newDuration;
    }
    if (teacherSlotUpdates.isNotEmpty) {
      batch.update(teacherSlotRef, teacherSlotUpdates);
    }
  }
  else {
    // 단일 레슨 업데이트 (lessonId 기준)
    batch.update(studentLessonsCollection.doc(lessonId), {
      'date': Timestamp.fromDate(updatedDateTime),
      'duration': newDuration,
      'isRescheduled' : true,
      'updatedAt' : UpdateTime,
      'RescheduledBy' : 'master'
    });
    batch.update(globalLessonsRef.doc(lessonId), {
      'date': Timestamp.fromDate(updatedDateTime),
      'duration': newDuration,
      'isRescheduled' : true,
      'updatedAt' : UpdateTime,
      'RescheduledBy' : 'master'
    });
    batch.update(teacherSlotRef, {
      'bookedSlots.$lessonId.date': Timestamp.fromDate(updatedDateTime),
      'bookedSlots.$lessonId.duration': newDuration,
      'bookedSlots.$lessonId.isRescheduled' : true,
    });
  }

  await batch.commit();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        "수업이 수정되었습니다.",
        style: style.copyWith(color: Colors.black),
        textAlign: TextAlign.center,
      ),
      backgroundColor: IBORY,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      duration: Duration(seconds: 2),
    ),
  );
}

// 수업 삭제 다이얼로그
Future<bool> _showCancelConfirmationDialog(BuildContext context) async {
  return await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("수업 취소", style: style.copyWith(fontSize: 20)),
      content: Text("정말로 이 수업을 취소하시겠습니까?", style: style.copyWith(fontSize: 18)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text("아니요", style: style),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          child: Text("예", style: style),
        ),
      ],
    ),
  ) ?? false;
}

// 수업 삭제 함수
Future<void> cancelLesson(String lessonId, String teacherId, String studentId) async {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final CollectionReference lessonsRef = firestore.collection('lessons');
  final DocumentReference teacherSlotRef = firestore.collection('availableSlots').doc(teacherId);
  final CollectionReference studentLessonsCollection =
  firestore.collection('users').doc(studentId).collection('lessons');

  WriteBatch batch = firestore.batch();
  FieldValue serverTimestamp = FieldValue.serverTimestamp();

  try {

    // 1 lesson 컬렉션에서 해당 레슨 문서 상태 변경 (canceled)
    final lessonDocRef = lessonsRef.doc(lessonId);
    batch.update(lessonDocRef, {
      'status': 'canceled',
      'canceledBy': 'master',     // 누가 취소했는지 기록
      'updatedAt': serverTimestamp,
    });

    // 2 선생님 availableSlots - bookedSlots 맵 필드에서 해당 수업 삭제
    batch.update(teacherSlotRef, {
      'bookedSlots.$lessonId': FieldValue.delete(), // bookedSlots 맵에서 해당 레슨 ID 삭제
    });

    // 3 학생 레슨 컬렉션에서 해당 수업 상태 변경 (canceled)
    final studentLessonDocRef = studentLessonsCollection.doc(lessonId);
    batch.update(studentLessonDocRef, {
      'status': 'canceled',
      'canceledBy': 'master',     // 누가 취소했는지 기록
      'updatedAt': serverTimestamp,
    });

    // 변경 사항 적용
    await batch.commit();
    print("수업 취소 완료: lessonId: $lessonId");
  } catch (e) {
    print("수업 취소 실패: $e");
    throw Exception("수업 취소 중 오류 발생");
  }
}
