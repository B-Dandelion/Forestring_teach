import 'package:flutter/material.dart';
import 'package:forestring_teacher_2/ver2/Data/constant_data.dart';
import 'package:forestring_teacher_2/ver2/Master/Setting/BanTime.dart';
import 'package:forestring_teacher_2/ver2/Master/Setting/SemesterE.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "기타 설정",
          style: style.copyWith(fontSize: 20, color: Colors.white),
        ),
        backgroundColor: PRIMARY_COLOR, // 상단바 색상
        iconTheme: IconThemeData(color: Colors.white), // 아이콘 색상 변경
      ),
      drawer: const ManagerDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),

            _buildSettingsCard(
              context,
              title: "학기 일정 관리",
              subtitle: "학기 일정 및 휴원 기간을 관리합니다.",
              icon: Icons.calendar_today,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SemesterManagementPage()),
                ); // 이동할 경로 설정
              },
            ),

            const SizedBox(height: 15),

            _buildSettingsCard(
              context,
              title: "예약 금지 설정",
              subtitle: "특정 시간에 수업 예약이 불가능하도록 설정합니다.",
              icon: Icons.block,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => BanTimeManagementPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 공통 사용 카드 위젯
  Widget _buildSettingsCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        leading: Icon(icon, size: 30, color: PRIMARY_COLOR),
        title: Text(
          title,
          style: style.copyWith(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: style.copyWith(fontSize: 14, color: Colors.grey[700]),
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey[600]),
        onTap: onTap,
      ),
    );
  }
}
