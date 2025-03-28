import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver2/Master/Teachers/NTeacher.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';

import 'TeacherC.dart';
import 'TeacherE.dart';

class TeacherM extends StatefulWidget {
  const TeacherM({super.key});

  @override
  State<TeacherM> createState() => _TeacherM();
}

class _TeacherM extends State<TeacherM> {
  @override
  void initState() {
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MasterProvider>(context);
    final teachers = provider.teachers;
    final students = provider.students;
    final workschedule = provider.workSchedule;
    final bookedslot = provider.bookedSlots;

    return Scaffold(
      backgroundColor: NEUTRAL_IVORY,
      appBar: KoAppBar(appBar: AppBar(), title: '선생님 관리'),
      drawer: ManagerDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Column(
          children: [
            const SizedBox(height: 15),
            // 신규 선생님 추가 버튼
            SchoolButton(
              onPressed: () {
                showNewTeacherDialog(context);
              },
            ),
            const SizedBox(height: 15),

            // 선생님 리스트
            Expanded(
              child: ListView.builder(
                itemCount: teachers.length,
                itemBuilder: (context, index) {
                  final teacher = teachers[index];
                  final schedules = provider.bookedSlots[teacher['id']] ?? {};
                  final List<Map<String, dynamic>> studentschedule = [
                    for (var studentId in teacher['studentIds'])
                      {
                        'studentId': studentId,
                        'name': provider.getDisplayName(studentId, isTeacher: false),
                        'weeklySchedule': students.firstWhere(
                              (student) => student['id'] == studentId,
                          orElse: () => {'weeklySchedule': {}}, // 기본값: 빈 schedule
                        )['weeklySchedule'],
                      }
                  ];
                  DateTime? outstudent = (teacher['withdrawalDate'] as Timestamp?)?.toDate();
                  String teachername = teacher['name'];
                  if (outstudent != null) {
                    teachername += ' (${DateFormat('yy.MM.dd').format(outstudent)} 탈퇴)';
                  }
                  Color newColor = getLighterColor(index);

                  final Map<String, dynamic> teacherWorkSchedule = workschedule[teacher['id']] ?? {};
                  final Map<String, Map<String, dynamic>> bookedlessons = bookedslot[teacher['id']] ?? {};
                  int count = _countLessons(bookedlessons) ?? 0;
                  return TeacherCard(
                    teacherName: teachername,
                    classCount: count,
                    cardColor: newColor,
                    studentschedule: studentschedule,
                    teacher: teacher,
                    schedules: schedules,
                    workschedule: teacherWorkSchedule,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
Color getLighterColor(int index) {
  // Color → HSLColor 변환
  Color baseColor = Color(0xff123026);
  HSLColor hslColor = HSLColor.fromColor(baseColor);

  // Lightness 증가 (최대 0.9까지만 증가시켜 완전히 하얗게 되지 않도록 조정)
  double newLightness = (hslColor.lightness + (index * 0.05)).clamp(0.0, 0.9);

  return hslColor.withLightness(newLightness).toColor();
}

// 선생님 정보 삭제 관련 함수
void showCannotDeleteTeacherDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(
          "삭제 불가",
          style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.redAccent),
        ),
        content: Text(
          "이 선생님이 담당하는 학생이 존재합니다.\n먼저 학생을 다른 선생님에게 배정하거나 삭제해주세요.",
          style: style.copyWith(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "확인",
              style: style.copyWith(fontSize: 14, fontWeight: FontWeight.w300, color: PRIMARY_COLOR),
            ),
          ),
        ],
      );
    },
  );
}
void showDeleteTeacherDialog(BuildContext context, String teacherName, String teacherId) {
  DateTime? selectedDate; // 사용자가 선택한 탈퇴 날짜

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              "$teacherName 선생님의 정보를 삭제하시겠습니까?",
              style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectedDate != null) ...[
                  Text(
                    "탈퇴 날짜: ${DateFormat('yyyy-MM-dd').format(selectedDate!)}",
                    style: style.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                ],
                ElevatedButton.icon(
                  onPressed: () async {
                    DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (pickedDate != null) {
                      setState(() {
                        selectedDate = pickedDate;
                      });
                    }
                  },
                  icon: Icon(Icons.calendar_today, color: Colors.white),
                  label: Text(
                    selectedDate == null ? "탈퇴 날짜 선택" : "날짜 변경",
                    style: style.copyWith(fontSize: 14, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SECONDARY_COLOR,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("취소", style: style.copyWith(fontSize: 14, color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: selectedDate == null
                    ? null
                    : () {
                  deleteTeacher(context, teacherId, teacherName, selectedDate!); // 삭제 함수 실행
                  Navigator.pop(context); // 다이얼로그 닫기
                },
                child: Text("삭제하기", style: style.copyWith(fontSize: 14, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedDate == null ? Colors.grey : Colors.redAccent,
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
Future<void> deleteTeacher(BuildContext context, String teacherId, String teacherName, DateTime withdrawalDate) async {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final DocumentReference teacherRef = firestore.collection('users').doc(teacherId);
  DateTime today = DateTime.now();

  try {
    if (withdrawalDate.isBefore(today)) {
      // 바로 아카이빙 실행
      await archiveTeacherData(teacherId, teacherName);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            "선생님 정보가 삭제되었습니다.",
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
    } else {
      // 지정한 날짜에 맞춰 withdrawalDate 업데이트
      await teacherRef.update({
        'withdrawalDate': Timestamp.fromDate(withdrawalDate),
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            "선생님 정보가 삭제 예정으로 설정되었습니다.",
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
  } catch (e) {
    print("선생님 삭제 오류: $e");
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
Future<void> archiveTeacherData(String teacherId, String teacherName) async {
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  WriteBatch batch = firestore.batch();

  // (1) users -> teacherId 문서 및 하위 컬렉션 → archivedUsers로 이동
  DocumentReference teacherDoc = firestore.collection('users').doc(teacherId);
  DocumentSnapshot teacherSnapshot = await teacherDoc.get();

  if (!teacherSnapshot.exists) {
    print("해당 Teacher ID($teacherId)가 존재하지 않습니다.");
    return;
  }

  Map<String, dynamic> teacherData = teacherSnapshot.data() as Map<String, dynamic>;

  DocumentReference archivedTeacherDoc = firestore.collection('archivedUsers').doc(teacherId);
  batch.set(archivedTeacherDoc, teacherData);

  // (2) availableSlots -> teacherId 문서의 workSchedule 필드 병합
  DocumentReference availableSlotsDoc = firestore.collection('availableSlots').doc(teacherId);
  DocumentSnapshot availableSlotsSnapshot = await availableSlotsDoc.get();

  Map<String, dynamic> availableSlotsData = availableSlotsSnapshot.data() as Map<String, dynamic>;

  if (availableSlotsSnapshot.exists) {
    if (availableSlotsData.containsKey('workSchedule')) {
      batch.set(archivedTeacherDoc, {
        'workSchedule': availableSlotsData['workSchedule']
      }, SetOptions(merge: true));
    }
  }

  // (3) availableSlots -> teacherId 문서의 bookedSlots 맵 필드 → archivedLessons로 이동
  if (availableSlotsSnapshot.exists) {
    DocumentReference archivedLessonsDoc = firestore.collection('archivedLessons').doc(teacherId);
    batch.set(archivedLessonsDoc, {
      'bookedSlots': availableSlotsData['bookedSlots']
    });
  }

  // (4) usersByName -> teacherName 문서의 userIds 리스트에서 teacherId 제거
  DocumentReference userByNameDoc = firestore.collection('usersByName').doc(teacherName);
  DocumentSnapshot userByNameSnapshot = await userByNameDoc.get();

  if (userByNameSnapshot.exists) {
    List<dynamic> userIds = List.from(userByNameSnapshot['userIds']);
    userIds.remove(teacherId);

    if (userIds.isEmpty) {
      batch.delete(userByNameDoc); // 만약 userIds 리스트가 비면 문서 삭제
    } else {
      batch.update(userByNameDoc, {'userIds': userIds});
    }
  }

  // 모든 작업 커밋
  await batch.commit();

  // 기존 문서 삭제 (users & availableSlots)
  await teacherDoc.delete();
  await availableSlotsDoc.delete();

  print("선생님 데이터 아카이브 완료: $teacherName ($teacherId)");
}

// 상세 정보 확인 창 관련 함수
void _showTeacherDetails(BuildContext context, Map<String, dynamic> teacher,
    List<Map<String, dynamic>> studentschedule, Map<String, dynamic> workschedule)
{
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "선생님 정보",
          style: style.copyWith(fontWeight: FontWeight.w500, fontSize: 22),
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow("성함", teacher['name'] + ' 선생님'),
              _infoRow("비밀 번호", teacher['password']),
              Text(
                "담당 학생",
                style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: PRIMARY_COLOR),
              ),
              Container(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: studentschedule.map((student) {
                    final name = student['name'] ?? '이름 없음';
                    // weeklySchedule 데이터를 가져오고, 타입에 따라 List로 변환
                    final dynamic rawWeeklySchedule = student['weeklySchedule'] ?? [];
                    List<dynamic> weekly;
                    if (rawWeeklySchedule is List) {
                      weekly = rawWeeklySchedule;
                    } else if (rawWeeklySchedule is Map) {
                      weekly = [rawWeeklySchedule];
                    } else {
                      weekly = [];
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 학생 이름 출력
                          Text(
                            name,
                            style: style.copyWith(fontSize: 14),
                          ),
                          if (weekly.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                '스케줄 없음',
                                style: style.copyWith(fontSize: 14),
                              ),
                            )
                          else
                          // weekly 리스트의 길이만큼 수업 정보를 출력
                            ...weekly.map((schedule) {
                              final String day = schedule['day'] ?? '';
                              final String koday = _convertDayToKorean(day);
                              final String rawStartTime = schedule['startTime'] ?? '14:00';
                              DateTime startTime;
                              try {
                                final parts = rawStartTime.split(':');
                                final int hour = int.parse(parts[0]);
                                final int minute = int.parse(parts[1]);
                                startTime = DateTime(2000, 1, 1, hour, minute);
                              } catch (e) {
                                startTime = DateTime(2000, 1, 1, 0, 0);
                              }
                              final int duration = schedule['duration'] ?? 0;
                              final DateTime endTime = startTime.add(Duration(minutes: duration));
                              final formattedStart = DateFormat('HH:mm').format(startTime);
                              final formattedEnd = DateFormat('HH:mm').format(endTime);
                              return Padding(
                                padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                                child: Text(
                                  '$koday요일 $formattedStart ~ $formattedEnd',
                                  style: style.copyWith(fontSize: 14),
                                ),
                              );
                            }).toList(),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              )

            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("닫기", style: style.copyWith(color: Colors.grey[700], fontSize: 14)),
          ),
        ],
      );
    },
  );
}


String _convertDayToKorean(String dayKey) {
  Map<String, String> dayMap = {
    "MO": "월",
    "TU": "화",
    "WE": "수",
    "TH": "목",
    "FR": "금",
    "SA": "토",
    "SU": "일",
  };
  return dayMap[dayKey] ?? dayKey;
}

int _countLessons(Map<String, Map<String, dynamic>> bookedLessons) {
  DateTime now = nowsemester;
  String currentTermKey = "${now.year}-${now.month.toString().padLeft(2, '0')}";

  // 현재 학기 시작 & 종료 날짜 가져오기
  DateTime startTime = SemesterTerm[currentTermKey]!['startDate'];
  DateTime endTime = SemesterTerm[currentTermKey]!['endDate'];

  // 학기별 수업 개수 계산
  int lessonCounts = 0; // 현재 학기
  for (var lesson in bookedLessons.values) {
    // 예약 금지된 수업이면 스킵 (가장 먼저 검사)
    if (lesson['status'] == 'ban') continue;

    DateTime lessonDate = lesson['date'];
    if (lessonDate.isAfter(startTime) && lessonDate.isBefore(endTime)) {
      lessonCounts++; // 현재 학기 수업 개수 증가
    }
  }
  return lessonCounts;
}


class TeacherCard extends StatelessWidget {
  final String teacherName;
  final int classCount;
  final Color cardColor;
  final List<Map<String, dynamic>> studentschedule;
  final Map<String, dynamic> teacher;
  final Map<String, Map<String, dynamic>> schedules;
  final Map<String, dynamic> workschedule;

  TeacherCard({
    required this.teacherName,
    required this.classCount,
    required this.cardColor,
    required this.studentschedule,
    required this.teacher,
    required this.schedules,
    required this.workschedule
  });

  @override
  Widget build(BuildContext context) {
    TextStyle style = const TextStyle(
        color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);
    List<String> studentNames = studentschedule.map((s) => s['name'] as String).toList();
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: PRIMARY_COLOR, width: 1),
      ),
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: cardColor,
                  child: Icon(Icons.person, color: Colors.white, size: 30),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teacherName + ' 선생님',
                        style: style.copyWith(color: cardColor, fontSize: 20, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        "담당 학생: ${studentNames.join(', ')}",
                        style: style.copyWith(fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      RichText(
                        text: TextSpan(
                          style: style.copyWith(fontSize: 15), // 기본 스타일
                          children: [
                            TextSpan(
                              text: "이번 달 수업 횟수: ", // 기본 색상
                              style: style.copyWith(color: Colors.black),
                            ),
                            TextSpan(
                              text: "$classCount ", // 변경할 부분
                              style: style.copyWith(color: PRIMARY_COLOR, fontWeight: FontWeight.bold), // 색상 및 강조
                            ),
                            TextSpan(
                              text: "회, ", // 변경할 부분
                              style: style.copyWith(color: Colors.black), // 색상 및 강조
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLabeledIcon(Icons.calendar_today, "캘린더", cardColor, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TeacherCalendar(teacherId: teacher['id'],),
                    ),
                  );
                }),
                _buildLabeledIcon(Icons.search_rounded, "상세 정보", cardColor, () {
                  _showTeacherDetails(context, teacher, studentschedule, workschedule);
                }),
                _buildLabeledIcon(Icons.edit, "정보 수정", cardColor, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditTeacherPage(teacher: teacher, workschedule: workschedule),
                    ),
                  );
                }),
                _buildLabeledIcon(Icons.delete, "삭제", Colors.redAccent, () {
                  if(teacher['studentIds'].length != 0 ){
                  // 만약 담당 학생 리스트가 0이 아니라면 (담당으로 맡는 학생이 1명 이상)
                  showCannotDeleteTeacherDialog(context);
                } else {
                  showDeleteTeacherDialog(context, teacher['name'], teacher['id']);
                }
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabeledIcon(IconData icon, String label, Color color, VoidCallback onPressed) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: (0.2 * 255)),
          ),
          padding: EdgeInsets.all(4),
          child: IconButton(
            icon: Icon(icon, color: color, size: 26),
            onPressed: onPressed,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w300, fontFamily: 'ELAND', color: Colors.black),
        )
      ],
    );
  }
}

// 정보 항목을 깔끔하게 정리하는 함수
Widget _infoRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$label: ",
            style: style.copyWith(color: PRIMARY_COLOR, fontWeight: FontWeight.w500, fontSize: 18)), // 글자 크기 증가
        Expanded(
          child: Text(
            value,
            style: style.copyWith(fontSize: 16),
            softWrap: true, // 줄 바꿈 가능하도록 설정
            // maxLines: null, // 제한 없이 여러 줄 표시
        ),),
      ],
    ),
  );
}