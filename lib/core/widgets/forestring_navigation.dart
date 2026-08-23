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
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      elevation: 0,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontFamily: 'OpenSans',
          fontSize: 23,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.1,
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
      width: MediaQuery.of(context).size.width * 0.78,
      backgroundColor: neutralIvory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 42, 18, 22),
              decoration: const BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$displayName 선생님',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'ELAND',
                      fontSize: 27,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        '💚',
                        style: TextStyle(fontSize: 19),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        roleLabel,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'ELAND',
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ListTile(
                  minTileHeight: 58,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(
                    item.icon,
                    color: primaryColor,
                    size: 27,
                  ),
                  title: Text(
                    item.label,
                    style: forestringTextStyle.copyWith(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: primaryColor,
                    size: 28,
                  ),
                  onTap: item.onTap,
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: ListTile(
                minTileHeight: 58,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(
                  Icons.logout,
                  color: primaryColor,
                  size: 27,
                ),
                title: Text(
                  '로그 아웃',
                  style: forestringTextStyle.copyWith(
                    color: Colors.redAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: primaryColor,
                  size: 28,
                ),
                onTap: onLogout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
