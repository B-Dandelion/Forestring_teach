import 'package:flutter/material.dart';
import 'package:forestring_teach/Data/constant.dart';

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

class My_page extends StatefulWidget {
  const My_page({super.key});

  @override
  State<My_page> createState() => _My_page();
}

class _My_page extends State<My_page> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BaseAppBar(title: "FORESTRING", center: true, appBar: AppBar()),
      drawer: const BaseDrawer(),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: <Widget>[
              Container(
                  padding: const EdgeInsets.only(top: 50),
                  child: const CircleAvatar(
                    radius: 80,
                    backgroundImage: AssetImage('assets/img/ME_Profile.png'),
                  )),
              Container(
                padding: const EdgeInsets.only(top: 20),
                child: const Text(
                  '진민경 님',
                  style: TextStyle(
                      color: Colors.black,
                      fontFamily: 'ELAND',
                      fontWeight: FontWeight.w300,
                      fontSize: 22),
                ),
              ),
              const SizedBox(height: 20.0),
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(
                        padding: const EdgeInsets.only(top: 20),
                        width: 100,
                        height: 1,
                        color: PRIMARY_COLOR),
                    const SizedBox(width: 10),
                    Container(
                      child: const Text(
                        '정규 수업',
                        style: TextStyle(
                            color: PRIMARY_COLOR,
                            fontFamily: 'ELAND',
                            fontWeight: FontWeight.w300,
                            fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                        width: 100,
                        height: 1,
                        color: PRIMARY_COLOR),
                  ]),
              const SizedBox(height: 20.0),
              const SizedBox(height: 20.0),
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(
                        padding: const EdgeInsets.only(top: 20),
                        width: 100,
                        height: 1,
                        color: PRIMARY_COLOR),
                    const SizedBox(width: 10),
                    Container(
                      child: const Text(
                        '다음 수업',
                        style: TextStyle(
                            color: PRIMARY_COLOR,
                            fontFamily: 'ELAND',
                            fontWeight: FontWeight.w300,
                            fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                        width: 100,
                        height: 1,
                        color: PRIMARY_COLOR),
                  ]),
              const SizedBox(height: 20.0),
            ],
          ),
        ),
      ),
    );
  }
}