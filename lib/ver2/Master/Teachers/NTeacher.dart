import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';

class NewTeacherDialog extends StatefulWidget {
  @override
  _NewTeacherDialogState createState() => _NewTeacherDialogState();
}

class _NewTeacherDialogState extends State<NewTeacherDialog> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final List<String> days = ["월", "화", "수", "목", "금", "토"];
  final Map<String, bool> selectedDays = {
    "월": false,
    "화": false,
    "수": false,
    "목": false,
    "금": false,
    "토": false,
  };

  final Map<String, TimeOfDay?> startTimes = {};
  final Map<String, TimeOfDay?> endTimes = {};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: SingleChildScrollView( // 오버플로우 방지
        child: Padding(
          padding: const EdgeInsets.all(12.0), // 패딩 줄이기
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("근무 시간 설정", style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w500)),

              const SizedBox(height: 8),
              //  이름 & 비밀번호 입력 필드
              _buildTextField(nameController, "선생님 성함"),
              const SizedBox(height: 8),
              _buildTextField(passwordController, "비밀 번호", obscureText: false),

              const SizedBox(height: 12),

              // 요일 체크박스 (가로 정렬) → 간격 줄이기
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround, // 더 균형 있게 정렬
                children: days.map((day) {
                  return Column(
                    children: [
                      Text(day, style: style.copyWith(fontSize: 14)), // 글자 크기 줄이기
                      SizedBox(height: 2),
                      Transform.scale(
                        scale: 0.85, // 체크박스 크기 줄이기
                        child: Checkbox(
                          value: selectedDays[day],
                          onChanged: (bool? value) {
                            setState(() {
                              selectedDays[day] = value ?? false;
                            });
                          },
                          activeColor: PRIMARY_COLOR,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),

              const SizedBox(height: 6), // 여백 줄이기

              // 요일별 시작/종료 시간 설정
              Column(
                children: days.where((day) => selectedDays[day] == true).map((day) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("$day:", style: style.copyWith(fontSize: 16, fontWeight: FontWeight.w500)),
                      _buildTimeButton(day, isStartTime: true),
                      _buildTimeButton(day, isStartTime: false),
                    ],
                  );
                }).toList(),
              ),


              const SizedBox(height: 10),

              // 취소 / 저장 버튼 → 간격 줄이기
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("취소", style: style.copyWith(color: Colors.red, fontSize: 14)),
                  ),
                  TextButton(
                    onPressed: _saveToFirebase,
                    child: Text("저장", style: style.copyWith(color: PRIMARY_COLOR, fontSize: 14)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  // 텍스트 필드 위젯
  Widget _buildTextField(TextEditingController controller, String label, {bool obscureText = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  Widget _buildTimeButton(String day, {required bool isStartTime}) {
    return ElevatedButton(
      onPressed: () async {
        TimeOfDay? pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: 9, minute: 0),
        );

        if (pickedTime != null) {
          setState(() {
            if (isStartTime) {
              startTimes[day] = pickedTime;
            } else {
              endTimes[day] = pickedTime;
            }
          });
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), // 버튼 크기 줄이기
        side: BorderSide(color: PRIMARY_COLOR),
        minimumSize: Size(85, 30), // 버튼 최소 크기 조정
      ),
      child: Text(
        isStartTime
            ? (startTimes[day]?.format(context) ?? "시작 시간")
            : (endTimes[day]?.format(context) ?? "종료 시간"),
        style: style.copyWith(color: Color(0xff708C7A), fontSize: 12),
      ),
    );
  }
  // Firebase에 저장하는 함수
  void _saveToFirebase() async {
    if (nameController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("이름과 비밀번호를 입력하세요.")));
      return;
    }
    String teacherId = _generateTeacherID();
    Map<String, dynamic> workSchedule = {};
    // 한글 요일 → 영문 코드 변환
    Map<String, String> dayCodeMap = {
      "월": "MO",
      "화": "TU",
      "수": "WE",
      "목": "TH",
      "금": "FR",
      "토": "SA",
    };

    selectedDays.forEach((day, isSelected) {
      if (isSelected && startTimes.containsKey(day) && endTimes.containsKey(day)) {
        String dayCode = dayCodeMap[day] ?? day; // 변환, 기본값은 기존 day 사용
        workSchedule[dayCode] = {
          "startTime": "${startTimes[day]!.hour.toString().padLeft(2, '0')}:${startTimes[day]!.minute.toString().padLeft(2, '0')}",
          "endTime": "${endTimes[day]!.hour.toString().padLeft(2, '0')}:${endTimes[day]!.minute.toString().padLeft(2, '0')}",
        };
      }
    });

    FirebaseFirestore firestore = FirebaseFirestore.instance;
    WriteBatch batch = firestore.batch();
    // 1. users 컬렉션에 정보를 저장
    DocumentReference userDocRef = firestore.collection('users').doc(teacherId);
    batch.set(userDocRef, {
      "name": nameController.text,
      "password": passwordController.text,
      "role": "teacher",
      "studentIds": [],
    });

    // 2. `userByName` 컬렉션 업데이트 (동명이인 방지)
    DocumentReference userByNameDocRef = firestore.collection('usersByName').doc(nameController.text);
    DocumentSnapshot userByNameSnapshot = await userByNameDocRef.get();
    if (!userByNameSnapshot.exists) {
      // 문서가 없으면 새로 생성
      batch.set(userByNameDocRef, {
        "userIds": [teacherId], // 새 리스트 생성
      });
    } else {
      // 문서가 있으면 기존 리스트에 추가
      List<dynamic> userIds = List.from(userByNameSnapshot["userIds"]);
      if (!userIds.contains(teacherId)) {
        userIds.add(teacherId);
        batch.update(userByNameDocRef, {"userIds": userIds});
      }
    }

    // 3. `availableSlots` 컬렉션에 저장
    DocumentReference availableSlotsDocRef = firestore.collection('availableSlots').doc(teacherId);
    batch.set(availableSlotsDocRef, {
      "bookedSlots": {},
      "workSchedule": workSchedule,
    });
    // **모든 배치 실행**
    await batch.commit();

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "선생님 추가 완료!",
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
  }
}
String _generateTeacherID() {
  String date = DateTime.now().toString().split(" ")[0].replaceAll("-", "").substring(2); // 240301
  String randomPart = (100 + DateTime.now().millisecond % 900).toString(); // 랜덤 2자리
  return "TCH_${date}${randomPart}";
}

// 버튼을 누르면 창을 띄우는 코드
void showNewTeacherDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return NewTeacherDialog(); // 다이얼로그 위젯 호출
    },
  );
}

