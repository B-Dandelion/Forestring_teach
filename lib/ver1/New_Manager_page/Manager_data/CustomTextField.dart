import 'package:flutter/material.dart';
import '../../New_Data/new_constant.dart';


class CustomTextField extends StatelessWidget {
  final String label;
  final bool isTime;
  final FormFieldSetter<String> onSaved;
  final FormFieldValidator<String> validator;


  CustomTextField({
    required this.label,
    required this.isTime,
    required this.onSaved,
    required this.validator,
    super.key,
  });

  final Controller = TextEditingController();

  @override
  Widget build(BuildContext context){
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.black, fontFamily: 'ELAND', fontWeight: FontWeight.w300, fontSize: 17,)),
        TextFormField(
          onSaved: onSaved,
          validator: validator,
          maxLines: 1,
          cursorColor: PRIMARY_COLOR,
          expands: false,
          keyboardType: isTime ? TextInputType.number : TextInputType.multiline,
          decoration: InputDecoration(
              border: const OutlineInputBorder(borderSide: BorderSide.none),
              filled: true,
              fillColor: const Color(0xffFFFFF0),
              suffixText: isTime ? '전화번호' : '여백 없이 입력',
              suffixStyle: TextStyle(color: PRIMARY_COLOR.withOpacity(0.5), fontFamily: 'ELAND', fontWeight: FontWeight.w300)
          ),
        )
      ],
    );
  }
}

