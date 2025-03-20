import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'LessonE.dart';

class EditStudentPage extends StatefulWidget {
  final Map<String, dynamic> student;

  EditStudentPage({required this.student});

  @override
  _EditStudentPageState createState() => _EditStudentPageState();
}

class _EditStudentPageState extends State<EditStudentPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String selectedTeacherId = "";
  String selectedTeacherName = "";
  List<Map<String, dynamic>> scheduleList = []; // 여러 개의 수업 스케줄 저장

  String selectedDay = "MO";
  String selectedTime = "16:00";
  int selectedDuration = 60;
  // 상태 변수 선언 (State 클래스 내)
  bool isChecked = true; // 기본 체크된 상태
  DateTime n = DateTime.now();

  // 초기값을 저장한 리스트 (예: initState에서 deep copy)
  late List<Map<String, dynamic>> originalScheduleList;

  // 적용 시작 날짜 (기본값은 오늘)
  DateTime applyStartDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.student['name'];
    _passwordController.text = widget.student['password'].toString();
    selectedTeacherId = widget.student['teacherId'];

    List<dynamic> schedule = widget.student['weeklySchedule'] ?? [];
    if (schedule.isNotEmpty) {
      selectedDay = schedule[0]['day'];
      selectedTime = schedule[0]['startTime'];
      selectedDuration = schedule[0]['duration'];
    }
    scheduleList = List<Map<String, dynamic>>.from(widget.student['weeklySchedule'] ?? []);
    // deep copy (간단하게 각 맵을 복사) (원본을 저장)
    originalScheduleList = scheduleList.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // 선생님 근무 시간, 담당 학생 정규 수업 시간 검사
  bool canAddLessons(String SID, String teacherId, List<Map<String, dynamic>> schedules) {
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
      String startTime = lesson["startTime"];
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
        debugPrint("수업 시간이 선생님의 근무 시간과 겹치지 않음 ($day, $startTime, $duration, "
            "${teacherWorkTime["startTime"]}, ${teacherWorkTime["endTime"]}).");
        return false;
      }
      print('검사 끝');
      // ────────────────────────────────
      // 2. 학생 정규(주간) 수업과 겹침 검사
      // ────────────────────────────────
      print('다른 학생 일정과 확인 시작');
      List<String> studentIds = (teacher['studentIds'] as List<dynamic>?)?.cast<String>() ?? [];
      print('학생 정보 가져오기');
      for (String studentId in studentIds) {
        var student = students[studentId];
        if (student == null) continue;
        List<Map<String, dynamic>> weeklySchedule = List<
            Map<String, dynamic>>.from(student['weeklySchedule'] ?? []);
        for (var studentLesson in weeklySchedule) {
          // 자기 자신의 기존 수업은 검사 제외
          if ( SID == studentId && studentLesson['code'] == code) continue;
          print('자기 자신은 제외하고 검사중');
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

  // 실행 함수 1
  Future<void> updateFunction1(
      DateTime resetDate,
      String studentId,
      String oldTeacherId,
      String newTeacherId,
      List<Map<String, dynamic>> scheduleList,
      ) async
  {
    // 학생의 미래 수업 모두 삭제.
    // 신규 학생 등록할 때 처럼 새로운 스케줄로 등록.

    FirebaseFirestore firestore = FirebaseFirestore.instance;
    WriteBatch batch = firestore.batch();
    FieldValue serverTimestamp = FieldValue.serverTimestamp();

    final provider = Provider.of<MasterProvider>(context, listen: false);
    final Map<String, dynamic> students = { for (var s in provider.students) s['id']: s };
    CollectionReference lessonsRef = firestore.collection('lessons');
    DocumentReference studentDocRef = firestore.collection('users').doc(studentId);
    CollectionReference studentLessonsRef = firestore.collection('users').doc(studentId).collection('lessons');
    DocumentReference oldTeacherSlotRef = firestore.collection('availableSlots').doc(oldTeacherId);
    DocumentReference newTeacherSlotRef = firestore.collection('availableSlots').doc(newTeacherId);

    // 1. 기존 수업 삭제 (보강 수업 제외) - 로컬 필터링
    List<Map<String, dynamic>> existingLessons = students[studentId]?['lessons'] ?? [];
    List<String> deletedLessonIds = existingLessons
        .where((lesson) => lesson['date'].isAfter(resetDate) && lesson['code'] != '-1') // 미래 수업 + 보강 수업 제외
        .map((lesson) => lesson['id'].toString()) // lessonId 추출
        .toList();

    // 2. 학생의 lessons 컬렉션 및 전체 lessons 컬렉션에서 삭제
    if (deletedLessonIds.isNotEmpty) {
      debugPrint("삭제할 수업 IDs: $deletedLessonIds");

      for (var lessonId in deletedLessonIds) {
        batch.delete(lessonsRef.doc(lessonId)); // 전체 lessons 컬렉션에서 삭제
        batch.delete(studentLessonsRef.doc(lessonId)); // 학생 레슨 문서 삭제
        batch.update(oldTeacherSlotRef, {
          'bookedSlots.$lessonId': FieldValue.delete(), // 선생님 bookedSlots에서 삭제
        });
      }
    }
    // 3. 새로운 수업 추가
    List<Map<String, dynamic>> allGeneratedLessons = [];
    for (var schedule in scheduleList) {
      allGeneratedLessons.addAll(generateLessons(
        getFirstLessonAfterN(resetDate, schedule),
        schedule['duration'],
        studentId,
        newTeacherId,
        schedule['code'],
      ));
    }

    // 4. 새로운 수업 추가
    if (allGeneratedLessons.isNotEmpty) {
      debugPrint("저장할 새로운 수업 개수: ${allGeneratedLessons.length}");

      for (var lesson in allGeneratedLessons) {
        DocumentReference lessonDocRef = lessonsRef.doc();
        String lessonId = lessonDocRef.id;

        Map<String, dynamic> lessonData = {
          'code': lesson['code'],
          'date': lesson['date'],
          'duration': lesson['duration'],
          'isRescheduled': lesson['isRescheduled'],
          'studentId': studentId,
          'teacherId': newTeacherId,
          'status': lesson['status'],
          'createdAt': serverTimestamp,
          'updatedAt': serverTimestamp,
        };

        batch.set(lessonDocRef, lessonData); // lessons 컬렉션 추가
        batch.set(studentLessonsRef.doc(lessonId), lessonData); // 학생 lessons 추가
        batch.set(
            newTeacherSlotRef,
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
        ); // 선생님 bookedSlots 업데이트
      }
    }

    // 5. 학생 스케줄 전부 변경
    List<Map<String, dynamic>> newWeeklySchedule = scheduleList.map((schedule) {
      return {
        'code': schedule['code'],
        'day': schedule['day'],
        'duration': schedule['duration'],
        'startTime': schedule['startTime'],
      };
    }).toList();

    batch.update(studentDocRef, {'weeklySchedule': newWeeklySchedule});


    // 6. 배치 실행 (삭제 + 저장 + `weeklySchedule` 업데이트 한 번에 처리)
    if (deletedLessonIds.isNotEmpty || allGeneratedLessons.isNotEmpty) {
      await batch.commit();
      debugPrint("기존 수업 삭제 및 새로운 수업 저장 완료");
    } else {
      debugPrint("변경할 사항 없음.");
    }
  }

  // 실행 함수 2
  Future<void> updateFunction2(
      DateTime resetDate,
      String studentId,
      String teacherId,
      List<Map<String, dynamic>> scheduleList,
      List<Map<String, dynamic>> originalScheduleList,
      ) async
  {

    FirebaseFirestore firestore = FirebaseFirestore.instance;
    WriteBatch batch = firestore.batch();
    FieldValue serverTimestamp = FieldValue.serverTimestamp();

    final provider = Provider.of<MasterProvider>(context, listen: false);
    final Map<String, dynamic> students = { for (var s in provider.students) s['id']: s };
    DateTime tomorrowMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

    CollectionReference lessonsRef = firestore.collection('lessons');
    DocumentReference teacherSlotRef = firestore.collection('availableSlots').doc(teacherId);
    DocumentReference studentDocRef = firestore.collection('users').doc(studentId);
    CollectionReference studentLessonsRef = studentDocRef.collection('lessons');

    // 프로바이더에 저장된 학생 수업 정보
    List<Map<String, dynamic>> existingLessons = students[studentId]?['lessons'] ?? [];

    // 1. 삭제된 수업, 수정된 수업 코드 추출
    Set<String> currentCodes = scheduleList.map((e) => e['code'] as String).toSet();
    List<String> deletedCodes = originalScheduleList
        .where((e) => !currentCodes.contains(e['code'])) // 기존에 있었으나 현재 없어진 경우
        .map((e) => e['code'] as String)
        .toList();

    Map<String, Map<String, dynamic>> originalMap = {
      for (var e in originalScheduleList) e['code'] as String: e
    };

    List<String> modifiedCodes = scheduleList
        .where((e) =>
    originalMap.containsKey(e['code'] as String) &&
        (e['day'] != originalMap[e['code']]!['day'] ||
            e['duration'] != originalMap[e['code']]!['duration'] ||
            e['startTime'] != originalMap[e['code']]!['startTime']))
        .map((e) => e['code'] as String)
        .toList();

    Set<String> codesToDelete = {...deletedCodes, ...modifiedCodes}; // 삭제해야 할 모든 코드 합치기

    // 2. 새로 추가된 코드 찾기
    Set<String> originalCodes = originalScheduleList.map((e) => e['code'].toString()).toSet();
    List<String> newCodes = scheduleList
        .where((e) => !originalCodes.contains(e['code'].toString())) // 기존에 없던 새로운 코드
        .map((e) => e['code'].toString())
        .toList();

    Set<String> codesToCreate = {...newCodes, ...modifiedCodes.map((e) => e.toString())};

    // 삭제
    if(codesToDelete.isNotEmpty) {
      debugPrint("삭제할 수업 코드: $codesToDelete");

      List<String> lessonIdsToDelete = existingLessons
          .where((lesson) =>
      lesson['date'].isAfter(tomorrowMidnight) &&
          lesson['code'] != "-1" && // 보강 수업 제외 (String 비교)
          codesToDelete.contains(lesson['code'].toString())) // String 변환 후 비교
          .map((lesson) => lesson['id'].toString())
          .toList();

      if (lessonIdsToDelete.isNotEmpty) {
        for (String lessonId in lessonIdsToDelete) {
          batch.delete(studentLessonsRef.doc(lessonId)); // 학생 lessons에서 삭제
          batch.delete(lessonsRef.doc(lessonId)); // 글로벌 lessons에서 삭제
          batch.update(teacherSlotRef, {
            'bookedSlots.$lessonId': FieldValue.delete(), // 선생님 bookedSlots에서 삭제
          });
        }
      }
    }

    // 생성
    for (var schedule in scheduleList) {
      if (codesToCreate.contains(schedule['code'])){
        List<Map<String, dynamic>> generatedLessons = generateLessons(
          getFirstLessonAfterN(resetDate, schedule),
          schedule['duration'],
          studentId,
          teacherId,
          schedule['code'],
        );
        for(var lesson in generatedLessons) {
          DocumentReference lessonDocRef = lessonsRef.doc();
          String lessonId = lessonDocRef.id;

          Map<String, dynamic> lessonData = {
            'code': lesson['code'],
            'date': lesson['date'],
            'duration': lesson['duration'],
            'isRescheduled': lesson['isRescheduled'],
            'studentId': studentId,
            'teacherId': teacherId,
            'status': lesson['status'],
            'createdAt': serverTimestamp,
            'updatedAt': serverTimestamp,
          };

          batch.set(lessonDocRef, lessonData); // lessons 컬렉션에 저장
          batch.set(studentLessonsRef.doc(lessonId), lessonData); // 학생 lessons에 저장
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
            SetOptions(merge: true),
          ); // 선생님 bookedSlots에 저장
        }
      }
    }

    // 3. 정규 스케줄 업데이트
    List<Map<String, dynamic>> newWeeklySchedule = scheduleList.map((schedule) {
      return {
        'code': schedule['code'],
        'day': schedule['day'],
        'duration': schedule['duration'],
        'startTime': schedule['startTime'],
      };
    }).toList();

    batch.update(studentDocRef, {'weeklySchedule': newWeeklySchedule});

    // 4. 배치 실행 (삭제 + 저장 + `weeklySchedule` 업데이트 한 번에 처리)
    if (codesToDelete.isNotEmpty || codesToCreate.isNotEmpty) {
      await batch.commit();
      debugPrint("기존 수업 삭제 및 새로운 수업 저장 완료");
    } else {
      debugPrint("변경할 사항 없음.");
    }
  }

  // 레슨 생성 함수
  List<Map<String, dynamic>> generateLessons(
      DateTime firstLessonDate, int duration, String studentId, String teacherId, String code)
  {
    List<Map<String, dynamic>> lessons = [];

    // 현재 학기 및 다음 2개 학기 찾기
    List<String> semesterTerms = [];  // 현재 +2 학기의 키 리스트
    DateTime lessonDate = firstLessonDate; // 레슨 시작 날짜
    for (String semesterId in SemesterTerm.keys) {
      DateTime start = SemesterTerm[semesterId]!['startDate'];
      DateTime end = SemesterTerm[semesterId]!['endDate'];

      if (start.isBefore(firstLessonDate) && end.isAfter(firstLessonDate)) {
        semesterTerms.add(semesterId);  // 현재 학기 추가

        // 다음 2개 학기 추가
        for (int i = 1; i <= 2; i++) {
          int nextYear = int.parse(semesterId.split('-')[0]);
          int nextMonth = int.parse(semesterId.split('-')[1]) + i;

          if (nextMonth > 12) {
            nextMonth -= 12;
            nextYear++;
          }

          String nextSemesterKey = "$nextYear-${nextMonth.toString().padLeft(2, '0')}";
          if (SemesterTerm.containsKey(nextSemesterKey)) {
            semesterTerms.add(nextSemesterKey);
          }
        }
        break;
      }
    }

    // 학기별 레슨 생성 (현재 학기 ~ +2 학기)
    for (int i = 0; i < semesterTerms.length; i++) {
      String semesterKey = semesterTerms[i];
      DateTime semesterEnd = SemesterTerm[semesterKey]!['endDate'].add(Duration(days: 1)); // 학기 마지막 날 ...!
      List<Map<String, DateTime>> holidays = SemesterTerm[semesterKey]!['holidays'];

      int count = 0;
      while (!lessonDate.isAfter(semesterEnd)) {
        if (!isHoliday(lessonDate, holidays)) {
          lessons.add({
            "code": code,
            "date": lessonDate,
            "duration": duration,
            "studentId": studentId,
            "teacherId": teacherId,
            "isRescheduled": false,
            "status": "confirmed",
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
          });

          // 다음 학기에서는 최대 4회까지만 생성
          if (i > 0) count++;
        }
        // 주 단위 증가
        lessonDate = lessonDate.add(Duration(days: 7));

        // 다음 학기에서 4개 생성되면 종료
        if (i > 0 && count >= 4) break;
      }
    }

    return lessons;
  }

  void _confirmDeleteLesson(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("수업 삭제", style: style),
          content: Text("예약된 모든 수업이 삭제됩니다.\n삭제하시겠습니까?", style: style),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), // 취소 버튼
              child: Text("취소", style: style.copyWith(color: Colors.black54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteLesson(index);
              },
              child: Text("삭제", style: style.copyWith(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
  // Future<void> deleteFutureLessons(String studentId, String teacherId, String lessonCode) async {
  //   FirebaseFirestore firestore = FirebaseFirestore.instance;
  //   WriteBatch batch = firestore.batch();
  //
  //   // ① 글로벌 lessons 컬렉션 참조
  //   CollectionReference globalLessonsRef = firestore.collection('lessons');
  //   // ② 선생님 availableSlots 문서 참조 (선생님 아이디를 문서 ID로 사용)
  //   DocumentReference teacherSlotRef = firestore.collection('availableSlots').doc(teacherId);
  //   // ③ 학생 레슨 하위 컬렉션 참조
  //   CollectionReference studentLessonsCollection =
  //   firestore.collection('users').doc(studentId).collection('lessons');
  //   // ④ 학생 문서 참조 (weeklySchedule 수정)
  //   DocumentReference studentDocRef = firestore.collection('users').doc(studentId);
  //
  //   // 현재 시간 이후의 같은 code 값을 가진 수업들 조회 (lessonCode를 String으로 비교)
  //   QuerySnapshot snapshot = await studentLessonsCollection
  //       .where('date', isGreaterThanOrEqualTo: Timestamp.now()) // 현재 이후의 수업만 삭제
  //       .where('code', isEqualTo: lessonCode) // 같은 code 값을 가진 수업만 삭제
  //       .get();
  //
  //   List<String> lessonIds = snapshot.docs.map((doc) => doc.id).toList();
  //
  //   // 삭제할 lessonId 리스트를 기반으로 모든 컬렉션에서 삭제
  //   for (String lessonId in lessonIds) {
  //     batch.delete(studentLessonsCollection.doc(lessonId)); // 학생 레슨에서 삭제
  //     batch.delete(globalLessonsRef.doc(lessonId)); // 글로벌 lessons에서 삭제
  //     batch.update(teacherSlotRef, {
  //       'bookedSlots.$lessonId': FieldValue.delete(), // 선생님 bookedSlots에서 삭제
  //     });
  //   }
  //
  //   // weeklySchedule에서 해당 code 값을 가진 요소 삭제
  //   DocumentSnapshot studentSnapshot = await studentDocRef.get();
  //   if (studentSnapshot.exists) {
  //     Map<String, dynamic> studentData = studentSnapshot.data() as Map<String, dynamic>;
  //     List<Map<String, dynamic>> weeklySchedule =
  //     List<Map<String, dynamic>>.from(studentData['weeklySchedule'] ?? []);
  //
  //     // 같은 `code` 값을 가진 요소 제거 후 Firestore에 업데이트
  //     List<Map<String, dynamic>> updatedSchedule =
  //     weeklySchedule.where((lesson) => lesson['code'] != lessonCode).toList();
  //
  //     batch.update(studentDocRef, {'weeklySchedule': updatedSchedule});
  //   }
  //
  //   // 모든 삭제 연산 실행
  //   await batch.commit();
  //
  //   print("수업 삭제 완료: lessonCode = $lessonCode");
  // }
  void _deleteLesson(int index) {
    setState(() {
      scheduleList.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final masterProvider = Provider.of<MasterProvider>(context); // 마스터 프로바이더 사용
    List<Map<String, dynamic>> teachers = masterProvider.teachers; // 로그인 시 불러온 선생님 목록 사용

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.student['name']}님 정보 수정", style: style.copyWith(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
        backgroundColor: PRIMARY_COLOR,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("이름", style: style.copyWith(color: Color(0xff3E6F58), fontSize: 18, fontWeight: FontWeight.w500)),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(border: OutlineInputBorder(), hintText: "이름 입력"),
            ),
            SizedBox(height: 10),

            Text("비밀번호", style: style.copyWith(color: Color(0xff3E6F58), fontSize: 18, fontWeight: FontWeight.w500)),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(border: OutlineInputBorder(), hintText: "비밀번호 입력"),
              obscureText: false,
            ),
            SizedBox(height: 10),

            // 담당 선생님 선택
            Text("담당 선생님", style: style.copyWith(color: Color(0xff3E6F58), fontSize: 18, fontWeight: FontWeight.w500)),
            DropdownButtonFormField<String>(
              value: selectedTeacherId,
              decoration: InputDecoration(border: OutlineInputBorder()),
              items: teachers.map<DropdownMenuItem<String>>((teacher) {
                return DropdownMenuItem<String>(
                  value: teacher['id'].toString(), // String 변환 추가
                  child: Text(teacher['name'], style: style),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  selectedTeacherId = newValue!;
                  selectedTeacherName = getName(selectedTeacherId, teachers);
                });
              },
            ),
            SizedBox(height: 10),
            if (selectedTeacherId != widget.student['teacherId'])
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 체크박스와 문구 Row
                  Row(
                    children: [
                      Checkbox(
                        value: isChecked,
                        onChanged: (value) {
                          setState(() {
                            isChecked = value!;
                          });
                        },
                      ),
                      Text('오늘 이후 모든 수업의 담당이 변경됩니다', style: style),
                    ],
                  ),
                  // 체크박스가 해제된 경우 날짜 선택 Row 노출
                  if (!isChecked)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "변경을 적용할 날짜: ${DateFormat('yy.MM.dd').format(n)}",
                          style: style,
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            DateTime? pickedDate = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2024, 1, 1),
                              lastDate: DateTime(2030, 12, 31),
                            );
                            if (pickedDate != null) {
                              setState(() {
                                n = pickedDate;
                              });
                            }
                          },
                          child: Icon(Icons.calendar_today, color: Colors.white, size: 20),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3E6F58)),
                        ),
                      ],
                    ),
                ],
              ),
            Expanded(
              child: ListView.builder(
                itemCount: scheduleList.length,
                itemBuilder: (context, index) {
                  final schedule = scheduleList[index];
                  int duration = schedule['duration'] as int;

                  // 끝나는 시간 계산을 위해 DateTime으로 변환
                  DateTime startDateTime = parseTime(schedule['startTime']);
                  DateTime endDateTime = startDateTime.add(Duration(minutes: duration));

                  // 출력에 맞게 정제한 문자열변수
                  final formattedStartTime = schedule['startTime'];
                  final formattedEndTime = "${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}";

                  // 요일 코드(MO, TU, ...)를 한글 요일명으로 변환
                  final Map<String, String> dayMap = {
                    'MO': '월',
                    'TU': '화',
                    'WE': '수',
                    'TH': '목',
                    'FR': '금',
                    'SA': '토',
                    'SU': '일',
                  };
                  String dayName = dayMap[schedule['day']] ?? schedule['day'];

                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Color(0xff3E6F58), width: 1),
                    ),
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("수업 ${index + 1}",
                                  style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: Color(0xff3E6F58))),
                              Row(
                                children: [
                                  IconButton(
                                      onPressed: (){
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => EditLessonPage(
                                              studentName: widget.student['name'],
                                              teacherName: getName(widget.student['teacherId'], teachers),
                                              index: index,
                                              lesson: scheduleList[index],
                                              isNewLesson: false, // 기존 수업 수정
                                              onSave: (updatedLesson) {
                                                setState(() {
                                                  String code = scheduleList[index]['code'];
                                                  updatedLesson['code'] = code;
                                                  // 수정한 수업의 코드를 넣어줘야함
                                                  scheduleList[index] = updatedLesson;
                                                });
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                      icon: Icon(Icons.edit, color: PRIMARY_COLOR)
                                  ),
                                  // 삭제 버튼 (index가 0인 경우 숨김)
                                  if (index > 0)
                                    IconButton(
                                      icon: Icon(Icons.delete, color: Colors.red),
                                      onPressed: () {
                                        _confirmDeleteLesson(context, index);
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // 수업 요일 & 시간 표시
                          Text(
                            "$dayName요일 $formattedStartTime ~ $formattedEndTime",
                            style: style.copyWith(fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditLessonPage(
                        studentName: widget.student['name'],
                        teacherName: getName(widget.student['teacherId'], teachers),
                        isNewLesson: true, // 새로운 수업 추가 모드
                        onSave: (newLesson) {
                          setState(() {
                            int nextCode = scheduleList.isNotEmpty
                                ? scheduleList.map((lesson) => int.parse(lesson['code'] as String))
                                .reduce((a, b) => a > b ? a : b) + 1
                                : 0;
                            newLesson['code'] = nextCode.toString();
                            scheduleList.add(newLesson);
                          });
                        },
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.add, color: Color(0xff3E6F58)),
                label: Text("수업 추가", style: style.copyWith(color: Color(0xff3E6F58))),
              ),
            ),
            Center(
              child: ElevatedButton(
                onPressed: () async {
                  showLoadingDialog(context, '변경 사항 저장중 ...');
                  try {
                    print('조건 검사 함수 시작 전');
                    bool canProceed = canAddLessons(widget.student['id'], selectedTeacherId, scheduleList);
                    print('조건 검사 함수 시행 끝');
                    if (!canProceed) {
                      debugPrint("수업 추가 불가능: 선생님 근무 시간 또는 다른 학생 정규 수업과 겹침");
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          "선생님 근무 시간 / 다른 학생 정규 수업을 확인해주세요.",
                          style: style.copyWith(color: Colors.black), // 검은색 글씨
                          textAlign: TextAlign.center, // 중앙 정렬
                        ),
                        backgroundColor: IBORY,
                        behavior: SnackBarBehavior.floating, // 살짝 떠 있는 느낌
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8), // 둥근 모서리
                        ),
                        duration: Duration(seconds: 2),
                      ));
                      return;
                    } else {
                      print('선생님 변경 여부 확인');
                      bool isTeacherChanged = (selectedTeacherId != widget.student['teacherId']);

                      if (isTeacherChanged) {
                        // 실행 함수 1 (선생님 변경됨)
                        print('선생님 변경됨');
                        await updateFunction1(
                            n,
                            widget.student['id'],
                            widget.student['teacherId'],
                            selectedTeacherId,
                            scheduleList
                        );
                      } else {
                        // 실행 함수 2 (선생님 변경 안 됨)
                        print('선생님 변경 안 됨');
                        await updateFunction2(
                            n,
                            widget.student['id'],
                            selectedTeacherId,
                            scheduleList,
                            originalScheduleList
                        );
                      }
                      Navigator.pop(context); // 모든 작업 완료 후 로딩 다이얼로그 닫기
                      // 성공 메시지 표시
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "변경 사항이 성공적으로 저장되었습니다.",
                            style: style.copyWith(color: Colors.black),
                            textAlign: TextAlign.center,
                          ),
                          backgroundColor: Color(0xff3E6F58), // 성공 메시지는 초록색 계열 추천
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (error) {
                    debugPrint("오류 발생: $error");
                    Navigator.of(context).pop(); // 로딩 다이얼로그 닫기

                    // 오류 메시지 표시
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "변경 사항 저장 중 오류가 발생했습니다. 다시 시도해주세요.",
                          style: style.copyWith(color: Colors.black),
                          textAlign: TextAlign.center,
                        ),
                        backgroundColor: Colors.redAccent, // 오류 메시지는 빨간색 계열
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: PRIMARY_COLOR,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                ),
                child: Text("저장", style: style.copyWith(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
String getDayCode(int weekday) {
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
DateTime getFirstLessonAfterN(DateTime n, Map<String, dynamic> weeklySchedule) {
  Map<String, int> dayMap = {
    'MO': DateTime.monday,
    'TU': DateTime.tuesday,
    'WE': DateTime.wednesday,
    'TH': DateTime.thursday,
    'FR': DateTime.friday,
    'SA': DateTime.saturday,
    'SU': DateTime.sunday,
  };
  String day = weeklySchedule['day']; // 요일 ('MO', 'TU' 등)
  int targetWeekday = dayMap[day]!;

  // n 이후 가장 가까운 해당 요일 찾기
  int daysUntilNext = (targetWeekday - n.weekday + 7) % 7;
  if (daysUntilNext == 0) daysUntilNext = 7; // 오늘이 targetWeekday면 다음 주로 설정

  // 수업 시작 시간 가져오기
  DateTime baseDate = n.add(Duration(days: daysUntilNext)); // 해당 요일의 날짜
  DateTime startTime = parseTime(weeklySchedule['startTime']);

  // 최종적으로 해당 날짜에 맞는 시작 시간 적용
  return DateTime(baseDate.year, baseDate.month, baseDate.day, startTime.hour, startTime.minute);
}



