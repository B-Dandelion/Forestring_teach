import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:forestring_teacher_2/ver2/Master/Students/StudentE.dart';
import 'package:intl/intl.dart';
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
class EditLessonPage extends StatefulWidget {
  final String studentName;
  final String teacherName;
  final int? index; // 기존 수업일 때만 index 필요
  final Map<String, dynamic>? lesson;
  final Function(Map<String, dynamic>) onSave;
  final bool isNewLesson; // 새 수업 추가 여부

  EditLessonPage({
    required this.studentName,
    required this.teacherName,
    this.index,
    this.lesson,
    required this.onSave,
    this.isNewLesson = false, // 기본값: 기존 수업 수정
  });

  @override
  _EditLessonPageState createState() => _EditLessonPageState();
}

class _EditLessonPageState extends State<EditLessonPage> {
  late DateTime selectedDate;
  late TimeOfDay selectedStartTime;
  late int selectedDuration;

  @override
  void initState() {
    super.initState();
    if (widget.isNewLesson) {
      // 새로운 수업: 기본값 설정
      selectedDate = DateTime.now();
      selectedStartTime = TimeOfDay(hour: 16, minute: 0);
      selectedDuration = 30;
    } else {
      // 기존 수업 수정
      selectedDate = getFirstLessonAfterN(now, widget.lesson!);
      selectedStartTime = TimeOfDay(
        hour: int.parse(widget.lesson!['startTime'].split(":")[0]),
        minute: int.parse(widget.lesson!['startTime'].split(":")[1]),
      );
      selectedDuration = widget.lesson!['duration'];
    }
  }

  // 날짜 선택 함수
  void _pickDate() async {
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
  }

  // 시간 선택 함수
  void _pickTime() async {
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: selectedStartTime,
    );
    if (pickedTime != null) {
      setState(() {
        selectedStartTime = pickedTime;
      });
    }
  }

  // 변경된 데이터 저장 후 이전 화면으로 복귀
  void _saveChanges() {
    Map<String, dynamic> newLesson = {
      'day' : _getDayCode(selectedDate.weekday),
      'date': selectedDate,
      'startTime': "${selectedStartTime.hour.toString().padLeft(2, '0')}:${selectedStartTime.minute.toString().padLeft(2, '0')}",
      'duration': selectedDuration,
    };

    widget.onSave(newLesson);
    Navigator.pop(context);
  }
  String formattedDate = DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(now);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isNewLesson
              ? "${widget.studentName}님 새 수업 추가"
              : "${widget.studentName}님 수업 ${widget.index! + 1} 수정",
          style: style.copyWith(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500),
        ),
        backgroundColor: PRIMARY_COLOR,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 변경 수업 날짜
            Text("수업 날짜", style: style.copyWith(color: PRIMARY_COLOR, fontWeight: FontWeight.w500, fontSize: 18)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('yyyy-MM-dd (E)', 'ko_KR').format(selectedDate), style: style.copyWith(fontSize: 16)),
                IconButton(
                  icon: Icon(Icons.calendar_today, color: Color(0xff3E6F58)),
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (!widget.isNewLesson) // 새 수업 추가 시 안내문 제거
              Text("* 변경 수업 기준 같은 주 수업부터 변경 사항이 적용됩니다",
                style: style.copyWith(fontSize: 12, color: Colors.red),
              ),
            const SizedBox(height: 12),

            // 변경 수업 시간
            Text("수업 시간", style: style.copyWith(color: PRIMARY_COLOR, fontWeight: FontWeight.w500, fontSize: 18)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${selectedStartTime.format(context)} ~ "
                    "${selectedStartTime.replacing(
                  hour: selectedStartTime.hour + (selectedStartTime.minute + selectedDuration) ~/ 60,
                  minute: (selectedStartTime.minute + selectedDuration) % 60,
                ).format(context)}", style: style.copyWith(fontSize: 16)),
                IconButton(
                  icon: Icon(Icons.access_time, color: Color(0xff3E6F58)),
                  onPressed: _pickTime,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 수업 길이 선택
            Text("수업 길이", style: style.copyWith(color: PRIMARY_COLOR, fontWeight: FontWeight.w500, fontSize: 18)),
            DropdownButtonFormField<int>(
              value: selectedDuration,
              decoration: InputDecoration(border: OutlineInputBorder()),
              items: [15, 30, 45, 60, 90].map((duration) {
                return DropdownMenuItem(
                  value: duration,
                  child: Text("$duration 분", style: style.copyWith(fontSize: 16)),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  selectedDuration = newValue!;
                });
              },
            ),
            const SizedBox(height: 10),
            buildPreviewHeader(context),
            const SizedBox(height: 10),
            LessonPreviewWidget(
              selectedDate: selectedDate,
              selectedTime: selectedStartTime,
              selectedDuration: selectedDuration,
              student: widget.studentName,
              teacher: widget.teacherName,
            ),
            // 저장 버튼
            Center(
              child: ElevatedButton(
                onPressed: _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: PRIMARY_COLOR,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                ),
                child: Text(widget.isNewLesson ? "수업 추가" : "저장", style: style.copyWith(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// 구분선 위젯
Widget buildPreviewHeader(BuildContext context) {
  return Container(
    width: MediaQuery.of(context).size.width, // 화면 가로 전체 크기 적용
    padding: const EdgeInsets.symmetric(horizontal: 16), // 좌우 여백 조정 (디자인에 맞게)
    child: Row(
      children: [
        const Expanded(
          child: Divider(
            color: PRIMARY_COLOR, // 선 색상
            thickness: 1.5, // 선 두께
            endIndent: 10, // 글자 왼쪽 여백
          ),
        ),
        Text(
          "수업 미리보기",
          style: style.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: PRIMARY_COLOR,
          ),
        ),
        const Expanded(
          child: Divider(
            color: PRIMARY_COLOR, // 선 색상
            thickness: 1.5, // 선 두께
            indent: 10, // 글자 오른쪽 여백
          ),
        ),
      ],
    ),
  );
}
class LessonPreviewWidget extends StatelessWidget {
  final DateTime selectedDate;
  final TimeOfDay selectedTime;
  final int selectedDuration;
  final String student;
  final String teacher;

  LessonPreviewWidget({
    required this.selectedDate,
    required this.selectedTime,
    required this.selectedDuration,
    required this.student,
    required this.teacher,
  });

  @override
  Widget build(BuildContext context) {
    List<DateTime> upcomingLessons = _generateFutureLessons(selectedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListView.separated(
          shrinkWrap: true, // 리스트 자체 스크롤 방지
          itemCount: upcomingLessons.length,
          separatorBuilder: (context, index) => SizedBox(height: 5), // 아이템 간격 조절
          itemBuilder: (context, index) {
            DateTime lessonDate = upcomingLessons[index];
            DateTime startDateTime = DateTime(
              lessonDate.year, lessonDate.month, lessonDate.day,
              selectedTime.hour, selectedTime.minute,
            );
            DateTime endDateTime = startDateTime.add(Duration(minutes: selectedDuration));

            return LessonCard(
              startTime: startDateTime,
              endTime: endDateTime,
              month: lessonDate.month,
              date: lessonDate.day,
              student: student,
              teacher: teacher,
            );
          },
        ),
      ],
    );
  }

  // 미래 수업 일정 계산 (주 1회 반복, 4주 생성)
  List<DateTime> _generateFutureLessons(DateTime startDate) {
    List<DateTime> futureLessons = [];
    DateTime nextLessonDate = startDate;

    for (int i = 0; i < 4; i++) { // 4주치 생성
      futureLessons.add(nextLessonDate);
      nextLessonDate = nextLessonDate.add(Duration(days: 7)); // 주 1회씩 증가
    }

    return futureLessons;
  }
}




