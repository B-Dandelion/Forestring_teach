class StudentClass{
  //학생 클래스

  final String id;
  final String name;
  final String role;
  final String password;
  final DateTime classDay;
  final String teacherID;
  final String teacherName;
  final List<String> classList;

  StudentClass({required this.id, required this.name, required this.role, required this.classDay, required this.password,
    required this.teacherID, required this.teacherName, required this.classList});

  StudentClass.fromJson({
    required Map<String, dynamic> json,
  }) : id = json['id'],
        name = json['name'],
        role = json['role'],
        password = json['password'],
        classDay = json['classDay'].toDate(),
        teacherID = json['teacherID'],
        teacherName = json['teacherName'],
        classList = List<String>.from(json['classList']);


  Map<String, dynamic> toJson() {
    return {
      'id' : id,
      'name' : name,
      'role' : role,
      'password' : password,
      'classDay' : classDay,
      'teacherID' : teacherID,
      'teacherName' : teacherName,
      'classList' : classList,
    };
  }
}