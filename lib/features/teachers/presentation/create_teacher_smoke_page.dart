import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/teacher_repository.dart';

class CreateTeacherSmokePage extends StatefulWidget {
  const CreateTeacherSmokePage({
    super.key,
  });

  @override
  State<CreateTeacherSmokePage> createState() => _CreateTeacherSmokePageState();
}

class _CreateTeacherSmokePageState extends State<CreateTeacherSmokePage> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();

  final _repository = TeacherRepository();
  final _branchRepository = BranchRepository();

  List<AcademyBranch> _branches = const [];

  String? _branchId;

  int _weekday = 1;

  TimeOfDay _startTime = const TimeOfDay(
    hour: 9,
    minute: 0,
  );

  TimeOfDay _endTime = const TimeOfDay(
    hour: 18,
    minute: 0,
  );

  bool _isLoading = false;
  bool _isLoadingBranches = true;

  String? _resultMessage;

  @override
  void initState() {
    super.initState();

    _loadBranches();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();

    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _isLoadingBranches = true;
    });

    try {
      final branches = await _branchRepository.fetchBranches();

      if (!mounted) {
        return;
      }

      final activeBranches = branches
          .where(
            (branch) => branch.isActive,
          )
          .toList();

      setState(() {
        _branches = activeBranches;

        if (activeBranches.isNotEmpty) {
          _branchId = activeBranches.first.id;
        }

        _resultMessage = null;
      });
    } on BranchFailure catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _resultMessage = '지점 목록 조회 실패\n${error.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBranches = false;
        });
      }
    }
  }

  String _formatTime(
    TimeOfDay value,
  ) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  bool _is15MinuteAligned(
    TimeOfDay value,
  ) {
    return value.minute % 15 == 0;
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _startTime = picked;
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _endTime = picked;
    });
  }

  Future<void> _createTeacher() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final branchId = _branchId;

    if (branchId == null || branchId.isEmpty) {
      setState(() {
        _resultMessage = '지점을 선택해주세요.';
      });

      return;
    }

    if (!_is15MinuteAligned(_startTime) || !_is15MinuteAligned(_endTime)) {
      setState(() {
        _resultMessage = '근무시간은 15분 단위로 선택해주세요.';
      });

      return;
    }

    final startMinutes = _startTime.hour * 60 + _startTime.minute;

    final endMinutes = _endTime.hour * 60 + _endTime.minute;

    if (startMinutes >= endMinutes) {
      setState(() {
        _resultMessage = '종료시간은 시작시간보다 뒤여야 합니다.';
      });

      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });

    try {
      final teacher = await _repository.createTeacher(
        name: _nameController.text,
        pin: _pinController.text,
        branchId: branchId,
        workHours: [
          TeacherWorkHourInput(
            weekday: _weekday,
            startTime: _formatTime(_startTime),
            endTime: _formatTime(_endTime),
          ),
        ],
      );

      if (!mounted) {
        return;
      }

      String? branchName;

      for (final branch in _branches) {
        if (branch.id == branchId) {
          branchName = branch.name;
          break;
        }
      }

      setState(() {
        _resultMessage = '생성 성공\n'
            '지점: ${branchName ?? '-'}\n'
            '선생님: ${teacher.displayName}\n'
            '${teacher.id}';

        _pinController.clear();
      });
    } on TeacherFailure catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _resultMessage = '생성 실패\n${error.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const weekdays = {
      1: '월요일',
      2: '화요일',
      3: '수요일',
      4: '목요일',
      5: '금요일',
      6: '토요일',
      7: '일요일',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '선생님 생성 Smoke Test',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '실제 Supabase DB에 테스트 선생님 계정을 생성합니다.',
            ),
            const SizedBox(height: 24),
            if (_isLoadingBranches)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_branches.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '등록된 활성 지점이 없습니다.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _loadBranches,
                    child: const Text(
                      '지점 다시 불러오기',
                    ),
                  ),
                ],
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _branchId,
                decoration: const InputDecoration(
                  labelText: '지점',
                  border: OutlineInputBorder(),
                ),
                items: _branches
                    .map(
                      (branch) => DropdownMenuItem<String>(
                        value: branch.id,
                        child: Text(branch.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _branchId = value;
                  });
                },
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '선생님 이름',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(
                  4,
                ),
              ],
              decoration: const InputDecoration(
                labelText: '4자리 PIN',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _weekday,
              decoration: const InputDecoration(
                labelText: '근무 요일',
                border: OutlineInputBorder(),
              ),
              items: weekdays.entries
                  .map(
                    (entry) => DropdownMenuItem<int>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _weekday = value;
                });
              },
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('시작시간'),
              subtitle: Text(
                _formatTime(_startTime),
              ),
              trailing: const Icon(
                Icons.access_time,
              ),
              onTap: _pickStartTime,
            ),
            ListTile(
              title: const Text('종료시간'),
              subtitle: Text(
                _formatTime(_endTime),
              ),
              trailing: const Icon(
                Icons.access_time,
              ),
              onTap: _pickEndTime,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isLoading || _isLoadingBranches || _branches.isEmpty
                  ? null
                  : _createTeacher,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      '테스트 선생님 생성',
                    ),
            ),
            if (_resultMessage != null) ...[
              const SizedBox(height: 24),
              SelectableText(
                _resultMessage!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
