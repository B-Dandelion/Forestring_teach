import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:forestring_teacher_2/ver1/New_Main_page/New_Home_page.dart';
import 'package:forestring_teacher_2/ver1/New_Manager_page/New_Manager_Home_page.dart';

import '../New_Data/new_constant.dart';

class New_Auth_page extends StatefulWidget {
  const New_Auth_page({super.key});

  @override
  State<New_Auth_page> createState() => _New_Auth_page();
}

class _New_Auth_page extends State<New_Auth_page> {
  bool _isChecked = false;
  final id_controller = TextEditingController();
  final pw_controller = TextEditingController();

  String userid = ''; // 사용자 이름(로그인용 id)를 저장하기 위한 변수
  String? userpw;

  static const storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
  }

  TextStyle style = const TextStyle(
      color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300);

  void _singIn() async {
    try {
      QuerySnapshot<Map<String, dynamic>> TMP = await FirebaseFirestore.instance.collection('User').get();
      for (var doc in TMP.docs) {
        if(doc['role'] == 'teacher'){
          if (doc['name'] == id_controller.text) {
            userpw = doc['password'];
            userid = doc.id;
            break;
          }
        } else if (doc['role'] == 'master') {
          if (doc['name'] == id_controller.text){
            userpw = doc['password'];
            userid = doc.id;
            break;
          }
        }
      }
      if (userpw != null && userpw == pw_controller.text){
        //로그인 성공
        setState(() {
          UserID = userid;
        });
        await MyModel();
        if(User.role == 'teacher'){
          await fetchSemesterInfo();
          await GetLesson();
        } else if (User.role == 'master') {
          await AllUsers();
          await fetchSemesterInfo();
          await Alllesson();
        }
        Userpw = User.password;
        UserName = User.name;

        if (_isChecked == true) {
          // 자동 로그인 켜져있는 경우
          // storage 에 각 값을 저장
          await storage.write(key: "auto_id", value: UserID);
          await storage.write(key: "auto_pw", value: Userpw);
        }
        // 입력 필드 초기화
        id_controller.clear();
        pw_controller.clear();

        if(User.role == 'teacher'){
          Navigator.of(context)
              .pushReplacement(MaterialPageRoute(builder: (context) {
            return const New_Home_page();
          }));
          print('로그인 완료');
        } else if (User.role == 'master'){
          Navigator.of(context)
              .pushReplacement(MaterialPageRoute(builder: (context) {
            return const New_Manager_Home_page();
          }));
          print('관리자 로그인 완료');
        }
        //로그인 과정이 모두 완료되었다면 Page 이동
      } else {
        //만약 pw 일치하지 않는 경우 (아이디 비밀번호 확인하기)
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Container(
                    child: Text(
                      '로그인 실패',
                      style: style.copyWith(
                        color: PRIMARY_COLOR,
                        fontSize: 17,
                      ),
                      textAlign: TextAlign.center,
                    )),
                content: Text('아이디/비밀번호를 다시 확인해주세요',
                    style: style.copyWith(fontSize: 15)),
              );
            });
      }
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: PRIMARY_COLOR,
        body: Center(
            child: Padding(
                padding: const EdgeInsets.only(left: 20, right: 20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Image.asset(
                        'assets/img/FORESTRING_Logo.png',
                        width: MediaQuery.of(context).size.width / 0.5,
                      ),
                      const Text(
                        '포레스트링 선생님',
                        style: TextStyle(
                            fontFamily: 'ELAND',
                            fontWeight: FontWeight.w300,
                            color: Colors.white,
                            fontSize: 20),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20.0),
                      TextField(
                        controller: id_controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                            filled: true,
                            fillColor: PRIMARY_COLOR,
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                            enabledBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                            labelText: '아이디',
                            labelStyle: const TextStyle(
                              fontFamily: 'ELAND',
                              fontWeight: FontWeight.w300,
                              color: Colors.white,
                            ),
                            suffixIcon: IconButton(
                              onPressed: () {
                                id_controller.clear();
                              },
                              icon: const Icon(Icons.close, size: 20),
                              color: Colors.white,
                            )),
                      ),
                      const SizedBox(height: 10.0),
                      TextField(
                        controller: pw_controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: PRIMARY_COLOR,
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                          labelText: '비밀번호',
                          labelStyle: const TextStyle(
                            fontFamily: 'ELAND',
                            fontWeight: FontWeight.w300,
                            color: Colors.white,
                          ),
                          suffixIcon: IconButton(
                            onPressed: () {
                              pw_controller.clear();
                            },
                            icon: const Icon(Icons.close, size: 20),
                            color: Colors.white,
                          ),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        const Text(
                          '자동 로그인',
                          style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'ELAND',
                              fontWeight: FontWeight.w300,
                              fontSize: 15),
                        ),
                        CupertinoSwitch(
                            value: _isChecked,
                            trackColor: Colors.white24,
                            activeColor: CupertinoColors.activeGreen,
                            onChanged: (bool? value) {
                              setState(() {
                                _isChecked = value ?? false;
                              });
                            }),
                      ]),
                      const SizedBox(height: 10.0),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 40)),
                        onPressed: () async {
                          _singIn();
                        },
                        child: const Text(
                          '로그인',
                          style: TextStyle(
                              color: PRIMARY_COLOR,
                              fontFamily: 'ELAND',
                              fontWeight: FontWeight.w300,
                              fontSize: 20),
                        ),
                      ),
                    ],
                  ),
                ))));
  }
}