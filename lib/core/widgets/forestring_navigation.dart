import 'package:flutter/material.dart';

import '../theme/forestring_theme.dart';

class ForestringDrawerItem {
  const ForestringDrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class ForestringAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const ForestringAppBar({
    super.key,
    this.title = 'FORESTRING',
    this.actions,
  });

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      title: Text(
        title,
        style: forestringTextStyle.copyWith(
          color: primaryColor,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      actions: actions,
    );
  }
}

class ForestringDrawer extends StatelessWidget {
  const ForestringDrawer({
    super.key,
    required this.displayName,
    required this.roleLabel,
    required this.items,
    required this.onLogout,
  });

  final String displayName;
  final String roleLabel;
  final List<ForestringDrawerItem> items;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              color: primaryColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FORESTRING',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'ELAND',
                      fontSize: 21,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$displayName님',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'ELAND',
                      fontSize: 17,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    roleLabel,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'ELAND',
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => ListTile(
                leading: Icon(
                  item.icon,
                  color: primaryColor,
                ),
                title: Text(
                  item.label,
                  style: forestringTextStyle.copyWith(
                    fontSize: 16,
                  ),
                ),
                onTap: item.onTap,
              ),
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.logout,
                color: Colors.redAccent,
              ),
              title: Text(
                '로그아웃',
                style: forestringTextStyle.copyWith(
                  fontSize: 16,
                ),
              ),
              onTap: onLogout,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
