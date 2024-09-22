import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:forestring_teach/Home_page.dart';
import 'package:forestring_teach/Data/constant.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class teacherID {
  final String id;
  final String pw;

  teacherID({required this.id, required this.pw});

  teacherID.fromJson({
    required Map<String, dynamic> json,
  }) : id = json['id'],
        pw = json['pw'];

  Map<String, dynamic> toJson(){
    return {
      'id' : id,
      'pw' : pw,
    };
  }

  teacherID copyWith({
    String? id,
    String? pw,
  }) {
    return teacherID(
      id: id ?? this.id,
      pw: pw ?? this.pw,
    );
  }
}

class Auth_page extends StatefulWidget {
  const Auth_page({super.key});

  @override
  State<Auth_page> createState() => _Auth_page();
}

class _Auth_page extends State<Auth_page> {
  bool _isChecked = false;

  String _message = '초기값입니다';

  final idController = TextEditingController();
  final pwController = TextEditingController();

  String? userid; // 사용자 이름(로그인용 id)를 저장하기 위한 변수
  String? userpw;

  static const storage = FlutterSecureStorage(); //flutter_secure_storage 사용을 위한 초기화 작업

  @override

  void initState() {
    super.initState();

    //비동기로 secure storage 정보를 불러오는 작업 (자동로그인)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _asyncMethod();
    });
  }

  _asyncMethod() async {
    //read 함수를 통하여 key 값에 맞는 정보를 불러옴. (자료형은 String)
    //당연히 데이터 없을 땐 null 반영
    userid = (await storage.read(key:"id"))!;
    userpw = (await storage.read(key:"pw"))!;

    if(userid != null) {
      //id 정보가 있다면 UserID에 저장 후 자동으로 로그인 됨
      UserID = userid!;
      Userpw = userpw;
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (context) {
        return const Home_page();
      }));
    }
  }

  @override

  _checkLogin(String user) async {
    DocumentSnapshot teacherID = await FirebaseFirestore.instance.collection('teacher').doc(user).get();
    if(teacherID != null) {
      setState(() {
        userid = user;
        userpw = teacherID['pw'];
        _message = '사용자 확인 완료';
      });
    }
  }

  @override

  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: PRIMARY_COLOR,
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 70.0),
                Align(
                  alignment: Alignment.center,
                  child: Image.asset('assets/img/FORESTRING_Logo.png',
                      width: 400, height: 400),
                ),
                const Text(
                  '포레스트링 선생님용',
                  style: TextStyle(
                      fontFamily: 'ELAND',
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20.0),
                TextField(
                  controller: idController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                      filled: true,
                      fillColor: SECONDARY_COLOR,
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
                          idController.clear();
                        },
                        icon: const Icon(Icons.close, size: 20),
                        color: Colors.white,
                      )),
                ),
                const SizedBox(height: 10.0),
                TextField(
                  controller: pwController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: SECONDARY_COLOR,
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
                        pwController.clear();
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
                Text( _message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontFamily: 'Open Sans',
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    //자동 로그인

                    _checkLogin(idController.text);

                    UserID = idController.text;
                    Userpw = pwController.text;

                    if(_isChecked == true) {
                      await storage.write(
                          key: "id",
                          value: idController.text);

                      await storage.write(
                          key: "pw",
                          value: pwController.text);
                    }
                    // 로그인 성공 시 페이지 이동 코드
                    Navigator.of(context)
                        .pushReplacement(MaterialPageRoute(builder: (context) {
                      return const Home_page();
                    }));
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
          ),
        ));
  }
}

