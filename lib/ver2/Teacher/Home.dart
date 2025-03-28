import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _Home();
}

class _Home extends State<Home> {
  DateTime selectedDate = DateTime.now();
  DateTime focusedDate = DateTime.now();
  late final ValueNotifier<List<Map<String,dynamic>>> selectedEvents;

  @override
  void initState() {
    super.initState();
    selectedDate = focusedDate;
    selectedEvents = ValueNotifier(_getEvents(selectedDate));
  }

  //특정 날짜의 수업을 가져옴
  List<Map<String, dynamic>> _getEvents(DateTime day) {
    final lessonProvider = Provider.of<LessonProvider>(context, listen: false);
    String formattedDay = DateFormat('yyyyMMdd').format(day);

    return lessonProvider.lessons.entries
        .where((entry) =>
    DateFormat('yyyyMMdd').format(entry.value['date']) == formattedDay)
        .map((entry) => entry.value) // lessonId 제거하고 lessonData만 반환
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    DateTime tmp1 = DateTime(DateTime.now().year, DateTime.now().month - 1, 1);
    DateTime tmp2 = DateTime(DateTime.now().year, DateTime.now().month + 1, 31);
    return Scaffold(
      appBar: BaseAppBar(title: "FORESTRING", center: true, appBar: AppBar()),
      drawer: const BaseDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            TableCalendar(
              firstDay: tmp1,
              lastDay: tmp2,
              focusedDay: focusedDate,
              onDaySelected: (DateTime selectedDate, DateTime focusedDate) {
                setState(() {
                  this.selectedDate = selectedDate;
                  this.focusedDate = focusedDate;
                  selectedEvents.value = _getEvents(selectedDate);
                });
              },
              selectedDayPredicate: (day) => isSameDay(selectedDate, day),
              eventLoader: _getEvents,
              calendarBuilders: CalendarBuilders(
                  dowBuilder: (context, day) {
                    final text = DateFormat.E().format(day);
                    return Center(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontFamily: 'OpenSans',
                          fontWeight: FontWeight.w500,
                          color: day.weekday == DateTime.sunday
                              ? Colors.red
                              : day.weekday == DateTime.saturday
                              ? Colors.blue
                              : Colors.black,
                        ),
                      ),
                    );
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
                  markerBuilder: (context, date, events) {
                    if (events.isNotEmpty) {
                      return Column(
                        children: [
                          const SizedBox(height: 45),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                                color: Color(0xff2E8B57),
                                shape: BoxShape.circle),
                          ),
                        ],
                      );
                    }
                    return null;
                  }),
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
                  color: Color(0xff124736),
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
              onPageChanged: (focusedDate) {
                // No need to call `setState()` here
                focusedDate = focusedDate;
              },
            ),
            const SizedBox(height: 8),
            TodayBanner(
                selectedDate: selectedDate,
                count: _getEvents(selectedDate).length),
            const SizedBox(height: 8),
            Expanded(
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: selectedEvents,
                  builder: (context, lessons, _) {
                    return ListView.builder(
                      itemCount: lessons.length,
                      itemBuilder: (context, index) {
                        final lesson = lessons[index];
                        final userProvider = Provider.of<UserProvider>(context, listen: false);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                          child: LessonCard(
                            startTime: lesson['date'],
                            endTime: lesson['date'].add(Duration(minutes: lesson['duration'])),
                            month: lesson['date'].month,
                            date: lesson['date'].day,
                            student: userProvider.displayStudentName(lesson['studentId']),
                            teacher: userProvider.userName,
                          ),
                        );
                      },
                    );
                  },
                )
            ),
          ],
        ),
      ),
    );
  }
}