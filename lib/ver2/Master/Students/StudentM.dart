import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:forestring_teacher_2/ver2/Master/Students/StudentE.dart';
import 'package:forestring_teacher_2/ver2/Master/Students/StudentC.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class StudentM extends StatefulWidget {
  const StudentM({super.key});

  @override
  State<StudentM> createState() => _StudentM();
}

class _StudentM extends State<StudentM> {

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MasterProvider>(context);
    final students = provider.students;
    final teachers = provider.teachers;

    return Scaffold(
      backgroundColor: NEUTRAL_IVORY,
      appBar: KoAppBar(appBar: AppBar(), title: '수강생 관리'),
      drawer: ManagerDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 15),
            // 신규 학생 추가 버튼
            HeartButton(
              onPressed: () {
                _showAddStudentDialog(context); // 학생 추가 다이얼로그 실행
              },
            ),
            const SizedBox(height: 15),

            // 수강생 리스트
            Expanded(
              child: ListView.builder(
                itemCount: students.length,
                itemBuilder: (context, index) {
                  final student = students[index];
                  // teacher 리스트의 index를 가져와서 색상 매칭
                  int teacherIndex = teachers.indexWhere((t) => t['id'] == student["teacherId"]);
                  Color teacherColor = teacherIndex != -1
                      ? Colors_list[teacherIndex % Colors_list.length]
                      : Colors.grey; // 만약 매칭 안 되면 기본값 회색
                  String teacherName = provider.getDisplayName(student["teacherId"], isTeacher: true);
                  DateTime? outstudent = (student['withdrawalDate'] as Timestamp?)?.toDate();
                  String studentname = student['name'];
                  if (outstudent != null) {
                    studentname += ' (${DateFormat('yy.MM.dd').format(outstudent)} 탈퇴)';
                  }
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: teacherColor.withOpacity(0.5), width: 1), // 선생님 색상 기반 경계선
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    elevation: 3,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () {
                        _showStudentDetails(context, student, teacherName); // 클릭 시 상세 정보 표시
                      },
                      child: ListTile(
                        leading: Icon(Icons.person, color: teacherColor),
                        title: Text(studentname, style: style.copyWith(fontSize: 18)),
                        subtitle: Text("$teacherName 선생님", style: style.copyWith(fontSize: 12),),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            _confirmDeleteStudent(context, student, student["teacherId"]);
                          },
                        ),
                      ),
                    )
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  // 정규 수업이 선생님 일정과 겹치지 않는지 확인
  bool isValidLessonTime(String teacherId, String day, String startTime, int duration) {
    final provider = Provider.of<MasterProvider>(context, listen: false);
    final workSchedule = provider.workSchedule;
    final students = provider.students;
    final teachers = provider.teachers;

    // 1. 선생님의 근무 시간 가져오기
    if (!workSchedule.containsKey(teacherId) || !workSchedule[teacherId]!.containsKey(day)) {
      return false; // 해당 요일에 근무하지 않음
    }

    Map<String, dynamic> teacherWorkTime = workSchedule[teacherId]![day]!;
    String teacherStartTime = teacherWorkTime["startTime"];
    String teacherEndTime = teacherWorkTime["endTime"];

    // 2. 선생님의 근무 시간 내인지 확인
    if (!isWithinTimeRange(startTime, duration, teacherStartTime, teacherEndTime)) {
      return false;
    }

    // 3. 담당 학생들의 정규 수업과 겹치는지 확인
    List<String> studentIds = (teachers.firstWhere(
            (t) => t['id'] == teacherId,
        orElse: () => {'studentIds': []}
    )['studentIds'] as List<dynamic>?)?.cast<String>() ?? [];

    for (String studentId in studentIds) {
      Map<String, dynamic>? student = students.firstWhere(
              (s) => s['id'] == studentId, orElse: () => {}
      );

      if (student.containsKey('weeklySchedule')) {
        List<Map<String, dynamic>> schedule = List<Map<String, dynamic>>.from(student['weeklySchedule']);

        for (var lesson in schedule) {
          if (lesson['day'] == day) {
            if (isOverlapping(startTime, duration, lesson['startTime'], lesson['duration'])) {
              return false; // 학생 수업과 겹침
            }
          }
        }
      }
    }
    return true; // 문제가 없으면 true 반환
  }
  bool canAddLessons(String teacherId, List<Map<String, dynamic>> lessons) {
    for (var lesson in lessons) {
      String day = lesson["dayCode"];
      String startTime = lesson["time"];
      int duration = lesson["duration"];

      if (!isValidLessonTime(teacherId, day, startTime, duration)) {
        return false; // 하나라도 겹치면 추가 불가능
      }
    }
    return true; // 모든 수업이 문제없으면 true
  }
  // 신규 학생 추가 다이얼로그
  void _showAddStudentDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    String selectedTeacherId = "";

    final provider = Provider.of<MasterProvider>(context, listen: false);
    List<Map<String, dynamic>> teachers = provider.teachers; // 선생님 리스트

    // 여러 개의 수업을 저장할 리스트
    List<Map<String, dynamic>> lessons = [
      {
        "code" : '0',
        "date" : DateTime.now(),
        "dayCode": _getDayCode(DateTime.now().weekday),
        "time": "16:00",
        "duration": 30,
      }
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                backgroundColor: Colors.white,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("수강생 추가하기", style: style.copyWith(fontSize: 25)),
                        _customTextField(nameController, "수강생 이름"),
                        const SizedBox(height: 8),
                        _customTextField(passwordController, "비밀 번호"),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: selectedTeacherId.isEmpty ? null : selectedTeacherId,
                          decoration: InputDecoration(border: OutlineInputBorder(), labelText: "담당 선생님"),
                          items: teachers.map((teacher) {
                            return DropdownMenuItem(
                              value: teacher['id'].toString(),
                              child: Text(teacher['name'], style: style),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setState(() {
                              selectedTeacherId = newValue!;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        Divider(),
                        Column(
                            children: List.generate(lessons.length, (index){
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("수업 ${index + 1}", style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
                                      if (index > 0) // 첫 번째 수업은 삭제 버튼 없음
                                        IconButton(
                                          icon: Icon(Icons.remove_circle, color: Colors.red),
                                          onPressed: () {
                                            setState(() {
                                              lessons.removeAt(index);
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("수업 날짜: ${DateFormat('yy.MM.dd').format(lessons[index]['date'])}", style: style),
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
                                              lessons[index]['date'] = pickedDate;
                                              lessons[index]['dayCode'] = _getDayCode(pickedDate.weekday);
                                            });
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(backgroundColor: Color(0xff3E6F58)),
                                        child: Icon(Icons.calendar_today, color: Colors.white, size: 20),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("수업 시간: ${lessons[index]['time']}", style: style),
                                      ElevatedButton(
                                        onPressed: () async {
                                          TimeOfDay? pickedTime = await showTimePicker(
                                            context: context,
                                            initialTime: TimeOfDay(hour: 16, minute: 0),
                                          );
                                          if (pickedTime != null) {
                                            setState(() { // UI 업데이트 추가!
                                              lessons[index]['time'] =
                                              "${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}";
                                            });
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(backgroundColor: Color(0xff3E6F58)),
                                        child: Icon(Icons.access_time_rounded, color: Colors.white, size: 20),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<int>(
                                    value: lessons[index]['duration'],
                                    decoration: InputDecoration(border: OutlineInputBorder(), labelText: "수업 길이"),
                                    items: [15, 30, 45, 60, 90].map((duration) {
                                      return DropdownMenuItem(
                                        value: duration,
                                        child: Text("$duration 분", style: style),
                                      );
                                    }).toList(),
                                    onChanged: (newValue) {
                                      setState(() {
                                        lessons[index]['duration'] = newValue!;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              );
                            })
                        ),
                        // 수업 추가 버튼
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              int nextCode = (lessons.isNotEmpty)
                                  ? lessons.map((lesson) => int.parse(lesson['code'] as String))
                                  .reduce((a, b) => a > b ? a : b) + 1
                                  : 0;
                              setState(() {
                                lessons.add({
                                  'code' : nextCode.toString(),
                                  "date": DateTime.now(),
                                  "dayCode": _getDayCode(DateTime.now().weekday),
                                  "time": "16:00",
                                  "duration": 30,
                                });
                              });
                            },
                            icon: Icon(Icons.add, color: Color(0xff3E6F58)),
                            label: Text("수업 추가", style: style.copyWith(color: Color(0xff3E6F58))),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text("취소", style: style.copyWith(color: Colors.red)),
                            ),
                            TextButton(
                              onPressed: () async {
                                // 저장하기 전에 수업 시간 맞는지 한번 확인
                                if (canAddLessons(selectedTeacherId, lessons)) {
                                  await _saveNewStudent(
                                    context,
                                    nameController.text,
                                    passwordController.text,
                                    selectedTeacherId,
                                    lessons,
                                  );
                                } else {
                                  print("겹치는 수업이 존재 / 선생님 근무 시간이 아닙니다.");
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          "겹치는 수업이 존재/선생님 근무 시간이 아닙니다.",
                                          style: style.copyWith(color: Colors.black), // 검은색 글씨
                                          textAlign: TextAlign.center, // 중앙 정렬
                                        ),
                                        backgroundColor: IBORY,
                                        behavior: SnackBarBehavior.floating, // 살짝 떠 있는 느낌
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8), // 둥근 모서리
                                        ),
                                        duration: Duration(seconds: 2),
                                      )
                                  );
                                }
                              },
                              child: Text("추가", style: style.copyWith(color: PRIMARY_COLOR)),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              );
            }
        );
      },
    );
  }
  // 학생 삭제 함수
// 1. 첫 번째 삭제 확인 다이얼로그
  void _confirmDeleteStudent(BuildContext context, Map<String, dynamic> student, String teacherId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("${student['name']}님의 정보를\n삭제하시겠습니까?", style: style.copyWith(fontSize: 20)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("아니요", style: style.copyWith(color: Colors.black)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // 첫 다이얼로그 닫기
                _showWithdrawalDateDialog(context, student, teacherId);
              },
              child: Text("예", style: style.copyWith(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
// 2. 탈퇴 날짜 선택 다이얼로그 (StatefulBuilder 사용)
  void _showWithdrawalDateDialog(BuildContext context, Map<String, dynamic> student, String teacherId) {
    DateTime selectedDate = DateTime.now();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("${student['name']}님의 탈퇴 날짜를\n지정해 주세요", style: style.copyWith(fontSize: 20)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text("탈퇴 날짜: ${DateFormat('yyyy년 M월 dd일').format(selectedDate)}", style: style),
                      IconButton(
                        icon: const Icon(Icons.calendar_today, color: PRIMARY_COLOR,),
                        onPressed: () async {
                          DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("아니요", style: style),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // 날짜 선택 다이얼로그 닫기
                    _showFinalDeleteConfirmationDialog(context, student, teacherId, selectedDate);
                  },
                  child: Text("예", style: style.copyWith(color: Colors.red)),
                ),
              ],
            );
          },
        );
      },
    );
  }
// 3. 최종 삭제 확인 다이얼로그
  void _showFinalDeleteConfirmationDialog(
      BuildContext context, Map<String, dynamic> student, String teacherId, DateTime withdrawalDate)
  {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("${student['name']} 님의 정보를 정말 삭제하시겠습니까?", style: style.copyWith(fontSize: 20)),
          content: Text("탈퇴 날짜: ${DateFormat('yyyy년 M월 dd일').format(withdrawalDate)}", style: style.copyWith(fontSize: 20)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("아니요", style: style.copyWith(color: Colors.black)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context); // 최종 확인 다이얼로그 닫기
                await _deleteStudentData(student['id'], student['name'], teacherId, withdrawalDate);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${student['name']} 님의 정보가 삭제되었습니다.', style: style),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: Text("예", style: style.copyWith(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
  // 4. 실제 삭제 작업 함수 (Firestore 배치 작업)
  Future<void> _deleteStudentData(String studentId, String studentName, String teacherId, DateTime withdrawalDate) async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    WriteBatch batch = firestore.batch();
    DateTime today = DateTime.now();
    try {
      final provider = Provider.of<MasterProvider>(context, listen: false);
      final Map<String, dynamic> students = { for (var s in provider.students) s['id']: s };
      // ① 프로바이더에 저장된 학생 수업 정보 정의
      List<Map<String, dynamic>> existingLessons = students[studentId]?['lessons'] ?? [];
      DateTime nextDay = withdrawalDate.add(const Duration(days: 1));
      DateTime thresholdDate = DateTime(nextDay.year, nextDay.month, nextDay.day,0,0,0,0,0);

      DocumentReference studentDocRef = firestore.collection('users').doc(studentId);
      CollectionReference studentLessonsRef = studentDocRef.collection('lessons');
      DocumentReference teacherSlotRef = firestore.collection('availableSlots').doc(teacherId);

      // ② 'date'가 (탈퇴 날짜 + 1일) 이후인 레슨 문서의 id를 삭제 리스트에 저장
      List<String> lessonIdsToDelete = existingLessons
          .where((lesson) => lesson['date'].isAfter(thresholdDate))
          .map((lesson) => lesson['id'].toString())
          .toList();

      if (lessonIdsToDelete.isEmpty) {
        debugPrint("삭제할 수업이 없습니다.");
      } else {
        debugPrint("삭제할 수업 ID 목록: $lessonIdsToDelete");
      }

      for (String id in lessonIdsToDelete) {
        DocumentReference lessonDocRef = firestore.collection('lessons').doc(id);
        DocumentReference studentLessonDocRef = studentLessonsRef.doc(id);
        batch.delete(lessonDocRef);// ③ lessons 컬렉션에서 삭제 리스트에 해당하는 문서들 삭제
        batch.delete(studentLessonDocRef);// ④ users 컬렉션 내 학생의 lessons 하위 컬렉션에서 해당 문서들 삭제
        batch.update(teacherSlotRef, {
          // ⑤ availableSlots 컬렉션, 선생님의 bookedSlots 맵 필드에서, 삭제 리스트에 해당하는 키들을 제거
          'bookedSlots.$id': FieldValue.delete(),
        });
      }

      // ⑥ users 컬렉션 내 학생 문서에 탈퇴 날짜 정보를 새 필드로 저장 (후처리 트리거 용)
      batch.update(studentDocRef, {
        'withdrawalDate': withdrawalDate,
      });
      debugPrint("batch.delete() 실행 개수: ${lessonIdsToDelete.length}");

      // 7. 정보를 조회할 때 (탈퇴)라고 표시되도록 아카이브 리스트에 탐지되로록 문서를 생성해줌.
      await firestore.collection('archivedUsers').doc(studentId).set({
        'name': studentName,
        'role': 'student',
      });

      // 배치 커밋
      await batch.commit();

      if (withdrawalDate.isBefore(today)) {
        // 바로 아카이빙 실행

        await archiveStudentData(studentId, teacherId, studentName);
        return;
      }
      await provider.fetchArchivedUsers(); // 아카이브 리스트는 자동 갱신이 안되므로 삭제 예정 즉시 업데이트 함.

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            "학생 정보가 삭제 예정으로 설정되었습니다.",
            style: style.copyWith(color: Colors.black),
            textAlign: TextAlign.center,
          ),
          backgroundColor: IBORY,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          duration: Duration(seconds: 2),
        ));
    } catch (e) {
      print("학생 삭제 오류: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          "삭제 중 오류가 발생했습니다.",
          style: style.copyWith(color: Colors.black),
          textAlign: TextAlign.center,
        ),
        backgroundColor: IBORY,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        duration: Duration(seconds: 2),
      ));
    }
  }
  Future<void> archiveStudentData(String studentId, String teacherId, String studentName) async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    WriteBatch batch = firestore.batch();

    // (1) users -> studentId 문서의 필드값 → archivedUsers로 이동
    DocumentReference studentDoc = firestore.collection('users').doc(studentId);
    DocumentSnapshot studentSnapshot = await studentDoc.get();

    if (!studentSnapshot.exists) {
      print("해당 Student ID($studentId)가 존재하지 않습니다.");
      return;
    }

    Map<String, dynamic> studentData = studentSnapshot.data() as Map<String, dynamic>;

    DocumentReference archivedStudentDoc = firestore.collection('archivedUsers').doc(studentId);
    batch.set(archivedStudentDoc, studentData);

    // (2) lessons -> archivedLessons 이동
    QuerySnapshot studentLessonSnapshot = await studentDoc.collection('lessons').get();

    for (var doc in studentLessonSnapshot.docs) {
      DocumentReference archivedDocRef =
      firestore.collection('archivedLessons').doc(studentId).collection('lessons').doc(doc.id);
      batch.set(archivedDocRef, doc.data()); // lessons 데이터 복사
    }

    // (3) usersByName -> studentName 문서의 userIds 리스트에서 studentId 제거
    DocumentReference userByNameDoc = firestore.collection('usersByName').doc(studentName);
    DocumentSnapshot userByNameSnapshot = await userByNameDoc.get();

    if (userByNameSnapshot.exists) {
      List<dynamic> userIds = List.from(userByNameSnapshot['userIds']);
      userIds.remove(studentId);

      if (userIds.isEmpty) {
        batch.delete(userByNameDoc); // 만약 userIds 리스트가 비면 문서 삭제
      } else {
        batch.update(userByNameDoc, {'userIds': userIds});
      }
    }
    // (4) 기존 lessons 컬렉션 삭제
    for (var doc in studentLessonSnapshot.docs) {
      await studentDoc.collection('lessons').doc(doc.id).delete();
    }
    // (5) teacher 문서에서 studentId 제거
    DocumentReference teacherDoc = firestore.collection('users').doc(teacherId);
    DocumentSnapshot teacherSnapshot = await teacherDoc.get();

    if (teacherSnapshot.exists) {
      List<dynamic> studentIds = List.from(teacherSnapshot['studentIds']);
      studentIds.remove(studentId);

      batch.update(teacherDoc, {'studentIds': studentIds});
    }

    // 모든 작업 커밋
    await batch.commit();

    // 기존 문서 삭제 (users)
    await studentDoc.delete();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        "학생 정보가 삭제되었습니다.",
        style: style.copyWith(color: Colors.black),
        textAlign: TextAlign.center,
      ),
      backgroundColor: IBORY,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      duration: Duration(seconds: 2),
    ));
    print("학생 데이터 아카이브 완료: $studentName ($teacherId)");
  }
}

String _generateStudentID() {
  String date = DateTime.now().toString().split(" ")[0].replaceAll("-", "").substring(2); // 240301
  String randomPart = (100 + DateTime.now().millisecond % 900).toString(); // 랜덤 2자리
  return "STU_$date$randomPart";
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
Future<void> _saveNewStudent(
    BuildContext context, String name, String password, String teacherId, List<Map<String, dynamic>> lessons) async
{
  FirebaseFirestore firestore = FirebaseFirestore.instance;

  // 1. 필수 입력 필드 확인
  if (name.isEmpty || password.isEmpty || teacherId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        "모든 필수 정보를 입력해주세요.",
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
  }

  String studentId = _generateStudentID(); // 학생 ID 생성

  // 각 요일별 레슨을 생성
  List<Map<String, dynamic>> allLessons = [];

  for (var lesson in lessons) {
    DateTime firstLessonDate = lesson['date'];
    List<String> timeParts = lesson['time'].split(':');
    firstLessonDate = DateTime(firstLessonDate.year, firstLessonDate.month,
        firstLessonDate.day, int.parse(timeParts[0]), int.parse(timeParts[1]));
    int duration = lesson["duration"];
    print('시점 1 : ${lesson['code']}');
    List<Map<String, dynamic>> generatedLessons = generateLessons(firstLessonDate, duration, studentId, teacherId, lesson['code']);
    allLessons.addAll(generatedLessons);
  }

  if (allLessons.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("생성된 수업이 없습니다. 학기 정보를 확인해주세요.")));
    return;
  }

  // 2. Firebase에 트랜잭션으로 데이터 저장
  WriteBatch batch = firestore.batch();

  // (1) `users` 컬렉션에 학생 데이터 저장
  DocumentReference studentRef = firestore.collection('users').doc(studentId);
  batch.set(studentRef, {
    'name': name,
    'password': password,
    'role': 'student',
    'teacherId': teacherId,
    'weeklySchedule': lessons.map((lesson) => {
      'code': lesson['code'],
      'day': lesson['dayCode'],
      'startTime': lesson['time'],
      'duration': lesson['duration'],
    }).toList(),
  });

  // (2) `userByName` 컬렉션 업데이트 (동명이인 방지)
  DocumentReference userByNameRef = firestore.collection('usersByName').doc(name);
  DocumentSnapshot userByNameSnapshot = await userByNameRef.get();

  if (!userByNameSnapshot.exists) {
    // 문서가 없으면 새로 생성
    batch.set(userByNameRef, {
      "userIds": [studentId], // 새 리스트 생성
    });
  } else {
    // 문서가 있으면 기존 리스트에 추가
    List<dynamic> userIds = List.from(userByNameSnapshot["userIds"]);
    if (!userIds.contains(studentId)) {
      userIds.add(studentId);
      batch.update(userByNameRef, {"userIds": userIds});
    }
  }

  // (3) `teachers` 컬렉션의 `studentIds` 리스트에 추가
  DocumentReference teacherRef = firestore.collection('users').doc(teacherId);
  DocumentSnapshot teacherSnapshot = await teacherRef.get();

  if (teacherSnapshot.exists) {
    List<dynamic> studentIds = List.from(teacherSnapshot["studentIds"] ?? []);
    if (!studentIds.contains(studentId)) {
      studentIds.add(studentId);
      batch.update(teacherRef, {"studentIds": studentIds});
    }
  }

  // (4) 생성해둔 수업을 3가지 위치에 저장.
  await saveLessonsToFirestore(studentId, teacherId, allLessons);

  // 배치 실행
  await batch.commit();

  // 완료 메시지 및 다이얼로그 닫기
  Navigator.pop(context);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("학생이 성공적으로 추가되었습니다!")));
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

// 학생 정보 페이지
void _showStudentDetails(BuildContext context, Map<String, dynamic> student, String teacherName) {
  const Map<String, String> dayMap = {
    "MO": "월",
    "TU": "화",
    "WE": "수",
    "TH": "목",
    "FR": "금",
    "SA": "토",
    "SU": "일"
  };
  // 저장된 weeklySchedule 불러오기 (타입 캐스팅 추가)
  List<Map<String, dynamic>> schedule = List<Map<String, dynamic>>.from(student['weeklySchedule'] ?? []);
  // 요일 리스트 변환
  List<String> lessonDays = schedule.map((lesson) {
    String dayCode = lesson['day'].toString(); // String으로 변환
    return dayMap[dayCode] ?? dayCode; // 변환 후 없으면 원본 값 유지
  }).toList();

  String formattedDays = lessonDays.isNotEmpty ? lessonDays.join(", ") : "미정"; // 2개 이상이면 쉼표로 구분

  // 수업 시간 변환
  List<String> lessonTimes = schedule.map((lesson) {
    String startTime = lesson['startTime']; // 시작 시간 (HH:mm)
    int duration = lesson['duration']; // 수업 길이 (분)

    // 종료 시간 계산 (DateTime 객체 사용)
    List<String> startParts = startTime.split(":");
    int startHour = int.parse(startParts[0]);
    int startMinute = int.parse(startParts[1]);

    DateTime startDateTime = DateTime(2025, 1, 1, startHour, startMinute); // 날짜는 임의 설정
    DateTime endDateTime = startDateTime.add(Duration(minutes: duration));

    String endTime = "${endDateTime.hour.toString().padLeft(2, '0')}:${endDateTime.minute.toString().padLeft(2, '0')}";

    return "$startTime ~ $endTime"; // 최종 포맷: HH:mm ~ HH:mm
  }).toList();
  String formattedTimes = lessonTimes.isNotEmpty ? lessonTimes.join(", ") : "미정"; // 2개 이상이면 쉼표로 구분


  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // 둥근 모서리
        title: Text(
          "수강생 정보",
          style: style.copyWith(fontWeight: FontWeight.w500, fontSize: 22),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow("이름", student['name']),
            _infoRow("담당 선생님", "$teacherName 선생님"),
            _infoRow("수업 요일", formattedDays),
            _infoRow("수업 시간", formattedTimes, isMultiline: true),
            _infoRow("비밀 번호", student['password'].toString().substring(student['password'].length - 4)),
            SizedBox(height: 16),

            // 버튼 2개 (아이콘 추가)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // 팝업 닫기
                      // 학생 캘린더 페이지 이동
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StudentCalendar(studentId: student['id']),
                        ),
                      );
                    },
                    icon: Icon(Icons.calendar_today, color: Colors.white), // 캘린더 아이콘 추가
                    label: Text("캘린더", style: style.copyWith(fontSize: 16, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xff3E6F58), // 캘린더 버튼 색상
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                SizedBox(width: 10), // 버튼 간격

                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // 팝업 닫기
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditStudentPage(student: student),
                        ),
                      );
                    },
                    icon: Icon(Icons.edit, color: Colors.white), // 🔹 수정 아이콘 추가
                    label: Text("수정", style: style.copyWith(fontSize: 16, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xff708C7A), // 수정 버튼 색상
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // 취소 버튼 (닫기)
            child: Text("닫기", style: style.copyWith(color: Colors.grey[700], fontSize: 14)),
          ),
        ],
      );
    },
  );
}
Widget _infoRow(String title, String value, {bool isMultiline = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0), // 간격 조정
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: style.copyWith(color: PRIMARY_COLOR, fontWeight: FontWeight.w500, fontSize: 18)),
        SizedBox(height: 4), // 제목과 값 사이 간격 추가
        isMultiline
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: value.split(", ").map((line) => Text(line, style: style.copyWith(fontSize: 16))).toList(),
        )
            : Text(value, style: style.copyWith(fontSize: 16)),
        Divider(thickness: 1, color: Colors.grey[300]), // 구분선 추가 (선택 사항)
      ],
    ),
  );
}

// 커스텀 텍스트 필드 (둥근 스타일)
Widget _customTextField(TextEditingController controller, String hint) {
  return TextField(
    controller: controller,
    decoration: InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey[200],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  );
}


