import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SemesterManagementPage extends StatefulWidget {
  const SemesterManagementPage({super.key});

  @override
  _SemesterManagementPageState createState() => _SemesterManagementPageState();
}

class _SemesterManagementPageState extends State<SemesterManagementPage> {
  late String selectedSemester;
  late DateTime startDate;
  late DateTime endDate;
  late List<Map<String, DateTime>> holidays;

  @override
  void initState() {
    super.initState();
    // 현재 날짜 기반으로 학기 키 값 생성
    selectedSemester = "${nowsemester.year}-${nowsemester.month.toString().padLeft(2, '0')}";
    // 만약 해당 학기가 존재하지 않으면 첫 번째 학기로 기본 설정
    if (!SemesterTerm.containsKey(selectedSemester)) {
      selectedSemester = SemesterTerm.keys.first;
    }
    _loadSemesterData(selectedSemester);
  }

  // 선택한 학기의 정보를 로드
  void _loadSemesterData(String semesterKey) {
    var semester = SemesterTerm[semesterKey];
    setState(() {
      selectedSemester = semesterKey;
      startDate = semester!["startDate"];
      endDate = semester["endDate"];
      holidays = List<Map<String, DateTime>>.from(semester["holidays"]);
    });
  }

  // 날짜 선택 함수
  Future<void> _pickDate(BuildContext context, bool isStart) async {
    DateTime initialDate = isStart ? startDate : endDate;
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (pickedDate != null) {
      setState(() {
        if (isStart) {
          startDate = pickedDate;
        } else {
          endDate = pickedDate;
        }
      });
    }
  }

  // 휴일 추가
  void _addHoliday() {
    setState(() {
      holidays.add({"startDate": DateTime.now(), "endDate": DateTime.now().add(Duration(days: 3))});
    });
  }

  // 휴일 삭제
  void _removeHoliday(int index) {
    setState(() {
      holidays.removeAt(index);
    });
  }

  // Firestore & 전역 변수 업데이트
  Future<void> _saveSemesterData() async {
    FirebaseFirestore firestore = FirebaseFirestore.instance;
    DocumentReference semesterRef = firestore.collection('semesters').doc(selectedSemester);

    // Firestore 업데이트
    await semesterRef.update({
      "startDate": Timestamp.fromDate(startDate),
      "endDate": Timestamp.fromDate(endDate),
      "holidays": holidays.map((holiday) => {
        "startDate": Timestamp.fromDate(holiday["startDate"]!),
        "endDate": Timestamp.fromDate(holiday["endDate"]!),
      }).toList(),
    });

    // 전역 변수 업데이트
    SemesterTerm[selectedSemester] = {
      "startDate": startDate,
      "endDate": endDate,
      "holidays": holidays,
    };

    print("학기 저장 완료: $selectedSemester");
  }

  Future<DateTimeRange?> _pickDateRange(BuildContext context, DateTime start, DateTime end) async {
    return await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: start, end: end),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2030, 12, 31),
      locale: Locale('ko', 'KR'), // 한국어 설정
    );
  }
  void _updateHoliday(int index, DateTimeRange newDateRange) {
    setState(() {
      holidays[index] = {
        "startDate": newDateRange.start,
        "endDate": newDateRange.end,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("학기 관리",
            style: style.copyWith(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
        backgroundColor: PRIMARY_COLOR,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 학기 선택 드롭다운
            Text("학기 선택", style: style.copyWith(fontSize: 16, fontWeight: FontWeight.bold)),
            DropdownButton<String>(
              value: selectedSemester,
              isExpanded: true,
              onChanged: (newSemester) {
                if (newSemester != null) {
                  _loadSemesterData(newSemester);
                }
              },
              items: SemesterTerm.keys.map((semester) {
                // "YYYY-MM" -> "YYYY년 M월 학기" 변환
                List<String> parts = semester.split('-');
                String formattedSemester = "${parts[0]}년 ${int.parse(parts[1])}월 학기";
                return DropdownMenuItem(
                  value: semester,
                  child: Text(formattedSemester, style: style.copyWith(fontSize: 16)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 학기 날짜 설정
            Text("학기 기간", style: style.copyWith(fontSize: 16, fontWeight: FontWeight.bold)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("시작: ${DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(startDate)}", style: style,),
                ElevatedButton(
                  onPressed: () => _pickDate(context, true),
                  child: Text("변경", style: style,),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("종료: ${DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(endDate)}", style: style),
                ElevatedButton(
                  onPressed: () => _pickDate(context, false),
                  child: Text("변경", style: style),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 휴일 목록
            Text("휴일 목록", style: style.copyWith(fontSize: 16, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: holidays.length,
                itemBuilder: (context, index) {
                  var holiday = holidays[index];
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(
                        "${DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(holiday["startDate"]!)} ~ ${DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(holiday["endDate"]!)}",
                        style: style.copyWith(fontSize: 14),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeHoliday(index),
                      ),
                      onTap: () async {
                        // 날짜 선택 함수 실행
                        DateTimeRange? newDateRange = await _pickDateRange(context, holiday["startDate"]!, holiday["endDate"]!);
                        if (newDateRange != null) {
                          _updateHoliday(index, newDateRange);
                        }
                      },
                    ),
                  );
                },
              ),
            ),

            // 휴일 추가 버튼
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _addHoliday,
                icon: Icon(Icons.add, color: PRIMARY_COLOR),
                label: Text("휴일 추가", style: style.copyWith(color: PRIMARY_COLOR)),
              ),
            ),

            // 저장 버튼
            Center(
              child: ElevatedButton(
                onPressed: () {
                  try {
                    _saveSemesterData;
                    if (!context.mounted) return; // ontext 유효성 체크
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "학기 정보가 성공적으로 저장되었습니다.",
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
                    debugPrint("학기 저장 오류: $e");

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "학기 저장 중 오류가 발생했습니다.",
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: PRIMARY_COLOR,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                ),
                child: Text("저장", style: style.copyWith(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
