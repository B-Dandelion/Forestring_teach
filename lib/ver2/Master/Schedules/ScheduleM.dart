import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart' show Provider;

class ScheduleM extends StatefulWidget {
  const ScheduleM({super.key});

  @override
  State<ScheduleM> createState() => _ScheduleM();
}

class _ScheduleM extends State<ScheduleM> {
  // 레슨 정보를 관리하는 ValueNotifier 선언
  final ValueNotifier<List<Map<String, dynamic>>> lessonsNotifier = ValueNotifier([]);
  // 선택된 선생님 ID 저장 (기본값: 모든 선생님)
  String selectedTeacherId = 'all';
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _filterLessonsByTeacherAndSemester(_tabIndex); // 초기값: 이번 학기 수업 표시
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MasterProvider>(context);
    final teachers = provider.teachers;
    final students = provider.students;

    // "모든 선생님" 옵션 추가한 리스트
    List<Map<String, String>> teacherOptions = [
      {'id': 'all', 'name': '모든 선생님'}
    ] + teachers.map((teacher) => {
      'id': teacher['id'].toString(),
      'name': teacher['name'].toString(),
    }).toList();

    return Scaffold(
      backgroundColor: NEUTRAL_IVORY,
      appBar: KoAppBar(appBar: AppBar(), title: '레슨 관리'),
      drawer: ManagerDrawer(),
      body: Padding(padding: const EdgeInsets.all(5.0),
        child: Column(
          children: [
            const SizedBox(height: 15),
            // 보강 등록 버튼
            ScheduleButton(
              onPressed: () {
                _showAddScheduleDialog(context);
              },
            ),
            const SizedBox(height: 15),

            // 선생님 선택 Dropdown
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: DropdownButtonFormField<String>(
                value: selectedTeacherId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "선생님 선택",
                ),
                items: teacherOptions.map<DropdownMenuItem<String>>((teacher) {
                  return DropdownMenuItem<String>(
                    value: teacher['id'].toString(),
                    child: Text(teacher['name']!, style: style),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    selectedTeacherId = newValue!;
                    _filterLessonsByTeacherAndSemester(_tabIndex);
                  });
                },
              ),
            ),
            const SizedBox(height: 15),
            // 3단 탭바 영역
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: Colors.black,
                      labelStyle: style,
                      indicatorColor: PRIMARY_COLOR,
                      onTap: (index) {
                        setState(() => _tabIndex = index);
                        _filterLessonsByTeacherAndSemester(index);
                      },
                      tabs: [
                        Tab(child: Text('이전 학기 수업', style: style)),
                        Tab(child: Text('이번 학기 수업', style: style)),
                        Tab(child: Text('다음 학기 수업', style: style)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                        valueListenable: lessonsNotifier,
                        builder: (context, lessons, _) {
                          if (lessons.isEmpty) {
                            return Center(child: Text('해당 학기에 수업이 없습니다.', style: style));
                          }
                          return ListView.builder(
                            itemCount: lessons.length,
                            itemBuilder: (context, index) {
                              final lesson = lessons[index];
                              final teacherName = provider.getDisplayName(lesson['teacherId'], isTeacher: true);
                              final studentName = provider.getDisplayName(lesson['studentId'], isTeacher: false);
                              return Column(
                                children: [
                                  LessonCardM(
                                      startTime: lesson['date'],
                                      endTime: lesson['date'].add(Duration(minutes: lesson['duration'])),
                                      month: lesson['date'].month,
                                      date: lesson['date'].day,
                                      student: studentName,
                                      teacher: teacherName,
                                      onEdit: () {
                                        showEditLessonDialog(context, lesson);
                                      }
                                      ),
                                  SizedBox(height: 3,),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  void _showAddScheduleDialog(BuildContext context) {
    String selectedStudentId = "";
    String selectedTeacherId = "";

    final provider = Provider.of<MasterProvider>(context, listen: false);
    List<Map<String, dynamic>> teachers = provider.teachers; // 선생님 리스트
    List<Map<String, dynamic>> students = provider.students;

    // 여러 개의 수업을 저장할 리스트
    List<Map<String, dynamic>> lessons = [
      {
        "id" : DateTime.now().microsecondsSinceEpoch.toString(),
        "code" : '-1', //보강 코드
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
                        Text("보강 등록하기", style: style.copyWith(fontSize: 25)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: selectedTeacherId.isEmpty ? null : selectedTeacherId,
                          decoration: InputDecoration(border: OutlineInputBorder(), labelText: "선생님 선택"),
                          items: teachers.map((teacher) {
                            return DropdownMenuItem(
                              value: teacher['id'].toString(),
                              child: Text(teacher['name'], style: style),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            setState(() {
                              selectedTeacherId = newValue!;
                              selectedStudentId = ''; // 선생님 변경 시 학생 선택 초기화
                            });
                          },
                        ),
                        const SizedBox(height: 15),
                        // 선생님 선택 시, 해당 선생님의 학생 dropdown 생성
                        if (selectedTeacherId.isNotEmpty)
                          Builder(builder: (context) {
                            // 선택된 선생님 정보 찾기 (id 타입 비교를 위해 toString 사용)
                            final teacher = teachers.firstWhere(
                                    (t) => t['id'].toString() == selectedTeacherId,
                                orElse: () => {});
                            // teacher['studentIds']에 저장된 학생 id 리스트
                            final List<dynamic> teacherStudentIds = teacher['studentIds'] ?? [];
                            // 학생 리스트에서 해당 id를 가진 학생만 필터링
                            final filteredStudents = students
                                .where((student) => teacherStudentIds.contains(student['id']))
                                .toList();

                            return DropdownButtonFormField<String>(
                              value: selectedStudentId.isEmpty ? null : selectedStudentId,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: "학생 선택",
                              ),
                              items: filteredStudents.map((student) {
                                return DropdownMenuItem(
                                  value: student['id'].toString(),
                                  child: Text(student['name'], style: style),
                                );
                              }).toList(),
                              onChanged: (newValue) {
                                setState(() {
                                  selectedStudentId = newValue!;
                                });
                              },
                            );
                          }),
                        Divider(),
                        Column(
                            children: List.generate(lessons.length, (index){
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("보강 ${index + 1}", style: style.copyWith(color: PRIMARY_COLOR,
                                          fontSize: 18, fontWeight: FontWeight.w500)),
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
                                      Text("보강 수업 날짜: ${DateFormat('yy.MM.dd').format(lessons[index]['date'])}", style: style),
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
                                        child: Icon(Icons.calendar_today, color: Colors.white, size: 20),
                                        style: ElevatedButton.styleFrom(backgroundColor: Color(0xff3E6F58)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("보강 수업 시간: ${lessons[index]['time']}", style: style),
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
                                              // 'date'에 시간까지 반영된 DateTime으로 덮어쓰기
                                              final DateTime dateOnly = lessons[index]['date'];
                                              lessons[index]['date'] = DateTime(
                                                dateOnly.year,
                                                dateOnly.month,
                                                dateOnly.day,
                                                pickedTime.hour,
                                                pickedTime.minute,
                                              );
                                            });
                                          }
                                        },
                                        child: Icon(Icons.access_time_rounded, color: Colors.white, size: 20),
                                        style: ElevatedButton.styleFrom(backgroundColor: Color(0xff3E6F58)),
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
                              setState(() {
                                lessons.add({
                                  "id" : DateTime.now().microsecondsSinceEpoch.toString(),
                                  "code" : '-1',
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
                                if (!canAddLessons_2(selectedTeacherId, lessons)) {
                                  // 겹치는 시간이 있을 경우 스낵바 출력 & 저장 취소
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "겹치는 수업이 존재합니다. 다른 시간을 선택해주세요.",
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
                                  return; // 저장 취소
                                }
                                // 검사를 통과한 경우에만 저장 진행
                                _saveNewSchedule(context, selectedTeacherId, selectedStudentId, lessons);
                                Navigator.pop(context);  // 여기서 팝업 닫기
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
                child: Text("취소", style: style.copyWith(color: Colors.grey)),
              ),

              // 저장 버튼 -> 적용 버튼 보이게 전환
              TextButton(
                onPressed: () async {

                  if (applyToAll) {
                    // 전체 수업 변경
                    // 선생님 / 학생 정보 가져오기

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
                  } else {
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
  // 선택된 선생님 기준으로 레슨 필터링
  // 학기별로 레슨을 필터링하는 함수
  void _filterLessonsByTeacherAndSemester(int semesterIndex) {
    final provider = Provider.of<MasterProvider>(context, listen: false);
    List<Map<String, dynamic>> allLessons = provider.lessons;

    // 학기 키
    String currentSemesterKey = "${nowsemester.year}-${nowsemester.month.toString().padLeft(2, '0')}";
    String pSemesterKey = "${previoussemester.year}-${previoussemester.month.toString().padLeft(2, '0')}";
    String nSemesterKey = "${nextsemester.year}-${nextsemester.month.toString().padLeft(2, '0')}";

    DateTime startDate, endDate;
    if (semesterIndex == 0) { // 이전 학기
      startDate = SemesterTerm[pSemesterKey]!['startDate'];
      endDate = SemesterTerm[pSemesterKey]!['endDate'].add(const Duration(days: 1));
    } else if (semesterIndex == 1) { // 이번 학기
      startDate = SemesterTerm[currentSemesterKey]!['startDate'];
      endDate = SemesterTerm[currentSemesterKey]!['endDate'].add(const Duration(days: 1));
    } else { // 다음 학기
      startDate = SemesterTerm[nSemesterKey]!['startDate'];
      endDate = SemesterTerm[nSemesterKey]!['endDate'].add(const Duration(days: 1));
    }

    DateTime asDate(dynamic raw) => raw is Timestamp ? raw.toDate() : raw as DateTime;

    // ---- 디버그: 현재 탭/범위/키/데이터량 ----
    debugPrint(
        "[ScheduleM] tab=$semesterIndex teacher=$selectedTeacherId | "
            "keys(prev=$pSemesterKey, cur=$currentSemesterKey, next=$nSemesterKey) | "
            "range=${DateFormat('yyyy-MM-dd HH:mm').format(startDate)} ~ ${DateFormat('yyyy-MM-dd HH:mm').format(endDate)} | "
            "allLessons=${allLessons.length}"
    );

    // 해당 기간에 속하는 레슨 필터링
    List<Map<String, dynamic>> filteredLessons = allLessons.where((lesson) {
      DateTime lessonDate = lesson['date'];
      bool isWithinSemester = lessonDate.isAfter(startDate) && lessonDate.isBefore(endDate);
      bool isNotCanceled = lesson['status'] != 'canceled';

      // 선택된 선생님이 "모든 선생님"이 아니면 teacherId 필터링 추가
      if (selectedTeacherId != 'all') {
        return isWithinSemester
            && isNotCanceled
            && lesson['teacherId'] == selectedTeacherId;
      }
      return isWithinSemester && isNotCanceled;
    }).toList();

    // 'date' 기준으로 오름차순 정렬 (과거 → 미래)
    filteredLessons.sort((a, b) => a['date'].compareTo(b['date']));

    // 필터링된 결과 업데이트
    lessonsNotifier.value = filteredLessons;
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
      DateTime lessonEnd = lessonDate.add(Duration(minutes: duration));
      print("🟦 추가 시도 수업: ID=$lessonId, 시작=$lessonDate, 종료=$lessonEnd");

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

        print("📌 비교 대상: ${entry.key} | 시작=$bookedStart, 종료=$bookedEnd");

        // (lessonDate ~ lessonEnd) vs (bookedStart ~ bookedEnd)
        final DateTime lessonEnd = lessonDate.add(Duration(minutes: duration));
        if (lessonDate.isBefore(bookedEnd) && lessonEnd.isAfter(bookedStart)) {
          print("겹치는 수업 발견: ${entry.key} / 시작: $bookedStart ~ 끝: $bookedEnd");
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

Future<void> _saveNewSchedule(
    BuildContext context, String teacherId, String studentId, List<Map<String, dynamic>> lessons) async
{
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  WriteBatch batch = firestore.batch();

  // 서버 타임스탬프를 위한 변수 (생성, 수정시 모두 사용)
  FieldValue serverTimestamp = FieldValue.serverTimestamp();
  // 1. 필수 입력 필드 확인
  if (studentId.isEmpty || teacherId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        "선생님 / 학생 을 선택해주세요",
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

  CollectionReference lessonsRef = firestore.collection('lessons');
  DocumentReference teacherSlotRef = firestore.collection('availableSlots').doc(teacherId);
  CollectionReference studentLessonsRef = firestore.collection('users').doc(studentId).collection('lessons');

  for (var lesson in lessons) {
    // Firestore Auto ID 생성
    DocumentReference lessonDocRef = lessonsRef.doc();
    String lessonId = lessonDocRef.id;

    // 날짜(DateTime) + 시간("HH:mm")을 하나의 DateTime으로 합침
    DateTime baseDate = lesson['date']; // 날짜 정보
    List<String> timeParts = (lesson['time'] as String).split(":");
    int hour = int.parse(timeParts[0]);
    int minute = int.parse(timeParts[1]);

    DateTime lessonDateTime = DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);

    // 공통 레슨 데이터 (한 번만 정의)
    Map<String, dynamic> lessonData = {
      "code": lesson['code'],
      "date": lessonDateTime, // 날짜 + 시간 통합 저장,
      "duration": lesson['duration'],
      "studentId": studentId,
      "teacherId": teacherId,
      "isRescheduled": true,
      "status": "makeup",
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    };

    // Firestore에 데이터 저장 (Batch 사용)
    batch.set(lessonDocRef, lessonData); // (1) `lessons` 컬렉션에 저장
    batch.set(studentLessonsRef.doc(lessonId), lessonData); // (2) 학생의 lessons 서브컬렉션에 저장
    batch.set(
      teacherSlotRef,
      {
        "bookedSlots": {
          lessonId: {  // lessonId가 "bookedSlots" 맵 안의 키 값으로 들어감
            "date":lessonDateTime, // 날짜 + 시간 통합 저장,
            "duration": lesson['duration'],
            "isRescheduled": true,
            "status": "makeup",
            "studentId": studentId,
          }
        }
      },
      SetOptions(merge: true),
    ); // (3) 선생님 `availableSlots.bookedSlots`에 추가
  }

  await batch.commit();
}

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

    // batch로 업데이트
    batch.update(userDocRef, {
      'weeklySchedule': weeklySchedule,
    });


    // 먼저 업데이트 대상 수업(lessonId)의 기존 날짜와 code 값을 가져옴
    DocumentSnapshot updatedLessonDoc = await globalLessonsRef.doc(lessonId).get();
    Map<String, dynamic> lessonData = updatedLessonDoc.data() as Map<String, dynamic>;

    // 기존 날짜 저장
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

    // 1) "lessons" 컬렉션에서 해당 레슨 문서 상태 변경
    final lessonDocRef = lessonsRef.doc(lessonId);
    batch.update(lessonDocRef, {
      'status': 'canceled',
      'canceledBy': 'master',     // 누가 취소했는지 기록
      'updatedAt': serverTimestamp,
    });

    // 2) 선생님 "availableSlots" 문서에서 해당 bookedSlots 항목 삭제
    //    → 선생님 일정 상에서 이 레슨이 완전히 사라지므로, 그 시간대가 비게 됨
    batch.update(teacherSlotRef, {
      'bookedSlots.$lessonId': FieldValue.delete(),
    });

    // 3) 학생 "users/{studentId}/lessons/{lessonId}" 문서 상태 변경
    //    → 그 학생의 레슨 목록에도 canceled 상태 기록
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

