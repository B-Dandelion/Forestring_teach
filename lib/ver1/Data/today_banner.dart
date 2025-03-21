import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver1/Data/constant.dart';
import 'package:intl/intl.dart';

class TodayBanner extends StatelessWidget {
  final DateTime selectedDate;
  final int count;
  // final int count;

  const TodayBanner({
    required this.selectedDate,
    required this.count,
    // required this.count,
    super.key
  });



  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
        fontFamily: 'ELAND',
        fontWeight: FontWeight.w300,
        color: Colors.white
    );

    String e = '';
    if(selectedDate.isAfter(DateTime.now())){
      e = '예약된 수업';
    }else if(DateFormat('yyyyMMdd').format(selectedDate) == DateFormat('yyyyMMdd').format(DateTime.now())){
      e = '오늘 수업';
    }else{
      e = '완료된 수업';
    }
    return Container(
        color: PRIMARY_COLOR,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${selectedDate.year}년 ${selectedDate.month}월 ${selectedDate.day}일',
                  style: textStyle,
                ),

                Text(
                  '$e $count개',
                  style: textStyle,
                )
              ],
            )
        )
    );
  }
}
