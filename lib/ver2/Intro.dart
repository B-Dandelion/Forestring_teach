import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:forestring_teacher_2/ver2/Login.dart';
import 'package:forestring_teacher_2/ver2/Master/Manage.dart';
import 'package:forestring_teacher_2/ver2/Teacher/Home.dart';
import 'package:provider/provider.dart';

class Intro extends StatefulWidget {
  const Intro({super.key});

  @override
  State<Intro> createState() => _Intro();
}

class _Intro extends State<Intro> {
  static const storage = FlutterSecureStorage();
  bool logincheck = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkInternetAndLogin();
  }
  // ** 인터넷 연결 확인 후 자동 로그인 시도**
  Future<void> _checkInternetAndLogin() async {
    var connectivityResult = await Connectivity().checkConnectivity();

    if (connectivityResult == ConnectivityResult.none) {
      // 인터넷 연결 없음 → 사용자에게 알림
      _showNoInternetDialog();
      return;
    }

    // 인터넷 연결이 있으면 자동 로그인 시도
    _attemptAutoLogin();
  }

  // ** 자동 로그인 시도**
  Future<void> _attemptAutoLogin() async {
    try {
      // 1. 저장된 사용자 정보 불러오기
      String? userId = await storage.read(key: "auto_id.ver2");
      String? userPw = await storage.read(key: "auto_pw.ver2");

      if (userId == null || userPw == null) {
        // 자동 로그인 된 정보가 없다면 로그인 페이지로 바로 이동
        _navigateToLogin();
        return;
      }

      // 2. Firestore에서 사용자 정보 가져오기
      FirebaseFirestore firestore = FirebaseFirestore.instance;
      DocumentSnapshot userDoc = await firestore.collection('users').doc(userId).get();

      if (!userDoc.exists || userDoc['password'] != userPw) {
        // 자동 로그인에 저장된 비번과 데이터 상 비번이 다르다면 로그인 화면페이지로 이동
        // 이렇게 하면 버전이 바뀌며 데이터 구조가 바뀌어도 자동 로그인에 문제가 생기지 않음

        _navigateToLogin();
        return;
      }

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // 3. 로그인 성공 → UserProvider에 정보 저장
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      await userProvider.setUser(
        userId,
        userData['name'],
        userData['password'],
        userData['role'],
      );

      // 로딩 다이얼 표시
      showLoadingDialog();

      // 4. 역할에 따라 추가 데이터 로드
      await fetchSemesterInfo();

      if (userProvider.role == "master") {
        // 마스터 계정 → 모든 레슨, 모든 수업에 전부 접근할 수 있음.

        final Masterprovider = Provider.of<MasterProvider>(context, listen: false);
        await Masterprovider.fetchUsers();
        await Masterprovider.fetchAllAvailableSlots();
        await Masterprovider.fetchLessons(); // lesson 데이터도 가져오기
        Masterprovider.listenToAvailableSlotsUpdates();
        Masterprovider.listenToLessonsUpdates(); // lesson 실시간 업데이트 감지
        Masterprovider.listenToUserCollectionUpdates();

        Navigator.of(context).pop();
        _navigateToHome(userProvider.role);
      } else {
        final lessonProvider = Provider.of<LessonProvider>(context, listen: false);
        await lessonProvider.fetchTeacherLessons(userProvider.userID);
        lessonProvider.listenToTeacherLessons(userProvider.userID);

        final workProvider = Provider.of<SlotProvider>(context, listen: false);
        await workProvider.fetchTeacherSlots(userProvider.userID);
        workProvider.listenToTeacherSlotsUpdates(userProvider.userID);

        // 로딩 다이얼로그 닫기 후 홈 이동
        Navigator.of(context).pop();
        _navigateToHome(userProvider.role);
      }

    } catch (e) {
      print("자동 로그인 중 오류 발생: $e");
      // 오류가 발생해도 로그인 페이지로 이동
      _navigateToLogin();
    }
  }
  // 로그인 페이지로 이동
  void _navigateToLogin() {
    Navigator.of(context).pushReplacement(
      _createRoute(const Login()),
    );
  }

  // 홈 화면으로 이동
  void _navigateToHome(String role) {
    setState(() {
      _isLoading = false;
    });
    Navigator.of(context).pushReplacement(
      _createRoute(role == "master" ? Manage() : const Home()),
    );
  }

  // 인터넷 연결이 없을 때 다이얼로그 표시
  void _showNoInternetDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('인터넷 연결 오류'),
          content: const Text('인터넷에 연결되지 않았습니다. 연결을 확인하고 다시 시도해주세요.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 팝업 닫기
                _checkInternetAndLogin(); // 재시도
              },
              child: const Text('재시도'),
            ),
          ],
        );
      },
    );
  }
  void showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 로딩 중 다이얼로그 닫기 방지
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            '로딩 중...',
            style: style.copyWith(color: PRIMARY_COLOR, fontSize: 17),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(PRIMARY_COLOR)),
              const SizedBox(height: 10),
              Text(
                "수업 정보를 불러오는 중...",
                style: style.copyWith(fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  // UI 부분

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: PRIMARY_COLOR,
        body: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Image.asset('assets/img/포레스트링_선생님_로고.png',
                        fit: BoxFit.contain),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(PRIMARY_COLOR), // 녹색 원 모양
                ),
              ),
          ],
        )
    );
  }
}

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