import 'package:flutter/material.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../auth/domain/current_profile.dart';
import '../data/branch_repository.dart';
import '../domain/academy_branch.dart';

class BranchManagementPage extends StatefulWidget {
  const BranchManagementPage({
    super.key,
    required this.profile,
  });

  final CurrentProfile profile;

  @override
  State<BranchManagementPage> createState() => _BranchManagementPageState();
}

class _BranchManagementPageState extends State<BranchManagementPage> {
  final _repository = BranchRepository();

  List<AcademyBranch> _branches = const [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final branches = await _repository.fetchBranches();

      if (!mounted) {
        return;
      }

      setState(() {
        _branches = branches;
      });
    } on BranchFailure catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCreateDialog() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: neutralIvory,
          title: Text(
            '지점 추가',
            style: forestringTextStyle.copyWith(
              color: primaryColor,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            style: forestringTextStyle,
            decoration: const InputDecoration(
              labelText: '지점명',
              hintText: '예: 포레스트링 키즈',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              Navigator.of(dialogContext).pop(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                '취소',
                style: forestringTextStyle.copyWith(
                  color: Colors.black54,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text);
              },
              child: Text(
                '추가',
                style: forestringTextStyle.copyWith(
                  color: primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (name == null || name.trim().isEmpty) {
      return;
    }

    try {
      await _repository.createBranch(name: name);
      await _load();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('지점을 추가했습니다.'),
        ),
      );
    } on BranchFailure catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: const ForestringAppBar(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: Text(
          '지점 추가',
          style: forestringTextStyle.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new),
                    color: primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '지점 관리',
                    style: forestringTextStyle.copyWith(
                      color: primaryColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: forestringTextStyle,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _load,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    if (_branches.isEmpty) {
      return Center(
        child: Text(
          '등록된 지점이 없습니다.',
          style: forestringTextStyle,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 100),
        itemCount: _branches.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final branch = _branches[index];

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.28),
              ),
            ),
            child: ListTile(
              minTileHeight: 72,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: primaryColor,
                ),
              ),
              title: Text(
                branch.name,
                style: forestringTextStyle.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                branch.isActive ? '운영 중' : '비활성',
                style: forestringTextStyle.copyWith(
                  fontSize: 13,
                  color: branch.isActive ? secondaryColor : Colors.black45,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: primaryColor,
              ),
            ),
          );
        },
      ),
    );
  }
}
