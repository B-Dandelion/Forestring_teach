import 'package:flutter/material.dart';
import 'package:forestring_teach/Data/constant.dart';
import 'package:forestring_teach/Data/calendar.dart';

class Schedule_page extends StatefulWidget {
  const Schedule_page({super.key});

  @override
  State<Schedule_page> createState() => _Schedule_page();
}

class _Schedule_page extends State<Schedule_page>{
  DateTime selectedDate = DateTime.utc(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime focusedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BaseAppBar(title: "FORESTRING", center: true, appBar: AppBar()),
      drawer: const BaseDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            WeekCalendar(
              selectedDate: selectedDate,
              onDaySelected: onDaySelected,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
  void onDaySelected(DateTime selectedDate, DateTime focusedDate) {
    setState(() {
      this.selectedDate = selectedDate;
      this.focusedDate = selectedDate;
    });
  }
}