import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:forestring_teach/Home_page.dart';
import 'package:forestring_teach/Data/constant.dart';

class Auth_page extends StatefulWidget {
  const Auth_page({super.key});

  @override
  State<Auth_page> createState() => _Auth_page();
}

class _Auth_page extends State<Auth_page> {
  final String _message = '';
  bool _isChecked = false;
  final id_controller = TextEditingController();
  final pw_controller = TextEditingController();

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
                  '포레스트링 수강생용',
                  style: TextStyle(
                      fontFamily: 'ELAND',
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      fontSize: 17),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20.0),
                TextField(
                  controller: id_controller,
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
                  onPressed: () {
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
                Text(_message),
              ],
            ),
          ),
        ));
  }
}

