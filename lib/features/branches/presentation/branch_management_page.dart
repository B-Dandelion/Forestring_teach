import 'package:flutter/material.dart';

import '../data/branch_repository.dart';
import '../domain/academy_branch.dart';

class BranchManagementPage extends StatefulWidget {
  const BranchManagementPage({
    super.key,
  });

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
    String branchName = '';

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '지점 추가',
          ),
          content: TextField(
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '지점명',
              hintText: '예: 포레스트링 키즈',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              branchName = value;
            },
            onSubmitted: (value) {
              Navigator.of(dialogContext).pop(value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(branchName);
              },
              child: const Text('추가'),
            ),
          ],
        );
      },
    );

    if (name == null || name.trim().isEmpty) {
      return;
    }

    try {
      await _repository.createBranch(
        name: name,
      );

      await _load();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '지점을 추가했습니다.',
          ),
        ),
      );
    } on BranchFailure catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message,
          ),
        ),
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('지점 관리'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(
          Icons.add,
        ),
        label: const Text('지점 추가'),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
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
              ),
              const SizedBox(
                height: 16,
              ),
              FilledButton(
                onPressed: _load,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    if (_branches.isEmpty) {
      return const Center(
        child: Text(
          '등록된 지점이 없습니다.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          100,
        ),
        itemCount: _branches.length,
        separatorBuilder: (_, __) => const Divider(
          height: 1,
        ),
        itemBuilder: (
          context,
          index,
        ) {
          final branch = _branches[index];

          return ListTile(
            leading: Icon(
              branch.isActive ? Icons.storefront_outlined : Icons.storefront,
            ),
            title: Text(branch.name),
            subtitle: Text(
              branch.isActive ? '운영 중' : '비활성',
            ),
          );
        },
      ),
    );
  }
}
