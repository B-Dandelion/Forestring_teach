import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';
import 'package:forestring_teacher_2/ver1/Data/schedule_card.dart';
import 'package:forestring_teacher_2/ver1/Data/schedule_model.dart';
import 'package:forestring_teacher_2/ver1/Data/today_banner.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class Home_page extends StatefulWidget {
  const Home_page({super.key});

  @override
  State<Home_page> createState() => _Home_page();
}

class _Home_page extends State<Home_page> {
  DateTime selectedDate = DateTime.now();
  DateTime focusedDate = DateTime.now();
  late final ValueNotifier<List<ScheduleModel>> selectedEvents;
  DateTime tmp1 = DateTime(DateTime.now().year,DateTime.now().month,1).subtract(const Duration(days: 10));
  DateTime tmp2 = DateTime(DateTime.now().year,DateTime.now().month,20).add(const Duration(days: 55));

  @override
  void initState() {
    super.initState();
    selectedDate = focusedDate;
    selectedEvents = ValueNotifier(_getEvents(selectedDate));
  }

  List<ScheduleModel> _getEvents(DateTime day) {
    //일정 정보를 20240910 : ScheduleModelList 형식으로 저장해주는 함수임.
    List<Map<DateTime, dynamic>> EVENTS = [{}];
    Map<DateTime, dynamic>? events;
    String Dayformat = DateFormat('yyyyMMdd').format(day);

    for (int i = 0; i<Schedules.length; i++){
      if(DateFormat('yyyyMMdd').format(DateTime.parse(Schedules[i].date.toString())) == Dayformat){
        if(events != null && events.containsKey(DateTime.utc(day.year,day.month,day.day))) {
          events[DateTime.utc(day.year,day.month,day.day)].add(Schedules[i]);
          EVENTS.add(events);
        } else {
          events  = {
            DateTime.utc(day.year,day.month,day.day) : [Schedules[i]]
          };
          EVENTS.add(events);
        }
      }
    }

    for(int i = 0; i<Rebooked.length; i++) {
      if(DateFormat('yyyyMMdd').format(DateTime.parse(Rebooked[i].date.toString())) == Dayformat){
        if(events != null && events.containsKey(DateTime.utc(day.year,day.month,day.day))) {
          events[DateTime.utc(day.year,day.month,day.day)].add(Rebooked[i]);
          EVENTS.add(events);
        } else {
          events  = {
            DateTime.utc(day.year,day.month,day.day) : [Rebooked[i]]
          };
          EVENTS.add(events);
        }
      }
    }

    EVENTS = List.from(EVENTS.reversed);
    return EVENTS[0][day] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BaseAppBar(title: "FORESTRING", center: true, appBar: AppBar()),
      drawer: const BaseDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            TableCalendar(
              firstDay: DateTime(tmp1.year,tmp1.month,1),
              lastDay: DateTime(tmp2.year, tmp2.month,0),
              // firstDay: DateTime(DateTime.now().year, startM, 1),
              // lastDay: DateTime(DateTime.now().year, endM, 1),
              focusedDay: focusedDate,
              onDaySelected: (DateTime selectedDate, DateTime focusedDate) {
                setState(() {
                  this.selectedDate = selectedDate;
                  this.focusedDate = focusedDate;
                });
              },
              selectedDayPredicate: (day) {
                return isSameDay(selectedDate, day);
              },
              calendarBuilders: CalendarBuilders(dowBuilder: (context, day) {
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
                  }, markerBuilder: (context, date, events) {
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
              eventLoader: _getEvents,
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
                child: Column(
                    children: [
                      SingleChildScrollView(
                          child: SizedBox(
                              height: 250,
                              child: ListView.builder(
                                  itemCount: _getEvents(selectedDate).length,
                                  itemBuilder: (context, index){
                                    final schedule = _getEvents(selectedDate);
                                    final EVENTS = schedule[index];

                                    DateTime tmp = EVENTS.date;
                                    return Padding(padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                                        child: ScheduleCard(
                                            teacher: UserName,
                                            startTime: tmp.hour*100 + tmp.minute,
                                            endTime: tmp.add(const Duration(minutes: 30)).hour*100 + tmp.add(const Duration(minutes: 30)).minute,
                                            month: tmp.month,
                                            date: tmp.day,
                                            studentID: EVENTS.name));
                                  }
                              )
                          )
                      ),
                      const Expanded(child: SizedBox()),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              minimumSize: const Size(50,35),
                              side: const BorderSide(color: PRIMARY_COLOR, width: 1.5)),
                          onPressed: () async {
                            await getschedule(context);
                            _getEvents(selectedDate);
                          },
                          child: const Text('새로고침',
                              style: TextStyle(fontFamily: 'ELAND',color: PRIMARY_COLOR))),
                    ]
                )),
          ],
        ),
      ),
    );
  }
}