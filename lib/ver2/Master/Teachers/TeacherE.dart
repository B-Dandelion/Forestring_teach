import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';

class EditTeacherPage extends StatefulWidget {
  final Map<String, dynamic> teacher;
  final Map<String, dynamic> workschedule;

  const EditTeacherPage({super.key, required this.teacher, required this.workschedule});

  @override
  _EditTeacherPageState createState() => _EditTeacherPageState();
}

class _EditTeacherPageState extends State<EditTeacherPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // 요일 리스트
  final List<String> days = ["월", "화", "수", "목", "금", "토"];
  final Map<String, String> dayMap = {
    "월": "MO",
    "화": "TU",
    "수": "WE",
    "목": "TH",
    "금": "FR",
    "토": "SA",
  };
  Map<String, dynamic> workschedule = {};
  Map<String, bool> localWorkSchedule = {}; // UI에서 관리하는 근무 여부

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.teacher['name'];
    _passwordController.text = widget.teacher['password'].toString();
    workschedule = Map.from(widget.workschedule);
    // Firestore에 있는 데이터는 `true`, 없는 데이터는 `false`
    for (var day in dayMap.values) {
      if (widget.workschedule[day]!=null) {
        localWorkSchedule[day] = true;
      } else {
        localWorkSchedule[day] = false;
      }
    }
  }

  // Firestore 업데이트 함수
  Future<void> _updateTeacherInfo() async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    WriteBatch batch = firestore.batch();

    String oldName = widget.teacher['name']; // 기존 이름
    String newName = _nameController.text;  // 변경된 이름
    String teacherId = widget.teacher['id'];

    DocumentReference availableSlotsDocRef = firestore.collection('availableSlots').doc(teacherId);
    batch.update(availableSlotsDocRef, {
      "workSchedule": workschedule,
    });

    DocumentReference usersDocRef = firestore.collection('users').doc(teacherId);
    batch.update(usersDocRef, {
      'name': newName,
      'password': _passwordController.text,
    });

    // 3월 21일 추가 >> 1. userbyname에 있는 기존 이름 문서 삭제
    DocumentReference oldNameDocRef = firestore.collection('usersByName').doc(oldName);
    DocumentSnapshot oldNameDocSnapshot = await oldNameDocRef.get();

    if (oldNameDocSnapshot.exists) {
      List<dynamic> userIds = List.from(oldNameDocSnapshot['userIds']);
      userIds.remove(teacherId);
      if (userIds.isEmpty) {
        batch.delete(oldNameDocRef); // userIds가 비면 문서 삭제
      } else {
        batch.update(oldNameDocRef, {'userIds': userIds});
      }
    }
    // 3월 21일 추가 >> 2. 새로운 `usersByName` 문서에 teacherId 추가
    DocumentReference newNameDocRef = firestore.collection('usersByName').doc(newName);
    DocumentSnapshot newNameDocSnapshot = await newNameDocRef.get();

    if (newNameDocSnapshot.exists) {
      List<dynamic> userIds = List.from(newNameDocSnapshot['userIds']);
      if (!userIds.contains(teacherId)) {
        userIds.add(teacherId);
        batch.update(newNameDocRef, {'userIds': userIds});
      }
    } else {
      batch.set(newNameDocRef, {'userIds': [teacherId]});
    }

    await batch.commit(); // Firestore에 변경 사항 적용
    Navigator.pop(context);
  }
  // 시간 선택 다이얼로그
  Future<void> _selectTime(BuildContext context, String day, String type) async {
    TimeOfDay initialTime = TimeOfDay(hour: 9, minute: 0);
    if (workschedule.containsKey(day) && workschedule[day]![type] != null) {
      initialTime = TimeOfDay(
        hour: int.parse(workschedule[day]![type]!.split(":")[0]),
        minute: int.parse(workschedule[day]![type]!.split(":")[1]),
      );
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      setState(() {
        if (!workschedule.containsKey(day)) {
          workschedule[day] = {}; // 근무 시간이 없었다면 새로 추가
        }
        workschedule[day]![type] = "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
      });
    }
  }
  void _addWorkSchedule(String day) {
    setState(() {
      workschedule[day] = {
        'startTime': '09:00',
        'endTime': '18:00',
      };
      localWorkSchedule[day] = true; // UI에서 근무 추가 상태 업데이트
    });
  }
  // 근무 삭제 버튼 클릭 시 Firestore에서 삭제 (UI에도 반영)
  void _removeWorkSchedule(String day) {
    setState(() {
      workschedule.remove(day);
      localWorkSchedule[day] = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.teacher['name']} 정보 수정",
            style: style.copyWith(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
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
            // 근무 시간 설정
            Text("근무 시간 설정", style: style.copyWith(color: Color(0xff3E6F58), fontSize: 18, fontWeight: FontWeight.w500)),

            Expanded(
              child: ListView.builder(
                itemCount: dayMap.length,
                itemBuilder: (context, index) {
                  String koreanDay = dayMap.keys.elementAt(index); // "월", "화" ...
                  String firestoreKey = dayMap[koreanDay]!; // "MO", "TU", ...

                  bool hasWorkSchedule = workschedule.containsKey(firestoreKey);

                  return Card(
                    elevation: 2,
                    margin: EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                koreanDay,
                                style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w500),
                              ),
                              Switch(
                                value: hasWorkSchedule,
                                onChanged: (value) {
                                  setState(() {
                                    if (value) {
                                      _addWorkSchedule(firestoreKey);
                                    } else {
                                      _removeWorkSchedule(firestoreKey);
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                          if (hasWorkSchedule) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("시작 시간: ${workschedule[firestoreKey]!['startTime']}", style: style),
                                ElevatedButton(
                                  onPressed: () => _selectTime(context, firestoreKey, 'startTime'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Color(0xff3E6F58)),
                                  child: Icon(Icons.more_time_rounded, color: Colors.white),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("종료 시간: ${workschedule[firestoreKey]!['endTime']}", style: style),
                                ElevatedButton(
                                  onPressed: () => _selectTime(context, firestoreKey, 'endTime'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Color(0xff3E6F58)),
                                  child: Icon(Icons.more_time_rounded, color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Center(
              child: ElevatedButton(
                onPressed: _updateTeacherInfo,
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
