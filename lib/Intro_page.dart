import 'package:flutter/material.dart';
import 'package:forestring_teach/Home_page.dart';
import 'package:forestring_teach/Data/constant.dart';
import 'package:forestring_teach/Auth_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

Route _createRoute() {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => Auth_page(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(0.0, 1.0);
      const end = Offset.zero;
      final tween = Tween(begin: begin, end: end);
      final offsetAnimation = animation.drive(tween);
      return child;
    },
  );
}

class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  State<StatefulWidget> createState(){
    return _IntroPage();
  }
}

class _IntroPage extends State<IntroPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PRIMARY_COLOR,
      body: FutureBuilder(future: connectCheck(),
        builder: (context, snapshot) {
          switch (snapshot.connectionState) {
            case ConnectionState.active:
              return const Center(
                child: CircularProgressIndicator(),
              );
            case ConnectionState.done:
              if(snapshot.data != null) {
                if (snapshot.data!) {
                  Future.delayed(const Duration(seconds: 2), () {
                    Navigator.of(context).push(
                      _createRoute(),
                    );
                  });
                }

                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Image.asset(
                            'assets/img/FORESTRING_Logo.png',
                            fit: BoxFit.contain
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                return const AlertDialog(
                    title: Text(Constant.APP_NAME),
                    content: Text(
                        '지금 인터넷에 연결되지 않아 포레스트링 앱을 실행할 수 없습니다.'
                            '네트워크 연결 후 다시 실행 해 주십시오.'
                    )
                );
              }
            case ConnectionState.none:
              return const Center(
                child: Text('데이터가 없습니다'),
              );
            case ConnectionState.waiting:
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