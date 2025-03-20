import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/Data/constant.dart';
import 'package:forestring_teacher_2/Data/student_model.dart';
import 'package:forestring_teacher_2/Manager_page/Sheets/custom_text_field.dart';


class new_student_sheet extends StatefulWidget {
  const new_student_sheet({super.key});

  @override
  State<new_student_sheet> createState() => _new_student_sheet();
}

class _new_student_sheet extends State<new_student_sheet>{
  String Teacher = AllTeacherList[0].id;
  String TeacherName = AllTeacherList[0].name;
  DateTime startTime = DateTime(2024,10,1,10,00);

  DateTime tmp = DateTime(2024,10,10,10,00);
  TimeOfDay TMP = TimeOfDay.fromDateTime(DateTime(2024,10,10,10,00));

  String? Name = '';
  String? pw = '';
  String? ID = '';
  final GlobalKey<FormState> formKey = GlobalKey();

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
                                  childCount: AllTeacherList.length,
                                  onSelectedItemChanged: (i){
                                    setState(() {
                                      Teacher = AllTeacherList[i].id;
                                      TeacherName = AllTeacherList[i].name;
                                    });
                                  },
                                  itemBuilder: (context, index){
                                    return Text('${AllTeacherList[index].name} 선생님', style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20,));
                                  },
                                )
                            ),
                            child: Text('$TeacherName 선생님',
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
    final DateTime tmp = DateTime.now();

    if (formKey.currentState!.validate()) {
      try {
        formKey.currentState!.save();
        final String studentID = DateFormat('yyyyMMdd').format(startTime) + '$pw';
        print('$studentID => 새로운 학생의 ID');
        final NewStudent = StudentModel(id: studentID, name: Name!, teacherID: Teacher, startTime: startTime);
        // 파이어베이스에 새로운 학생 등록
        await FirebaseFirestore.instance.collection('student').doc(studentID).set(NewStudent.toJson());


        // 휴일 정보 가져오기
        final holidaySnapshot = await FirebaseFirestore.instance.collection('Class').doc(DateTime.now().year.toString()).get();
        List<DateTime> holidays = (holidaySnapshot.data()!['Holiday'] as List)
            .map((timestamp) => (timestamp as Timestamp).toDate())
            .toList();
        final holidaySnapshot2 = await FirebaseFirestore.instance.collection('Class').doc((DateTime.now().year+1).toString()).get();
        List<DateTime> Holidays = (holidaySnapshot2.data()!['Holiday'] as List)
            .map((timestamp) => (timestamp as Timestamp).toDate())
            .toList();
        holidays.addAll(Holidays);
        print(holidays);

        // 3개월 분량의 수업 날짜 생성 (휴일 제외)
        var classList = [];
        DateTime classDate = startTime;
        for (int i = 0; i < 12; i++) {
          // 해당 날짜가 휴일 기간에 포함되는지 확인
          bool isHoliday = holidays.any((holiday) {
            DateTime holidayStart = holiday;
            DateTime holidayEnd = holiday.add(const Duration(days: 7));
            return classDate.isAfter(holidayStart) && classDate.isBefore(holidayEnd);
          });
          // 휴일이 아니면 수업 추가
          if (!isHoliday) {
            classList.add(classDate);
          } else {
            print('휴일로 인해 $classDate 수업이 건너뛰어집니다.');
            i -= 1;
          }
          classDate = classDate.add(const Duration(days: 7)); // 7일씩 증가
        }

        // Class 컬렉션에 수업 정보 추가
        await FirebaseFirestore.instance.collection('Class').doc(studentID).set({
          'canceled': [],
          'class': classList,
          'rebooked': [],
          'deleted' : []
        });

        // teacher 컬렉션에 학생 정보 추가
        DocumentReference<Map<String, dynamic>> documentRef =
        FirebaseFirestore.instance.collection('teacher').doc(Teacher);
        DocumentSnapshot<Map<String, dynamic>> docSnap = await documentRef.get();
        var tmp = docSnap.data()!['students'];
        tmp.add(studentID);
        await FirebaseFirestore.instance.collection('teacher').doc(Teacher).update({'students': tmp});

        // 새로운 학생 ID를 기존 학생 리스트에 추가하고, 그 값을 저장한 변수로 데이터베이스에 업데이트
        await getallstudents();
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
      }
    }
    Navigator.of(context).pop();
  }

  // void onSavePressed(BuildContext context) async{
  //   final DateTime tmp = DateTime.now();
  //   if(formKey.currentState!.validate()){
  //     // student 컬렉션에 학생 정보 추가 (로그인 가능해짐)
  //     try{
  //       formKey.currentState!.save();
  //       final String StudentID = '${DateFormat('yyyyMMdd').format(startTime)}'+'${pw}';
  //       print('${StudentID} => 새로운 학생의 ID');
  //       final NewStudent = StudentModel(id: StudentID, name: Name!, teacherID: Teacher, startTime: startTime);
  //       //파이어 베이스에 새로운 학생 등록
  //       await FirebaseFirestore.instance.collection('student').doc(StudentID).set(NewStudent.toJson());
  //       //Class에 형식 맞춰서 추가하기
  //       await FirebaseFirestore.instance.collection('Class').doc(StudentID).set({
  //         'canceled' : [],
  //         'class' : [],
  //         'rebooked' : []
  //       });
  //       //teacher 컬렉션에 학생 정보 추가
  //       DocumentReference<Map<String, dynamic>> DocumentRef =
  //       FirebaseFirestore.instance.collection('teacher').doc(Teacher);
  //       DocumentSnapshot<Map<String, dynamic>> docSnap = await DocumentRef.get();
  //       var tmp = docSnap.data()!['students'];
  //       //학생 리스트를 잠시 저장해줄 변수 설정
  //       tmp.add(StudentID);
  //       await FirebaseFirestore.instance.collection('teacher').doc(Teacher).update({'students' : tmp});
  //       // 새로운 학생 ID를 기존 학생 리스트에 추가하고, 그 값을 저장한 변수로 데이터베이스에 업데이트
  //       await getallstudents();
  //     }catch(e) {
  //       showDialog(
  //           context: context,
  //           builder: (BuildContext context) {
  //             return AlertDialog(
  //               title: Container(
  //                   child: Text(
  //                     '오류',
  //                     style: style.copyWith(
  //                       color: PRIMARY_COLOR,
  //                       fontSize: 17,
  //                     ),
  //                     textAlign: TextAlign.center,
  //                   )),
  //               content: Text('학생 정보를 저장하는 과정에서 오류가 발생했습니다',
  //                   style: style.copyWith(fontSize: 15)),
  //             );
  //           });
  //     }
  //   }
  //   Navigator.of(context).pop();
  // }
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