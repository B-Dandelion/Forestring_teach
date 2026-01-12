import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

Future<void> _showBanTimeDialog(BuildContext context) async {
  String? selectedTeacherId;
  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedStartTime = TimeOfDay(hour: 9, minute: 0);
  TimeOfDay selectedEndTime = TimeOfDay(hour: 10, minute: 0);

  final provider = Provider.of<MasterProvider>(context, listen: false);
  List<Map<String, dynamic>> teachers = provider.teachers;

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text("예약 금지 시간 설정", style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w500)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 선생님 선택
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: "선생님 선택",
                    labelStyle: style.copyWith(fontSize: 16, color: PRIMARY_COLOR),
                  ),
                  value: selectedTeacherId,
                  items: teachers.map((teacher) {
                    return DropdownMenuItem(
                      value: teacher['id'].toString(),
                      child: Text(teacher['name'] + ' 선생님', style: style),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      selectedTeacherId = newValue;
                    });
                  },
                ),
                const SizedBox(height: 10),

                // 날짜 선택
                ListTile(
                  leading: Icon(Icons.calendar_today, color: PRIMARY_COLOR),
                  title: Text(DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(selectedDate), style: style),
                  onTap: () async {
                    DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2024, 1, 1),
                      lastDate: DateTime(2030, 12, 31),
                    );
                    if (pickedDate != null) {
                      setState(() {
                        selectedDate = pickedDate;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),

                // 시작 시간 선택
                ListTile(
                  leading: Icon(Icons.access_time, color: PRIMARY_COLOR),
                  title: Text("시작 시간: ${selectedStartTime.format(context)}", style: style),
                  onTap: () async {
                    TimeOfDay? pickedTime = await showTimePicker(
                      context: context,
                      initialTime: selectedStartTime,
                    );
                    if (pickedTime != null) {
                      setState(() {
                        selectedStartTime = pickedTime;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),

                // 종료 시간 선택
                ListTile(
                  leading: Icon(Icons.access_time, color: PRIMARY_COLOR),
                  title: Text("종료 시간: ${selectedEndTime.format(context)}", style: style),
                  onTap: () async {
                    TimeOfDay? pickedTime = await showTimePicker(
                      context: context,
                      initialTime: selectedEndTime,
                    );
                    if (pickedTime != null) {
                      setState(() {
                        selectedEndTime = pickedTime;
                      });
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("취소", style: style.copyWith(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedTeacherId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("선생님을 선택해주세요.")));
                    return;
                  }
                  _saveBanTime(selectedTeacherId!, selectedDate, selectedStartTime, selectedEndTime);
                  Navigator.pop(context);
                  if (!context.mounted) return; // ontext 유효성 체크
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "예약 금지 시간이 설정되었습니다.",
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
                },
                style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_COLOR),
                child: Text("확인", style: style.copyWith(color: Colors.white)),
              ),
            ],
          );
        },
      );
    },
  );
}
// 예약 금지 시간 저장 함수
void _saveBanTime(String teacherId, DateTime date, TimeOfDay startTime, TimeOfDay endTime) {
  FirebaseFirestore firestore = FirebaseFirestore.instance;
  DocumentReference teacherRef = firestore.collection('availableSlots').doc(teacherId);

  DateTime startDateTime = DateTime(date.year, date.month, date.day, startTime.hour, startTime.minute);
  DateTime endDateTime = DateTime(date.year, date.month, date.day, endTime.hour, endTime.minute);

  String banId = firestore.collection('bookedSlots').doc().id;
  // 예약 금지 시간 정보
  Map<String, dynamic> banTimeData = {
    'date': Timestamp.fromDate(startDateTime),
    'endDate': Timestamp.fromDate(endDateTime),
    'duration': endDateTime.difference(startDateTime).inMinutes, // 분 단위 변환
    'isRescheduled': false,
    'studentId': "BanTime",
    'status': 'ban',
  };
  // Firestore에 데이터 추가
  teacherRef.set({
    'bookedSlots': {banId: banTimeData}
  }, SetOptions(merge: true)).then((_) {
    print("예약 금지 시간 추가 완료: $startDateTime ~ $endDateTime");
  }).catchError((error) {
    print("예약 금지 시간 추가 실패: $error");
  });

}

class BanTimeManagementPage extends StatefulWidget {
  const BanTimeManagementPage({super.key});

  @override
  _BanTimeManagementPageState createState() => _BanTimeManagementPageState();
}

class _BanTimeManagementPageState extends State<BanTimeManagementPage> {
  String? selectedTeacherId;
  List<Map<String, dynamic>> banTimes = [];

  @override
  void initState() {
    super.initState();
    // 기본적으로 첫 번째 선생님의 데이터를 불러옴
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<MasterProvider>(context, listen: false);
      if (provider.teachers.isNotEmpty) {
        setState(() {
          selectedTeacherId = provider.teachers.first['id'];
        });
        _loadBanTimesFromProvider(provider.teachers.first['id']); // 프로바이더에서 불러오기
      }
    });
  }
  void _loadBanTimesFromProvider(String teacherId) {
    final provider = Provider.of<MasterProvider>(context, listen: false);

    // provider.bookedSlots 내부에서 해당 선생님의 데이터 가져오기
    if (provider.bookedSlots.containsKey(teacherId)) {
      Map<String, Map<String, dynamic>> bookedSlots = provider.bookedSlots[teacherId]!;
      List<Map<String, dynamic>> fetchedBanTimes = [];

      bookedSlots.forEach((key, value) {
        if (value['status'] == 'ban') {
          fetchedBanTimes.add({
            "id": key,
            "date": value['date'],
            "duration": value['duration'],
          });
        }
      });

      setState(() {
        banTimes = fetchedBanTimes;
      });
    }
  }

  void _removeBanTime(String banId) async {
    if (selectedTeacherId == null) return;

    FirebaseFirestore firestore = FirebaseFirestore.instance;
    DocumentReference teacherRef =
    firestore.collection('availableSlots').doc(selectedTeacherId);

    await teacherRef.update({"bookedSlots.$banId": FieldValue.delete()});

    setState(() {
      banTimes.removeWhere((ban) => ban["id"] == banId);
    });
  }

  void _showAddBanTimeDialog() async {
    await _showBanTimeDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MasterProvider>(context, listen: false);
    List<Map<String, dynamic>> teachers = provider.teachers;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "예약 금지 시간 관리",
          style: style.copyWith(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.white),
        ),
        backgroundColor: PRIMARY_COLOR,
        iconTheme: IconThemeData(color: Colors.white), // 아이콘 색상 변경
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 선생님 선택 드롭다운
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: "선생님 선택",
                labelStyle: style.copyWith(fontSize: 16, color: PRIMARY_COLOR),
              ),
              value: selectedTeacherId,
              items: teachers.map((teacher) {
                return DropdownMenuItem(
                  value: teacher['id'].toString(),
                  child: Text(teacher['name'] +' 선생님', style: style.copyWith(fontSize: 16)),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  selectedTeacherId = newValue!;
                });
                _loadBanTimesFromProvider(newValue!);
              },
            ),
            const SizedBox(height: 20),

            // 예약 금지 시간 목록
            Expanded(
              child: banTimes.isEmpty
                  ? Center(child: Text(
                "예약 금지된 시간이 없습니다.",
                style: style.copyWith(fontSize: 16)),
              )
                  : ListView.builder(
                itemCount: banTimes.length,
                itemBuilder: (context, index) {
                  var ban = banTimes[index];
                  // 날짜 형식 변경 (2025 - 03 - 21 (금))
                  String formattedDate = DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(ban['date']);
                  // 시작 시간 (9:00)
                  String formattedStart = DateFormat('H:mm').format(ban['date']);
                  // 종료 시간 (10:00)
                  String formattedEnd = DateFormat('H:mm').format(ban['date'].add(Duration(minutes: ban['duration'])));

                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(Icons.block, color: Colors.redAccent),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formattedDate, // "2025 - 03 - 21 (금)"
                            style: style.copyWith(fontSize: 14, fontWeight: FontWeight.w300),
                          ),
                          Text(
                            "$formattedStart ~ $formattedEnd", // "9:00 ~ 10:00"
                            style: style.copyWith(fontSize: 16, fontWeight: FontWeight.w300),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          try {
                            _removeBanTime(ban["id"]);
                            if (!context.mounted) return; // ontext 유효성 체크
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "예약 금지 설정이 해제되었습니다.",
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
                          } catch (e) {
                            debugPrint("벤타임 삭제 오류: $e");

                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "예약 금지 시간 삭제 중 오류가 발생했습니다.",
                                    style: style.copyWith(color: Colors.black),
                                    textAlign: TextAlign.center,
                                  ),
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  duration: Duration(seconds: 2),
                                ));
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: PRIMARY_COLOR,
        onPressed: () async {
          try {
            await _showBanTimeDialog(context);
          } catch (e) {
            debugPrint("벤타임 저장 오류: $e");

            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "예약 금지 시간 저장 중 오류가 발생했습니다.",
                    style: style.copyWith(color: Colors.black),
                    textAlign: TextAlign.center,
                  ),
                  backgroundColor: Colors.redAccent,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  duration: Duration(seconds: 2),
                ));
          }
          },
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

