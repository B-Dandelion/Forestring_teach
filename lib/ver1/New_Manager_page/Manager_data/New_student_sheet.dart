import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/New_Data/lessonClass.dart';
import 'package:forestring_teacher_2/ver1/New_Data/new_constant.dart';
import 'package:forestring_teacher_2/ver1/New_Data/studentClass.dart';
import 'package:forestring_teacher_2/ver1/New_Data/teacherClass.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/Manager_data/CustomTextField.dart';
import 'package:intl/intl.dart';


class New_student_sheet extends StatefulWidget {
  const New_student_sheet({super.key});

  @override
  State<New_student_sheet> createState() => _New_student_sheet();
}

class _New_student_sheet extends State<New_student_sheet>{
  TeacherClass TMPTeacher = Allteachers[0];
  DateTime startTime = DateTime.now();
  DateTime tmp = DateTime(2024,10,10,10,00);
  TimeOfDay TMP = TimeOfDay.fromDateTime(DateTime(2024,10,10,10,00));

  String? Name = '';
  String? pw = '';
  String? ID = '';
  final GlobalKey<FormState> formKey = GlobalKey();

  bool isSaving = false;

  @override
  Widget build(BuildContext context){
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Form(
        key: formKey,
        child : SafeArea(
            child: Container(
                height: MediaQuery.of(context).size.height / 2 + bottomInset,
                color: Colors.white,
                child: Padding( padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomInset),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: CustomTextField(label: '성함', isTime: false,
                                validator: contentValidater,
                                onSaved: (String? val){
                                  Name = val!;})),
                            const SizedBox(width: 16),
                            Expanded(child: CustomTextField(label: '비밀번호', isTime: true,
                                validator: contentValidater,
                                onSaved: (String? val){
                                  pw = val!;})),
                          ],
                        ),
                        const SizedBox(height: 15),
                        const Text('담당 선생님',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () => _showDialog(
                                CupertinoPicker.builder(
                                  itemExtent: 30,
                                  childCount: Allteachers.length,
                                  onSelectedItemChanged: (i){
                                    setState(() {
                                      TMPTeacher = Allteachers[i];
                                    });
                                  },
                                  itemBuilder: (context, index){
                                    return Text('${Allteachers[index].name} 선생님', style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20,));
                                  },
                                )
                            ),
                            child: Text('${TMPTeacher.name} 선생님',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,))),
                        const SizedBox(height: 8),
                        const Text('첫 수업 날짜',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () async {
                              tmp = (await showDatePicker(context: context,
                                  firstDate: DateTime(2024, 1, 1),
                                  lastDate: DateTime(2050, 12, 31)))!;
                              setState(() {
                                startTime = DateTime(tmp.year, tmp.month, tmp.day, startTime.hour, startTime.minute);
                              });
                            },
                            child: Text( DateFormat('yyyy년 MM월 dd일').format(startTime),
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,))),
                        const SizedBox(height: 10,),
                        const Text('수업 시간 선택',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () async {
                              TMP = (await showTimePicker(context: context, initialTime: TMP))!;
                              setState(() {
                                startTime = DateTime(startTime.year, startTime.month, startTime.day, TMP.hour, TMP.minute);
                              });
                              // UI 업데이트를 위한 startTime 설정은 setState 안에서 처리
                              setState(() {
                                startTime = DateTime(tmp.year, tmp.month, tmp.day, startTime.hour, startTime.minute);
                              });

                              // TMPTeacher.workTime 접근 및 근무 시간 확인 로직
                              int dayIndex = startTime.weekday - 1; // weekday는 1(월)~7(일), 배열 인덱스는 0부터 시작
                              if (dayIndex != 6) {
                                // 일요일인 경우 제외하기 (어차피 모든 선생님의 일요일 근무는 존재하지 않음)
                                DateTime workStartTime = TMPTeacher.workTime[dayIndex * 2]; // 근무 시작 시간
                                DateTime workEndTime = TMPTeacher.workTime[dayIndex * 2 + 1]; // 근무 종료 시간
                                print('요일 index - 1 값: $dayIndex ');
                                print('근무 시작 시간: $workStartTime');
                                print('근무 끝나는 시간: $workEndTime');
                                print('설정된 시간 : $startTime');
                                // 근무 시간에 부합하지 않는 경우 안내 문구 표시
                                if (startTime.hour < workStartTime.hour ||
                                    (startTime.hour == workStartTime.hour && startTime.minute < workStartTime.minute) ||
                                    startTime.hour > workEndTime.hour ||
                                    (startTime.hour == workEndTime.hour && startTime.minute >= workEndTime.minute))
                                {
                                  print('부합하는 조건문 입성');
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        title: Text(
                                          '주의',
                                          style: style.copyWith(color: Colors.red, fontWeight: FontWeight.w500),
                                        ),
                                        content: Text(
                                          '설정한 시간대는 선생님의 근무 시간이 아닙니다.\n확인 후 수정 바랍니다.',
                                          style: style.copyWith(fontSize: 16),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                            },
                                            child: Text(
                                              '확인',
                                              style: style.copyWith(color: PRIMARY_COLOR),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                }
                              }
                              else {
                                // 일요일인 경우에도 안내창을 띄움
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: Text(
                                        '주의',
                                        style: style.copyWith(color: Colors.red, fontWeight: FontWeight.w500),
                                      ),
                                      content: Text(
                                        '설정한 시간대는 선생님의 근무 시간이 아닙니다.\n확인 후 수정 바랍니다.',
                                        style: style.copyWith(fontSize: 16),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                          child: Text(
                                            '확인',
                                            style: style.copyWith(color: PRIMARY_COLOR),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              }
                                                        },
                            child: Text('${(startTime.hour).toString().padLeft(2,'0')} : ${(startTime.minute).toString().padLeft(2,'0')}',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,))),
                        const Expanded(child: SizedBox()),
                        SizedBox(width: double.infinity,
                            child: ElevatedButton(onPressed: () => onSavePressed(context),
                                style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_COLOR),
                                child: const Text('저장하기', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, color: Colors.white)))),
                      ],
                    ))
            )
        )
    );
  }
  String? contentValidater(String? val) {
    if(val == null || val.isEmpty){
      return '내용을 입력해주세요!';
    }
    return null;
  }
  void onSavePressed(BuildContext context) async {
    if (isSaving) return; // 중복 호출 방지
    setState(() {
      isSaving = true;
    });
    showDialog(
      context: context,
      barrierDismissible: false, // 다른 곳 클릭 불가
      builder: (BuildContext context) {
        return Center(
          child: CircularProgressIndicator(),
        );
      },
    );
    final DateTime tmp = DateTime.now();

    if (formKey.currentState!.validate()) {
      try {
        formKey.currentState!.save();

        final String studentID =  'STU_${DateFormat('yyMMdd').format(startTime)}${DateFormat('ss').format(DateTime.now())}';
        print('$studentID => 새로운 학생의 ID');

        List<String> NewClass = await generateClassSchedule(studentID, startTime);

        final NewStudent = StudentClass(id: studentID, teacherID: TMPTeacher.id, role : 'student', name: Name!,
          classDay: startTime, password: pw!, teacherName: TMPTeacher.name, classList: NewClass,
        );
        // 파이어베이스에 새로운 학생 등록
        await FirebaseFirestore.instance.collection('User').doc(studentID).set(NewStudent.toJson());

        // teacher 컬렉션에 학생 정보 추가
        DocumentReference<Map<String, dynamic>> documentRef =
        FirebaseFirestore.instance.collection('User').doc(TMPTeacher.id);
        await documentRef.update({'studentList': FieldValue.arrayUnion([studentID])});
        // 수업 정보도 추가해줍니다
        await documentRef.update({'classList': FieldValue.arrayUnion(NewClass)});

        // 새로운 학생 ID를 기존 학생 리스트에 추가하고, 그 값을 저장한 변수로 데이터베이스에 업데이트
        await AllUsers();
        await Alllesson();

      } catch (e) {
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text(
                  '오류',
                  style: style.copyWith(
                    color: PRIMARY_COLOR,
                    fontSize: 17,
                  ),
                  textAlign: TextAlign.center,
                ),
                content: Text(
                  '학생 정보를 저장하는 과정에서 오류가 발생했습니다',
                  style: style.copyWith(fontSize: 15),
                ),
              );
            });
      } finally {
        setState(() {
          isSaving = false;
          Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
        });
      }
    }
    Navigator.of(context).pop();
  }
  Future<List<String>> generateClassSchedule(String studentID, DateTime startTime) async {
    // 휴일 정보를 가져옵니다.
    final holidaySnapshot = await FirebaseFirestore.instance
        .collection('Class')
        .doc(DateTime.now().year.toString())
        .get();
    final holidaySnapshot2 = await FirebaseFirestore.instance
        .collection('Class')
        .doc((DateTime.now().year+1).toString())
        .get();

    List<DateTime> holidays = (holidaySnapshot.data()!['Holiday'] as List)
        .map((timestamp) => (timestamp as Timestamp).toDate())
        .toList();
    List<DateTime> additionalHolidays = (holidaySnapshot2.data()!['Holiday'] as List)
        .map((timestamp) => (timestamp as Timestamp).toDate())
        .toList();

    // 기존 holidays 리스트에 추가
    holidays.addAll(additionalHolidays);

    // 휴일 기간을 구합니다. 각 휴일 날짜부터 7일 동안을 범위로 설정.
    List<DateTime> holidayPeriods = [];
    for (var holiday in holidays) {
      DateTime startOfHoliday = holiday;
      DateTime endOfHoliday = holiday.add(const Duration(days: 6));
      for (var day = startOfHoliday;
      day.isBefore(endOfHoliday) || day.isAtSameMomentAs(endOfHoliday);
      day = day.add(const Duration(days: 1))) {
        holidayPeriods.add(day);
      }
    }

    // 중복을 제거하기 위해 정렬 후 `Set`으로 변환
    holidayPeriods = holidayPeriods.toSet().toList()
      ..sort((a, b) => a.compareTo(b));

    // 기존 12개 생성 코드

    // while (lessonCount < 12) {
    //   // 학기 정보를 가져오기 위해 Firebase에 접근
    //   String year = classDate.year.toString();
    //   String month = classDate.month.toString();
    //   DocumentSnapshot<Map<String, dynamic>> semesterDoc = await FirebaseFirestore.instance
    //       .collection('Class')
    //       .doc(year)
    //       .get();
    //
    //   // 학기 정보 가져오기
    //   List<dynamic> semesterList = semesterDoc.data()?[month] ?? [];
    //   if (semesterList.length < 2) {
    //     throw Exception('Invalid semester data for $year-$month');
    //   }
    //
    //   DateTime semesterStart = (semesterList[0] as Timestamp).toDate();
    //   DateTime semesterEnd = (semesterList[1] as Timestamp).toDate();
    //
    //   // 학기 코드 결정
    //   String semesterCode;
    //   if (classDate.isBefore(semesterStart)) {
    //     // 이전 학기 코드
    //     DateTime prevMonth = DateTime(classDate.year, classDate.month - 1, 1);
    //     semesterCode = '${DateFormat('yyMM').format(prevMonth)}';
    //   } else if (classDate.isAfter(semesterEnd)) {
    //     // 다음 학기 코드
    //     DateTime nextMonth = DateTime(classDate.year, classDate.month + 1, 1);
    //     semesterCode = '${DateFormat('yyMM').format(nextMonth)}';
    //   } else {
    //     // 현재 학기 코드
    //     semesterCode = '${DateFormat('yyMM').format(classDate)}';
    //   }
    //
    //   // 현재 날짜가 휴일 기간에 포함되지 않으면 수업 추가.
    //   if (!holidayPeriods.any((holiday) =>
    //   holiday.year == classDate.year &&
    //       holiday.month == classDate.month &&
    //       holiday.day == classDate.day)) {
    //
    //     // 해당 학기의 기존 수업 수 확인
    //     int lessonIndex = classSchedule.where((id) => id.startsWith(studentID + '_' + semesterCode)).length + 1;
    //
    //     // lessonID 생성
    //     lessonID = '${studentID}_${semesterCode}${lessonIndex.toString().padLeft(2, '0')}';
    //     newlesson = Lesson(id: lessonID, time: classDate, isValid: true);
    //
    //     // Firestore에 저장
    //     await FirebaseFirestore.instance.collection('Class').doc(lessonID).set(newlesson.toJson());
    //
    //     // 수업 스케줄에 추가
    //     classSchedule.add(newlesson.id);
    //     lessonCount++;
    //   }
    //   // 다음 수업 날짜로 설정 (일주일 후)
    //   classDate = classDate.add(const Duration(days: 7));
    // }


    DateTime classDate = startTime;
    List<String> classSchedule = [];
    Lesson newlesson = Lesson(id: '', time: classDate, isValid: true);
    String lessonID = '';

    // 새롭게 바꾸는 코드는 현재 학기 포함 4개월간의 수업을 생성함
    // 4개월 후의 학기가 끝나는 날 계산
    DateTime fourMonthsLater = DateTime(startTime.year, startTime.month + 3, startTime.day);
    String fourMonthsYear = fourMonthsLater.year.toString();
    String fourMonthsMonth = fourMonthsLater.month.toString();
    DocumentSnapshot<Map<String, dynamic>> semesterDoc = await FirebaseFirestore.instance
        .collection('Class')
        .doc(fourMonthsYear)
        .get();
    List<dynamic> semesterList = semesterDoc.data()?[fourMonthsMonth] ?? [];
    if (semesterList.length < 2) {
      throw Exception('Invalid semester data for $fourMonthsYear-$fourMonthsMonth');
    }
    DateTime endOfFourMonthsSemester = (semesterList[1] as Timestamp).toDate();

    // 학기 종료일까지 수업 생성
    while (classDate.isBefore(endOfFourMonthsSemester)) {
      // 생성하려는 날짜의 학기 정보 불러오기
      String year = classDate.year.toString();
      String month = classDate.month.toString();
      DocumentSnapshot<Map<String, dynamic>> semesterDoc = await FirebaseFirestore.instance
          .collection('Class')
          .doc(year)
          .get();
      List<dynamic> semesterList = semesterDoc.data()?[month] ?? [];
      if (semesterList.length < 2) {
        throw Exception('Invalid semester data for $year-$month');
      }
      DateTime semesterStart = (semesterList[0] as Timestamp).toDate();
      DateTime semesterEnd = (semesterList[1] as Timestamp).toDate();

      String semesterCode;
      if (classDate.isBefore(semesterStart)) {
        DateTime prevMonth = DateTime(classDate.year, classDate.month - 1, 1);
        semesterCode = DateFormat('yyMM').format(prevMonth);
      } else if (classDate.isAfter(semesterEnd)) {
        DateTime nextMonth = DateTime(classDate.year, classDate.month + 1, 1);
        semesterCode = DateFormat('yyMM').format(nextMonth);
      } else {
        semesterCode = DateFormat('yyMM').format(classDate);
      }

      // 현재 날짜가 휴일이 아니면 수업 생성
      if (!holidayPeriods.any((holiday) =>
      holiday.year == classDate.year &&
          holiday.month == classDate.month &&
          holiday.day == classDate.day)) {
        int lessonIndex = classSchedule.where((id) => id.startsWith('${studentID}_$semesterCode')).length + 1;
        lessonID = '${studentID}_$semesterCode${lessonIndex.toString().padLeft(2, '0')}';
        newlesson = Lesson(id: lessonID, time: classDate, isValid: true);

        await FirebaseFirestore.instance.collection('Class').doc(lessonID).set(newlesson.toJson());

        classSchedule.add(newlesson.id);
      }

      // 다음 수업 날짜로 설정 (일주일 후)
      classDate = classDate.add(const Duration(days: 7));
    }

    return classSchedule;
  }


  void _showDialog(Widget child){
    showCupertinoModalPopup(context: context, builder: (BuildContext context) =>
        Container(
            color: CupertinoColors.systemBackground.resolveFrom(context),
            height: MediaQuery.of(context).size.height / 3,
            padding: const EdgeInsets.only(top: 4),
            margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SafeArea(top: false,child: child,)
        )
    );
  }
}