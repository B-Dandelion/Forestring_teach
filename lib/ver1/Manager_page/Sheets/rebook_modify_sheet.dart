import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Schedule_Manage_page/Schedule_modify_page.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';


class rebook_modify_sheet extends StatefulWidget {
  const rebook_modify_sheet({super.key});

  @override
  State<rebook_modify_sheet> createState() => _rebook_modify_sheet();
}

class _rebook_modify_sheet extends State<rebook_modify_sheet>{
  String TeacherName = selectedTeacher;
  DateTime startTime = selectedTime;

  DateTime tmp = DateTime(2024,10,10,10,00);
  TimeOfDay TMP = TimeOfDay.fromDateTime(DateTime(2024,10,10,10,00));

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
                child: Padding( padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomInset + 8),
                    child: Column(
                      children: [
                        const SizedBox(height: 5,),
                        const Text('수정하려는 수업 학생 이름',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17)),
                        const SizedBox(height: 10,),
                        Text(selectedName,
                            style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30)),
                        const SizedBox(height: 10,),
                        const Text('담당 수업 선생님',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17)),
                        const SizedBox(height: 10,),
                        Text('$selectedTeacher 선생님',
                            style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30)),
                        const SizedBox(height: 10,),
                        const Text('변경할 수업 날짜 선택',
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
                              TMP = (await showTimePicker(context: context, initialTime: TimeOfDay(hour: startTime.hour, minute: startTime.minute)))!;
                              setState(() {
                                startTime = DateTime(startTime.year, startTime.month, startTime.day, TMP.hour, TMP.minute);
                              });
                            },
                            child: Text('${(startTime.hour).toString().padLeft(2,'0')} : ${(startTime.minute).toString().padLeft(2,'0')}',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30,))),
                        const Expanded(child: SizedBox()),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton(onPressed: () => onDeletePressed(context),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                child: const Text('취소하기', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, color: Colors.white))),
                            ElevatedButton(onPressed: () => onSavePressed(context),
                                style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_COLOR),
                                child: const Text('저장하기', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, color: Colors.white))),
                          ],
                        ),
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
  void onSavePressed(BuildContext context) async{
    final DateTime tmp = DateTime.now();
    if(formKey.currentState!.validate()){
      try{
        var doc = await FirebaseFirestore.instance.collection('Class').doc(selectedID).get();
        var rebooklist = doc.data()!['rebooked'];

        // 특정 날짜를 찾고 값 변경
        int index = rebooklist.indexWhere((item) => (item as Timestamp).toDate() == selectedTime);
        print(rebooklist[index]);
        rebooklist[index] = startTime;
        print(rebooklist[index]);

        // var TMP = [];
        // for(var sche in rebooklist){
        //   TMP.add(DateTime(sche.toDate().year, sche.toDate().month,
        //       sche.toDate().day, sche.toDate().hour, sche.toDate().minute, 0));
        // }
        // TMP.remove(DateTime(selectedTime.year, selectedTime.month, selectedTime.day,
        //     selectedTime.hour, selectedTime.minute, 0));
        // // 기존 수업 배열에 있던 것을 삭제함.
        //
        // //파이어 베이스에 수정된 수업 정보를 rebook 리스트에 추가하여 등록하기
        // tmp = doc.data()!['rebooked'];
        // tmp.add(startTime);
        await FirebaseFirestore.instance.collection('Class').doc(selectedID).update({'rebooked' : rebooklist});
        await getallschedules();
      }catch(e) {
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Container(
                    child: Text(
                      '오류',
                      style: style.copyWith(
                        color: PRIMARY_COLOR,
                        fontSize: 17,
                      ),
                      textAlign: TextAlign.center,
                    )),
                content: Text('스케줄 정보를 수정하는 과정에서 오류가 발생했습니다',
                    style: style.copyWith(fontSize: 15)),
              );
            });
      }
    }
    Navigator.of(context).pop();
  }
  void onDeletePressed(BuildContext context) async {
    if(formKey.currentState!.validate()){
      try{
        var doc = await FirebaseFirestore.instance.collection('Class').doc(selectedID).get();
        var tmp = doc.data()!['rebooked'];
        var TMP = [];
        for(var sche in tmp){
          TMP.add(DateTime(sche.toDate().year, sche.toDate().month,
              sche.toDate().day, sche.toDate().hour, sche.toDate().minute, 0));
        }
        TMP.remove(DateTime(selectedTime.year, selectedTime.month, selectedTime.day,
            selectedTime.hour, selectedTime.minute, 0));
        await FirebaseFirestore.instance.collection('Class').doc(selectedID).update({'rebooked': TMP});
        // 기존 수업 배열에 있던 것을 삭제함.

        //canceled에 취소된 수업 추가
        doc = await FirebaseFirestore.instance.collection('Class').doc(selectedID).get();
        tmp = doc.data()!['canceled'];
        tmp.add(selectedTime);
        await FirebaseFirestore.instance.collection('Class').doc(selectedID).update({'canceled': tmp});
      } catch (e) {
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Container(
                    child: Text(
                      '오류',
                      style: style.copyWith(
                        color: PRIMARY_COLOR,
                        fontSize: 17,
                      ),
                      textAlign: TextAlign.center,
                    )),
                content: Text('스케줄 정보를 수정하는 과정에서 오류가 발생했습니다',
                    style: style.copyWith(fontSize: 15)),
              );
            });
      }
    }
    Navigator.of(context).pop();
  }

}