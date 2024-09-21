import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teach/Data/constant.dart';

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

class WeekCalendar extends StatelessWidget {
  final OnDaySelected onDaySelected;
  final DateTime selectedDate;

  WeekCalendar({super.key,
    required this.onDaySelected,
    required this.selectedDate,
  });

  final int startM = DateTime.now().subtract(const Duration(days: 100)).month;
  final int endM = DateTime.now().add(const Duration(days:100)).month;
  
  @override
  Widget build(BuildContext context) {
    return TableCalendar(

      firstDay: DateTime(DateTime.now().year, startM, 1),
      lastDay: DateTime(DateTime.now().year, endM, 0),
      focusedDay: DateTime.now(),
      calendarFormat: CalendarFormat.week,
      onDaySelected: onDaySelected,
      selectedDayPredicate: (date) =>
      date.year == selectedDate.year &&
          date.month == selectedDate.month &&
          date.day == selectedDate.day,

        calendarBuilders: CalendarBuilders(
          // 요일 배너 주말 과 평일 글꼴 설정, 색상 설정
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

      //화면에 보여지는 날짜
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