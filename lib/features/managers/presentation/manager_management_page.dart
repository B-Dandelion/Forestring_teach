import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/forestring_theme.dart';
import '../../../core/widgets/forestring_navigation.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/manager_repository.dart';
import 'manager_create_page.dart';
import 'manager_departure_page.dart';

class ManagerManagementPage extends StatefulWidget {
  const ManagerManagementPage({super.key});

  @override
  State<ManagerManagementPage> createState() =>
      _ManagerManagementPageState();
}

class _ManagerManagementPageState extends State<ManagerManagementPage> {
  static const _allBranches = '__all__';

  final _repository = ManagerRepository();
  final _branchRepository = BranchRepository();
  final _searchController = TextEditingController();

  List<ManagedManager> _managers = const [];
  List<AcademyBranch> _branches = const [];
  String _branchFilter = _allBranches;
  String _statusFilter = 'active';
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _repository.fetchManagers(),
        _branchRepository.fetchBranches(),
      ]);
      if (!mounted) return;

      final branches = (results[1] as List<AcademyBranch>).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _managers = results[0] as List<ManagedManager>;
        _branches = branches;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ManagerFailure
            ? error.message
            : '지점장 정보를 불러오지 못했습니다.\n$error';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ManagedManager> get _visibleManagers {
    final query = _searchController.text.trim().toLowerCase();
    return _managers.where((manager) {
      if (_branchFilter != _allBranches && manager.branchId != _branchFilter) {
        return false;
      }
      if (_statusFilter == 'active' && !manager.isActive) return false;
      if (_statusFilter == 'departed' && manager.isActive) return false;
      if (query.isEmpty) return true;
      return manager.displayName.toLowerCase().contains(query) ||
          manager.branchName.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ManagerCreatePage()),
    );
    if (created == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지점장을 등록했습니다.')),
      );
    }
  }

  Future<void> _openDetails(ManagedManager manager) async {
    var current = manager;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, setPageState) {
            Future<void> runAction(
              Future<void> Function(ManagedManager) action, {
              bool refresh = false,
            }) async {
              await action(current);
              if (!refresh || !mounted || !pageContext.mounted) return;

              await _load();
              if (!mounted || !pageContext.mounted) return;

              ManagedManager? updated;
              for (final item in _managers) {
                if (item.id == current.id) {
                  updated = item;
                  break;
                }
              }

              if (updated == null) {
                Navigator.of(pageContext).pop();
                return;
              }
              setPageState(() => current = updated!);
            }

            return Scaffold(
              backgroundColor: neutralIvory,
              appBar: const ForestringAppBar(title: '지점장 관리'),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                  children: [
                    Text(
                      current.displayName,
                      style: forestringTextStyle.copyWith(
                        color: primaryColor,
                        fontSize: 23,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      current.branchName,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (current.isActive) ...[
                      _actionSection(
                        title: '계정 관리',
                        actions: [
                          _actionButton(
                            icon: Icons.drive_file_rename_outline,
                            label: '이름 수정',
                            onPressed: () => runAction(
                              _editName,
                              refresh: true,
                            ),
                          ),
                          _actionButton(
                            icon: Icons.lock_reset_outlined,
                            label: 'PIN 재설정',
                            onPressed: () => runAction(_resetPin),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _actionSection(
                        title: '지점 관리',
                        actions: [
                          _actionButton(
                            icon: Icons.store_mall_directory_outlined,
                            label: '담당 지점 변경',
                            onPressed: current.hasScheduledWithdrawal
                                ? null
                                : () => runAction(
                                      _changeBranch,
                                      refresh: true,
                                    ),
                          ),
                        ],
                      ),
                      if (current.hasScheduledWithdrawal) ...[
                        const SizedBox(height: 8),
                        Text(
                          '퇴사 예정인 지점장은 담당 지점을 변경할 수 없습니다.',
                          style: forestringTextStyle.copyWith(
                            color: Colors.black45,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 14),
                    _actionSection(
                      title: '재직 관리',
                      actions: [
                        _actionButton(
                          icon: current.isActive
                              ? Icons.person_off_outlined
                              : Icons.badge_outlined,
                          label: current.isActive ? '퇴사 관리' : '퇴사 정보',
                          color: Colors.red.shade700,
                          onPressed: () => runAction(
                            _openDeparture,
                            refresh: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    if (mounted) await _load();
  }

  Future<void> _editName(ManagedManager manager) async {
    final controller = TextEditingController(text: manager.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: const Text('지점장 이름 수정'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '이름',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || name.trim() == manager.displayName) {
      return;
    }

    await _runAction(
      () => _repository.updateManagerName(
        managerId: manager.id,
        name: name,
      ),
      successMessage: '이름을 변경했습니다.',
    );
  }

  Future<void> _resetPin(ManagedManager manager) async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: const Text('PIN 재설정'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          decoration: const InputDecoration(
            labelText: '새 4자리 PIN',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('재설정'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pin == null) return;

    await _runAction(
      () => _repository.resetManagerPin(
        managerId: manager.id,
        pin: pin,
      ),
      successMessage: 'PIN을 재설정했습니다.',
    );
  }

  Future<void> _changeBranch(ManagedManager manager) async {
    final activeBranches = _branches.where((branch) => branch.isActive).toList();
    if (activeBranches.isEmpty) {
      _showMessage('변경할 수 있는 운영 지점이 없습니다.');
      return;
    }

    var selectedId = manager.branchId;
    if (!activeBranches.any((branch) => branch.id == selectedId)) {
      selectedId = activeBranches.first.id;
    }

    final branchId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: neutralIvory,
          title: const Text('담당 지점 변경'),
          content: DropdownButtonFormField<String>(
            value: selectedId,
            decoration: const InputDecoration(
              labelText: '담당 지점',
              border: OutlineInputBorder(),
            ),
            items: activeBranches
                .map(
                  (branch) => DropdownMenuItem(
                    value: branch.id,
                    child: Text(branch.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setDialogState(() => selectedId = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(selectedId),
              child: const Text('변경'),
            ),
          ],
        ),
      ),
    );

    if (branchId == null || branchId == manager.branchId) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: neutralIvory,
        title: const Text('담당 지점 변경'),
        content: Text(
          '담당 지점을 변경할까요?\n\n'
          '지점장이 직접 수업을 담당 중이라면 학생 관계와 정규 일정, 예정 수업을 먼저 정리해야 합니다.',
          style: forestringTextStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: primaryColor),
            child: const Text('변경'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _runAction(
      () => _repository.changeManagerBranch(
        managerId: manager.id,
        branchId: branchId,
      ),
      successMessage: '담당 지점을 변경했습니다.',
    );
  }

  Future<void> _openDeparture(ManagedManager manager) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManagerDeparturePage(manager: manager),
      ),
    );
    if (changed == true && mounted) {
      await _load();
    }
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    try {
      await action();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } on ManagerFailure catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final managers = _visibleManagers;

    return Scaffold(
      backgroundColor: neutralIvory,
      appBar: ForestringAppBar(
        title: '지점장 관리',
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        onPressed: _loading ? null : _openCreate,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(
          '지점장 등록',
          style: forestringTextStyle.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
            children: [
              _filters(),
              const SizedBox(height: 14),
              if (_errorMessage != null) ...[
                _errorCard(_errorMessage!),
                const SizedBox(height: 12),
              ],
              if (_loading && _managers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (managers.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(
                    child: Text(
                      '조건에 맞는 지점장이 없습니다.',
                      style: forestringTextStyle.copyWith(color: Colors.black54),
                    ),
                  ),
                )
              else ...[
                Text(
                  '${managers.length}명',
                  style: forestringTextStyle.copyWith(
                    color: primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                ...managers.map(_managerCard),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '지점장 이름 검색',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _branchFilter,
          decoration: _filterDecoration('지점'),
          items: [
            const DropdownMenuItem(
              value: _allBranches,
              child: Text('전체 지점'),
            ),
            ..._branches.map(
              (branch) => DropdownMenuItem(
                value: branch.id,
                child: Text(branch.name),
              ),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _branchFilter = value);
          },
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _statusFilter,
          decoration: _filterDecoration('상태'),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('전체')),
            DropdownMenuItem(value: 'active', child: Text('재직')),
            DropdownMenuItem(value: 'departed', child: Text('퇴사')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _statusFilter = value);
          },
        ),
      ],
    );
  }

  InputDecoration _filterDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.18)),
      ),
    );
  }

  Widget _managerCard(ManagedManager manager) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: primaryColor.withValues(alpha: 0.16)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetails(manager),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            manager.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: forestringTextStyle.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusBadge(manager),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      manager.branchName,
                      overflow: TextOverflow.ellipsis,
                      style: forestringTextStyle.copyWith(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(ManagedManager manager) {
    final color = manager.isActive
        ? (manager.hasScheduledWithdrawal
            ? Colors.orange.shade700
            : primaryColor)
        : Colors.black45;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        manager.statusLabel,
        style: forestringTextStyle.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _actionSection({
    required String title,
    required List<Widget> actions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: forestringTextStyle.copyWith(
            color: primaryColor,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryColor.withValues(alpha: 0.16)),
          ),
          child: Column(children: actions),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
    Color? color,
  }) {
    final actionColor = color ?? primaryColor;
    return ListTile(
      leading: Icon(icon, color: onPressed == null ? Colors.black26 : actionColor),
      title: Text(
        label,
        style: forestringTextStyle.copyWith(
          color: onPressed == null ? Colors.black38 : Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: onPressed == null ? Colors.black26 : primaryColor,
      ),
      onTap: onPressed,
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: forestringTextStyle.copyWith(color: Colors.red.shade700),
      ),
    );
  }
}
