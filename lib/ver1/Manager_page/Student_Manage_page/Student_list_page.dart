import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Sheets/Student_card.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Student_Manage_page/Student_Manage_page.dart';


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

class Student_list_page extends StatefulWidget {
  const Student_list_page({super.key});

  @override
  State<Student_list_page> createState() => _Student_list_page();
}

class _Student_list_page extends State<Student_list_page> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: BaseAppBar(
            title: "\u{1F49A} FORESTRING \u{1F49A}",
            center: true,
            appBar: AppBar()),
        drawer: const ManagerDrawer(),
        floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.white,
            shape: const CircleBorder(),
            child: const Icon(Icons.arrow_back_rounded, color: PRIMARY_COLOR),
            onPressed: () {
              Navigator.of(context).push(
                _createRoute(const Student_Manage_page()),
              );
            }),
        body: Container(
            padding: const EdgeInsets.only(bottom: 10, left: 8, right: 8, top: 10),
            child: ListView.builder(
                itemCount: AllStudentList.length,
                itemBuilder: (context, index) {
                  return Column(
                    children: [
                      InkWell(
                        onTap: (){
                          showDialog(context: context, builder: (context) => AlertDialog(
                            title: const Text('학생 정보를 삭제하시겠습니까?', style: TextStyle(fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 15, color: Colors.black)),
                            actions: [TextButton(onPressed: (){Navigator.pop(context);}, child: const Text('아니오', style: TextStyle(color: Colors.black))),
                              TextButton(onPressed: () async {

                                try {
                                  //학생 정보 삭제 메소드
                                  //student collection에서 삭제
                                  FirebaseFirestore.instance.collection('student').doc(AllStudentList[index].id).delete();
                                  //teacher doc array에서 삭제
                                  DocumentReference<Map<String, dynamic>> DocumentRef =
                                  FirebaseFirestore.instance.collection('teacher').doc(AllStudentList[index].teacherID);
                                  DocumentSnapshot<Map<String, dynamic>> docSnap = await DocumentRef.get();
                                  var tmp = await docSnap.data()!['students'];
                                  tmp.remove(AllStudentList[index].id);
                                  FirebaseFirestore.instance.collection('teacher').doc(AllStudentList[index].teacherID).update({'students' : tmp});
                                  //class collection에서 삭제
                                  FirebaseFirestore.instance.collection('Class').doc(AllStudentList[index].id).delete();
                                  Navigator.pop(context);
                                  await getallstudents();
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
                                          content: Text('학생 정보를 삭제하는 과정에서 오류가 발생했습니다.\n페이지를 새로고침 후 다시 시도해주세요.',
                                              style: style.copyWith(fontSize: 15)),
                                        );
                                      });
                                }

                                },
                                  child: const Text('예', style: TextStyle(color: Colors.red))),

                            ],
                          ));
                        },
                        child: StudentCard(
                            Day: DateFormat('EEE').format(AllStudentList[index].startTime),
                            startTime: AllStudentList[index].startTime,
                            id: AllStudentList[index].name,
                            teacher: TeacherNameMap[AllStudentList[index].teacherID]!, endTime: AllStudentList[index].startTime.add(const Duration(minutes: 30)),),
                      ),
                      const SizedBox(height: 5)
                    ],
                  );
                })));
  }
}
