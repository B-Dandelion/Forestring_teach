import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../core/theme/forestring_theme.dart';
import '../../domain/lesson.dart';

class StudentStyleLessonCalendar extends StatefulWidget {
  const StudentStyleLessonCalendar({
    super.key,
    required this.lessons,
    required this.firstDay,
    required this.lastDay,
    required this.lessonBuilder,
  });

  final List<Lesson> lessons;
  final DateTime firstDay;
  final DateTime lastDay;
  final Widget Function(Lesson lesson) lessonBuilder;

  @override
  State<StudentStyleLessonCalendar> createState() =>
      _StudentStyleLessonCalendarState();
}

class _StudentStyleLessonCalendarState
    extends State<StudentStyleLessonCalendar> {
  static const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  late DateTime _selectedDate;
  late DateTime _focusedDate;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _selectedDate = _clamp(today);
    _focusedDate = _selectedDate;
  }

  @override
  void didUpdateWidget(covariant StudentStyleLessonCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameDay(oldWidget.firstDay, widget.firstDay) ||
        !isSameDay(oldWidget.lastDay, widget.lastDay)) {
      _selectedDate = _clamp(_selectedDate);
      _focusedDate = _selectedDate;
    }
  }

  DateTime _clamp(DateTime value) {
    final day = _dateOnly(value);
    final first = _dateOnly(widget.firstDay);
    final last = _dateOnly(widget.lastDay);
    if (day.isBefore(first)) return first;
    if (day.isAfter(last)) return last;
    return day;
  }

  List<Lesson> _lessonsOn(DateTime day) {
    final result = widget.lessons
        .where((lesson) => isSameDay(lesson.startsAt, day))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final selectedLessons = _lessonsOn(_selectedDate);

    return Column(
      children: [
        TableCalendar<Lesson>(
          firstDay: _dateOnly(widget.firstDay),
          lastDay: _dateOnly(widget.lastDay),
          focusedDay: _focusedDate,
          startingDayOfWeek: StartingDayOfWeek.sunday,
          selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
          eventLoader: _lessonsOn,
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDate = selectedDay;
              _focusedDate = focusedDay;
            });
          },
          onPageChanged: (focusedDay) {
            _focusedDate = focusedDay;
          },
          headerStyle: HeaderStyle(
            titleCentered: true,
            formatButtonVisible: false,
            titleTextFormatter: (date, locale) => '${date.month}월',
            leftChevronIcon: const Icon(
              Icons.chevron_left,
              color: primaryColor,
            ),
            rightChevronIcon: const Icon(
              Icons.chevron_right,
              color: primaryColor,
            ),
            titleTextStyle: const TextStyle(
              fontFamily: 'ELAND',
              fontWeight: FontWeight.w500,
              fontSize: 22,
              color: primaryColor,
            ),
          ),
          calendarStyle: const CalendarStyle(
            todayDecoration: BoxDecoration(
              color: primaryColor,
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: secondaryColor,
              shape: BoxShape.circle,
            ),
            markerDecoration: BoxDecoration(
              color: Color(0xff2E8B57),
              shape: BoxShape.circle,
            ),
          ),
          calendarBuilders: CalendarBuilders(
            dowBuilder: (context, day) {
              final label = _weekdayLabels[day.weekday - 1];
              return Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'ELAND',
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
          ),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: ivoryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${DateFormat('M월 d일').format(_selectedDate)} · '
            '${selectedLessons.length}개 수업',
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: selectedLessons.isEmpty
              ? Center(
                  child: Text(
                    '예약된 수업이 없습니다.',
                    style: forestringTextStyle.copyWith(
                      color: Colors.black54,
                      fontSize: 15,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                  itemCount: selectedLessons.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) =>
                      widget.lessonBuilder(selectedLessons[index]),
                ),
        ),
      ],
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
