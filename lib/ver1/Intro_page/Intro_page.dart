import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';
import 'package:forestring_teacher_2/ver1/Intro_page/Auth_page.dart';
import 'package:forestring_teacher_2/ver1/Main_page/Home_page.dart';
import 'package:forestring_teacher_2/ver1/Manager_page/Manager_Home_page.dart';

class Intro_page extends StatefulWidget {
  const Intro_page({super.key});

  @override
  State<StatefulWidget> createState() {
    return _Intro_page();
  }
}

class _Intro_page extends State<Intro_page> {
  String? userid; // 사용자 이름(로그인용 id)를 저장하기 위한 변수
  String? userpw;
  String? username;
  static const storage = FlutterSecureStorage();
  bool logincheck = false;

  @override
  void initState() {
    super.initState();
    _asyncMethod();
  }

  void _asyncMethod() async {
    //read 함수를 통하여 key 값에 맞는 정보를 불러옴. (자료형은 Striing)
    //당연히 데이터 없을 땐 null 반영
    try {
      userid = (await storage.read(key: "auto_id"))!;
      userpw = (await storage.read(key: "auto_pw"))!;
      username = (await storage.read(key: "name"))!;

      if (userid != null) {
        setState(() {
          logincheck = true;
          UserID = userid!;
          Userpw = userpw!;
          UserName = username!;
        });
        if(UserName == '김진아'){
          await semester();
        } else{
          await getMyModel();
        }
      }
    } catch (e) {
      print('async 함수에서 발생한 에러 \n $e \n ---------------------');
    }
  }

  Future<void> login() async {
    try {
      await semester();
      await getWorkHour(UserID);
      await getstudents(context);
      await getschedule(context);
    } catch (e) {
      print('$e 로그인 함수에서 발생한 에러');
    }
  }

  Future<void> Managerlogin() async {
    print('Managerlogin 함수 실행됨');
    try {
      await getallstudents();
      await getallteachers();
      await getallschedules();
      await getallcount();
      await getWorkHour(AllTeacherList[0].id);
    } catch (e) {
      print('$e 매니저 로그인 함수에서 발생한 에러');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PRIMARY_COLOR,
      body: FutureBuilder(
        future: connectCheck(),
        builder: (context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.active:
              print('activating');
              return const Center(
                child: CircularProgressIndicator(),
              );
            case ConnectionState.done:
              print('done');
              if (snapshot.data != null) {
                if (snapshot.data!) {
                  if (logincheck == true) {
                    if(UserName == '김진아'){
                      Future.delayed(const Duration(seconds: 2), () async {
                        await Managerlogin();
                        Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (context) {
                              return const Manager_Home_page();
                            }));
                      });
                    } else {
                      Future.delayed(const Duration(seconds: 2), () async {
                        await login();
                        Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (context) {
                              return const Home_page();
                            }));
                      });
                    }
                  } else {
                    Future.delayed(const Duration(seconds: 2), () async {
                      Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (context) {
                            return const Auth_page();
                          }));
                    });
                  }
                }
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Image.asset('assets/img/FORESTRING_Logo.png',
                            fit: BoxFit.contain),
                      ),
                    ],
                  ),
                );
              } else {
                return const AlertDialog(
                    title: Text('포레스트링 수강생'),
                    content: Text('지금 인터넷에 연결되지 않아 포레스트링 앱을 실행할 수 없습니다.'
                        '네트워크 연결 후 다시 실행 해 주십시오.'));
              }
            case ConnectionState.none:
              return const Center(
                child: Text('데이터가 없습니다'),
              );
            case ConnectionState.waiting:
              print('waiting');
              return const Center(
                child: CircularProgressIndicator(),
              );
          }
        },
      ),
    );
  }

  Future<bool> connectCheck() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.isEmpty) return false;
    if (connectivityResult.first == ConnectivityResult.mobile ||
        connectivityResult.first == ConnectivityResult.wifi) {
      return true;
    }
    return false;
  }
}