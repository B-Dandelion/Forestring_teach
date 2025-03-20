import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Data/constant.dart';


class new_schedule_sheet extends StatefulWidget {
  const new_schedule_sheet({super.key});

  @override
  State<new_schedule_sheet> createState() => _new_schedule_sheet();
}

class _new_schedule_sheet extends State<new_schedule_sheet>{
  final GlobalKey<FormState> formKey = GlobalKey();
  DateTime tmp = DateTime.now();
  DateTime savetmp = DateTime.now();
  TimeOfDay TMP = const TimeOfDay(hour: 10, minute: 00);
  TimeOfDay saveTMP = const TimeOfDay(hour: 10, minute: 00);
  String Student = AllStudentList[0].id;
  String StudentName = AllStudentList[0].name;

  @override
  Widget build(BuildContext context){
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Form(
        key: formKey,
        child : SafeArea(
            child: Container(
                height: MediaQuery.of(context).size.height / 2.5 + bottomInset,
                color: Colors.white,
                child: Padding( padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomInset+8),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        const Text('수강생 선택하기', style: TextStyle(
                            color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17)),
                        TextButton(
                            onPressed: () => _showDialog(
                                CupertinoPicker.builder(
                                  itemExtent: 30,
                                  childCount: AllStudentList.length,
                                  onSelectedItemChanged: (i){
                                    setState(() {
                                      Student =AllStudentList[i].id;
                                      StudentName = AllStudentList[i].name;
                                    });
                                  },
                                  itemBuilder: (context, index){
                                    return Text('${AllStudentList[index].name} 학생', style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 20,));
                                  },
                                )
                            ),
                            child: Text('$StudentName 학생',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,))),
                        const SizedBox(height: 10),
                        const Text('보강 날짜 선택하기', style: TextStyle(
                            color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17)),
                        TextButton(onPressed: () async {
                          tmp = (await showDatePicker(context: context, firstDate: DateTime(2024,1,1), lastDate: DateTime(2050,12,31)))!;
                          setState(() {
                            savetmp = tmp;
                          });
                        },
                            child: Text('${savetmp.year}.${savetmp.month}.${savetmp.day}',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25))),
                        const Text('보강 시간 선택',
                            style: TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
                        TextButton(
                            onPressed: () async {
                              TMP = (await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 00)))!;
                              setState(() {
                                saveTMP = TMP;
                              });
                            },
                            child: Text('${(saveTMP.hour).toString().padLeft(2,'0')} : ${(saveTMP.minute).toString().padLeft(2,'0')}',
                                style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,))),
                        const Expanded(child: SizedBox()),
                        SizedBox(width: double.infinity,
                            child: ElevatedButton(onPressed: () => onSavePressed(context),
                                style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_COLOR),
                                child: const Text('추가하기', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, color: Colors.white)))),
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
  void onSavePressed(BuildContext context) async{
    if(formKey.currentState!.validate()){
      formKey.currentState!.save();
      final NEWSchedule = DateTime(savetmp.year, savetmp.month, savetmp.day, saveTMP.hour, saveTMP.minute,);
      //파이어 베이스에 새로운 스케줄 등록
      var ref = await FirebaseFirestore.instance.collection('Class').doc(Student).get();
      var TMP = ref.data()!['rebooked'];
      TMP.add(NEWSchedule);
      await FirebaseFirestore.instance.collection('Class').doc(Student).update({'rebooked': TMP});
    }
    await getallschedules();
    Navigator.of(context).pop();
  }
}
