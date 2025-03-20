import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/Data/constant.dart';
import 'package:forestring_teacher_2/Manager_page/Teacher_Manage_page/Teacher_list_page.dart';

Route _createRoute(Page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => Page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(0.0, 1.0);
      const end = Offset.zero;
      final tween = Tween(begin: begin, end: end);
      final offsetAnimation = animation.drive(tween);
      return child;
    },
  );
}
class teacher_modify_page extends StatefulWidget {
  const teacher_modify_page({super.key});

  @override
  State<teacher_modify_page> createState() => _teacher_modify_page();
}

class _teacher_modify_page extends State<teacher_modify_page>{
  String name = '';
  String password = '';
  TimeOfDay tmp = const TimeOfDay(hour: 10, minute: 30);
  DateTime now = DateTime.now();
  int M1 = 0;
  int M2 = 0;
  int M3 = 0;
  int M4 = 0;

  int Tu1 = 0;
  int Tu2 = 0;
  int Tu3 = 0;
  int Tu4 = 0;

  int W1 =0;
  int W2 = 0;
  int W3 = 0;
  int W4 = 0;

  int Th1 = 0;
  int Th2 = 0;
  int Th3 = 0;
  int Th4 = 0;

  int F1 = 0;
  int F2 = 0;
  int F3 = 0;
  int F4 = 0;

  int S1 = 0;
  int S2 = 0;
  int S3 = 0;
  int S4 = 0;

  final GlobalKey<FormState> formKey = GlobalKey();
  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: BaseAppBar(title: "\u{1F49A} FORESTRING \u{1F49A}", center: true, appBar: AppBar()),
      drawer: const ManagerDrawer(),
      floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.white,
          shape: const CircleBorder(),
          child: const Icon(Icons.arrow_back_rounded, color: PRIMARY_COLOR),
          onPressed: () {
            Navigator.of(context).push(
              _createRoute(const Teacher_list_page()),
            );
          }),
      body: SingleChildScrollView(
        child: Form(key: formKey,
          child: Container(
            padding: const EdgeInsets.only(bottom: 10, left: 15, right: 15, top: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${TeacherNameMap[teacherid]} 선생님', style: const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 30)),
                const SizedBox(height: 15),
                const Text('근무 시간', style:
                TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 23,)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('월요일 : ', style:
                    TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),
                    TextButton(onPressed: ()async{
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        M1 = tmp.hour;
                        M2 = tmp.minute;
                      });
                    },
                      child:Text('${M1.toString().padLeft(2,'0')} : ${M2.toString().padLeft(2,'0')}', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                    const Text(' ~ ', style:
                    TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25),),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        M3 = tmp.hour;
                        M4 = tmp.minute;
                      });
                    },
                      child:Text('${M3.toString().padLeft(2,'0')} : ${M4.toString().padLeft(2,'0')} ', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                  ],
                ),
                Row(
                  children: [
                    const Text('화요일 : ', style:
                    TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        Tu1 = tmp.hour;
                        Tu2 = tmp.minute;
                      });
                    },
                      child:Text('${Tu1.toString().padLeft(2,'0')} : ${Tu2.toString().padLeft(2,'0')}', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                    const Text(' ~ ', style:
                    TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25),),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        Tu3 = tmp.hour;
                        Tu4 = tmp.minute;
                      });
                    },
                      child:Text('${Tu3.toString().padLeft(2,'0')} : ${Tu4.toString().padLeft(2,'0')} ', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                  ],
                ),
                Row(
                  children: [
                    const Text('수요일 : ', style:
                    TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        W1 = tmp.hour;
                        W2 = tmp.minute;
                      });
                    },
                      child:Text('${W1.toString().padLeft(2,'0')} : ${W2.toString().padLeft(2,'0')}', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                    const Text(' ~ ', style:
                    TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25),),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        W3 = tmp.hour;
                        W4 = tmp.minute;
                      });
                    },
                      child:Text('${W3.toString().padLeft(2,'0')} : ${W4.toString().padLeft(2,'0')} ', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                  ],
                ),
                Row(
                  children: [
                    const Text('목요일 : ', style:
                    TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        Th1 = tmp.hour;
                        Th2 = tmp.minute;
                      });
                    },
                      child:Text('${Th1.toString().padLeft(2,'0')} : ${Th2.toString().padLeft(2,'0')}', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                    const Text(' ~ ', style:
                    TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25),),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        Th3 = tmp.hour;
                        Th4 = tmp.minute;
                      });
                    },
                      child:Text('${Th3.toString().padLeft(2,'0')} : ${Th4.toString().padLeft(2,'0')} ', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                  ],
                ),
                Row(
                  children: [
                    const Text('금요일 : ', style:
                    TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        F1 = tmp.hour;
                        F2 = tmp.minute;
                      });
                    },
                      child:Text('${F1.toString().padLeft(2,'0')} : ${F2.toString().padLeft(2,'0')}', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                    const Text(' ~ ', style:
                    TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25),),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        F3 = tmp.hour;
                        F4 = tmp.minute;
                      });
                    },
                      child:Text('${F3.toString().padLeft(2,'0')} : ${F4.toString().padLeft(2,'0')} ', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                  ],
                ),
                Row(
                  children: [
                    const Text('토요일 : ', style:
                    TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        S1 = tmp.hour;
                        S2 = tmp.minute;
                      });
                    },
                      child:Text('${S1.toString().padLeft(2,'0')} : ${S2.toString().padLeft(2,'0')}', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                    const Text(' ~ ', style:
                    TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25),),
                    TextButton(onPressed: () async {
                      tmp = (await showTimePicker(context: context, initialTime: tmp))!;
                      setState(() {
                        S3 = tmp.hour;
                        S4 = tmp.minute;
                      });
                    },
                      child:Text('${S3.toString().padLeft(2,'0')} : ${S4.toString().padLeft(2,'0')} ', style:
                      const TextStyle(color: PRIMARY_COLOR, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 25,)),),
                  ],
                ),
                SizedBox(width: double.infinity,
                    child: ElevatedButton(onPressed: () => onSavePressed(context),
                        style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_COLOR),
                        child: const Text('변경 내용 저장하기', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, color: Colors.white)))),
              ],
            ),
          ),

        ),
      ),
    );
  }
  void onSavePressed(BuildContext context) async{
    if(formKey.currentState!.validate()){
      //선생님 근무 시간 정보 수정하기
      formKey.currentState!.save();
      await FirebaseFirestore.instance.collection('teacher').doc(teacherid).update({
        'Mon':[DateTime(2024, 1, 1, M1, M2), DateTime(2024, 1, 1, M3, M4)],
        'Tue': [DateTime(2024, 1, 2, Tu1, Tu2), DateTime(2024, 1, 2, Tu3, Tu4)],
        'Wed': [DateTime(2024, 1, 3, W1, W2), DateTime(2024, 1, 3, W3, W4)],
        'Thu': [DateTime(2024, 1, 4, Th1, Th2), DateTime(2024, 1, 4, Th3, Th4)],
        'Fri': [DateTime(2024, 1, 5, F1, F2), DateTime(2024, 1, 5, F3, F4)],
        'Sat': [DateTime(2024, 1, 6, S1, S2), DateTime(2024, 1, 6, S3, S4)]});
    }
    Navigator.of(context).push(
        _createRoute(const Teacher_list_page())
    );
  }

  String? contentValidater(String? val) {
    if(val == null || val.isEmpty){
      return '내용을 입력해주세요!';
    }
    return null;
  }

}