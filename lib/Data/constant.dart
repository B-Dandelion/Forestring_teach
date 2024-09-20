import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import 'package:forestring_teach/Home_page.dart';
import 'package:forestring_teach/My_page.dart';

class Constant {
  static const APP_NAME = 'FORESTRING';
}


const PRIMARY_COLOR = Color(0xff003717);
const SECONDARY_COLOR = Color(0xff003411);
const IBORY = Color(0xffFDF8E7);
const ERROR_COLOR = Colors.red;
const TEXT_FIELD_FILL_COLOR = Colors.black;

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

class BaseAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BaseAppBar({super.key,
    required this.appBar,
    required this.title,
    this.center = true});

  final AppBar appBar;
  final String title;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: PRIMARY_COLOR,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Text(
        title,
        style: const TextStyle(
            color: Colors.white,
            fontFamily: 'OpenSans',
            fontWeight: FontWeight.w500,
            fontSize: 20),
      ),
      centerTitle: true,
      elevation: 0.0, //앱바 밑에 그림자
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(appBar.preferredSize.height);
}

class BaseDrawer extends StatelessWidget {
  const BaseDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const UserAccountsDrawerHeader(
            currentAccountPicture: CircleAvatar(
              backgroundImage: AssetImage('assets/img/ME_Profile.png'),
            ),
            accountName: Text(
              '진민경 님',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            accountEmail: Text(
              'Michelle_mk@naver.com',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'OpenSans',
                fontWeight: FontWeight.w300,
              ),
            ),
            decoration: BoxDecoration(
                color: PRIMARY_COLOR,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(10.0),
                  bottomRight: Radius.circular(10.0),
                )),
          ),
          ListTile(
            leading: const Icon(Icons.account_circle),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '마이페이지',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              Navigator.of(context).push(
                _createRoute(const My_page()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.home_filled),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '메인페이지',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {
              Navigator.of(context).push(
                _createRoute(const Home_page()),
              );
            },
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_rounded),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '예약 변경하기',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {},
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner_rounded),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              'QR Check In',
              style: TextStyle(
                color: Colors.black,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {},
            trailing: const Icon(Icons.navigate_next_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            iconColor: PRIMARY_COLOR,
            focusColor: IBORY,
            title: const Text(
              '로그아웃',
              style: TextStyle(
                color: Colors.red,
                fontFamily: 'ELAND',
                fontWeight: FontWeight.w300,
              ),
            ),
            onTap: () {},
            trailing: const Icon(Icons.navigate_next_rounded),
          )
        ],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MainCalendar extends StatelessWidget {
  final OnDaySelected onDaySelected;
  final DateTime selectedDate;

  const MainCalendar({super.key, 
    required this.onDaySelected,
    required this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    return TableCalendar(
      onDaySelected: onDaySelected,
      selectedDayPredicate: (date) =>
      date.year == selectedDate.year &&
          date.month == selectedDate.month &&
          date.day == selectedDate.day,

      calendarBuilders: CalendarBuilders(
        dowBuilder: (context, day) {
          final text = DateFormat.E().format(day);
          if (day.weekday == DateTime.sunday) {
            return Center(
                child: Text(
                  text,
                  style: const TextStyle(
                      fontFamily: 'OpenSans',
                      fontWeight: FontWeight.w500,
                      color: Colors.red),
                ));
          } else if (day.weekday == DateTime.saturday) {
            return Center(
                child: Text(text,
                    style: const TextStyle(
                        fontFamily: 'OpenSans',
                        fontWeight: FontWeight.w500,
                        color: Colors.blue)));
          } else {
            return Center(
                child: Text(text,
                    style: const TextStyle(
                      fontFamily: 'OpenSans',
                      fontWeight: FontWeight.w500,
                    )));
          }
        },
        defaultBuilder: (context, day, _) {
          return Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                  color: day.weekday == 7
                      ? Colors.red
                      : day.weekday == 6
                      ? Colors.blue
                      : Colors.black),
            ),
          );
        },
      ),

      focusedDay: DateTime.now(),
      //화면에 보여지는 날짜
      firstDay: DateTime(2020, 1, 1),
      lastDay: DateTime(2059, 12, 31),
      headerStyle: const HeaderStyle(
        titleCentered: true,
        formatButtonVisible: false,
        titleTextStyle: TextStyle(
          fontFamily: 'OpenSans',
          fontWeight: FontWeight.w500,
          fontSize: 20.0,
        ),
      ),

      calendarStyle: const CalendarStyle(
        isTodayHighlighted: true,
        todayDecoration: BoxDecoration(
          color: PRIMARY_COLOR,
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(
          color: Colors.white,
          fontFamily: 'openSans',
          fontWeight: FontWeight.w500,
        ),
        weekendDecoration: BoxDecoration(
          shape: BoxShape.circle,
        ),
        weekendTextStyle: TextStyle(
          color: Colors.red,
          fontFamily: 'openSans',
          fontWeight: FontWeight.w300,
        ),
        selectedDecoration: BoxDecoration(
          color: Color(0xff708C7A),
          shape: BoxShape.circle,
        ),
        selectedTextStyle: TextStyle(
          color: Colors.black,
          fontFamily: 'openSans',
          fontWeight: FontWeight.w500,
        ),
        defaultTextStyle: TextStyle(
          fontFamily: 'openSans',
          fontWeight: FontWeight.w300,
        ),
      ),
    );
  }
}