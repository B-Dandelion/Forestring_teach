import 'package:flutter/material.dart';
import 'package:forestring_teach/Data/constant.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';


class Schedule_page extends StatefulWidget {
  const Schedule_page({super.key});

  @override
  State<Schedule_page> createState() => _Schedule_page();
}

class _Schedule_page extends State<Schedule_page>{
  DateTime selectedDate = DateTime.utc( //선택된 날짜를 관리할 변수
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime focusedDate = DateTime.now();
  final int startM = DateTime.now().subtract(const Duration(days: 100)).month;
  final int endM = DateTime.now().add(const Duration(days:100)).month;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BaseAppBar(title: "FORESTRING", center: true, appBar: AppBar()),
      drawer: const BaseDrawer(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(
              bottom: 8,
              left: 8,
              right: 8),
          child: Column(
            children: [
              TableCalendar(
                firstDay: DateTime(DateTime.now().year, startM, 1),
                lastDay: DateTime(DateTime.now().year, endM, 1),
                focusedDay: focusedDate,
                calendarFormat: CalendarFormat.week, //table calendar style 선택

                onDaySelected: (DateTime selectedDate, DateTime focusedDate) {
                  setState(() {
                    this.selectedDate = selectedDate;
                    this.focusedDate = focusedDate;
                  });
                },
                selectedDayPredicate: (date) => //선택된 날짜를 구분 할 로직
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
                  // 달력 속 날짜 숫자 색상 변경(요일에 맞게)
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
              ),
              const SingleChildScrollView()
            ],
          ),
        ),
      )
    );
  }
}