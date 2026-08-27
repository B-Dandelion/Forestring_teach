import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/domain/current_profile.dart';
import '../../branches/data/branch_repository.dart';
import '../../branches/domain/academy_branch.dart';
import '../data/student_repository.dart';

class CreateStudentSmokePage extends StatefulWidget {
  const CreateStudentSmokePage({
    required this.actorProfile,
    super.key,
  });

  final CurrentProfile actorProfile;

  @override
  State<CreateStudentSmokePage> createState() =>
      _CreateStudentSmokePageState();
}

class _CreateStudentSmokePageState
    extends State<CreateStudentSmokePage> {
  final _nameController =
      TextEditingController();

  final _pinController =
      TextEditingController();

  final _repository =
      StudentRepository();

  final _branchRepository =
      BranchRepository();

  List<AcademyBranch> _branches =
      const [];

  String? _branchId;

  StudentType _studentType =
      StudentType.regular;

  bool _isLoadingBranches = true;
  bool _isLoading = false;

  String? _resultMessage;

  bool get _isMaster =>
      widget.actorProfile.role ==
      AppRole.master;

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
      final branches =
          await _branchRepository
              .fetchBranches();

      if (!mounted) {
        return;
      }

      final activeBranches =
          branches
              .where(
                (branch) =>
                    branch.isActive,
              )
              .toList();

      String? selectedBranchId;

      if (_isMaster) {
        if (activeBranches.isNotEmpty) {
          selectedBranchId =
              activeBranches.first.id;
        }
      } else {
        selectedBranchId =
            widget.actorProfile.branchId;

        if (selectedBranchId != null &&
            !activeBranches.any(
              (branch) =>
                  branch.id ==
                  selectedBranchId,
            )) {
          selectedBranchId = null;
        }
      }

      setState(() {
        _branches =
            activeBranches;
        _branchId =
            selectedBranchId;
        _resultMessage = null;
      });
    } on BranchFailure catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _resultMessage =
            '지점 목록 조회 실패\n'
            '${error.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingBranches =
              false;
        });
      }
    }
  }

  Future<void> _createStudent() async {
    FocusManager
        .instance
        .primaryFocus
        ?.unfocus();

    final branchId =
        _branchId;

    if (branchId == null ||
        branchId.isEmpty) {
      setState(() {
        _resultMessage =
            '지점을 선택해주세요.';
      });

      return;
    }

    setState(() {
      _isLoading = true;
      _resultMessage = null;
    });

    try {
      final student =
          await _repository
              .createStudent(
        name:
            _nameController.text,
        pin:
            _pinController.text,
        branchId:
            branchId,
        studentType:
            _studentType,
      );

      if (!mounted) {
        return;
      }

      String? branchName;

      for (final branch
          in _branches) {
        if (branch.id ==
            branchId) {
          branchName =
              branch.name;
          break;
        }
      }

      setState(() {
        _resultMessage =
            '생성 성공\n'
            '지점: ${branchName ?? '-'}\n'
            '학생: ${student.displayName}\n'
            '유형: ${student.studentType.label}\n'
            '${student.id}';

        _pinController.clear();
      });
    } on StudentFailure catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _resultMessage =
            '생성 실패\n'
            '${error.message}';
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
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '학생 생성 Smoke Test',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding:
              const EdgeInsets.all(
            24,
          ),
          children: [
            const Text(
              '실제 Supabase DB에 학생 계정을 생성합니다.',
            ),

            const SizedBox(
              height: 24,
            ),

            if (_isLoadingBranches)
              const Center(
                child:
                    CircularProgressIndicator(),
              )
            else if (_branches.isEmpty)
              const Text(
                '사용 가능한 지점이 없습니다.',
              )
            else
              DropdownButtonFormField<
                  String>(
                initialValue: _branchId,
                decoration:
                    const InputDecoration(
                  labelText: '지점',
                  border:
                      OutlineInputBorder(),
                ),
                items: _branches
                    .map(
                      (branch) =>
                          DropdownMenuItem<
                              String>(
                        value:
                            branch.id,
                        child: Text(
                          branch.name,
                        ),
                      ),
                    )
                    .toList(),
                onChanged:
                    _isMaster
                        ? (value) {
                            setState(() {
                              _branchId =
                                  value;
                            });
                          }
                        : null,
              ),

            if (!_isMaster) ...[
              const SizedBox(
                height: 8,
              ),
              const Text(
                '지점 관리자는 본인 지점에만 학생을 등록할 수 있습니다.',
              ),
            ],

            const SizedBox(
              height: 16,
            ),

            TextField(
              controller:
                  _nameController,
              decoration:
                  const InputDecoration(
                labelText: '학생 이름',
                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(
              height: 16,
            ),

            TextField(
              controller:
                  _pinController,
              keyboardType:
                  TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [
                FilteringTextInputFormatter
                    .digitsOnly,
                LengthLimitingTextInputFormatter(
                  4,
                ),
              ],
              decoration:
                  const InputDecoration(
                labelText: '4자리 PIN',
                border:
                    OutlineInputBorder(),
              ),
            ),

            const SizedBox(
              height: 8,
            ),

            DropdownButtonFormField<
                StudentType>(
              initialValue: _studentType,
              decoration:
                  const InputDecoration(
                labelText: '학생 유형',
                border:
                    OutlineInputBorder(),
              ),
              items: StudentType.values
                  .map(
                    (type) =>
                        DropdownMenuItem<
                            StudentType>(
                      value: type,
                      child: Text(
                        type.label,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _studentType =
                      value;
                });
              },
            ),

            const SizedBox(
              height: 8,
            ),

            Text(
              _studentType ==
                      StudentType.regular
                  ? '정규 학생: 이후 담당 선생님과 반복 수업 시간표를 설정합니다.'
                  : '자율 예약 학생: 정규 반복 시간표 없이 필요할 때 수업을 예약합니다.',
            ),

            const SizedBox(
              height: 24,
            ),

            FilledButton(
              onPressed:
                  _isLoading ||
                          _isLoadingBranches ||
                          _branchId == null
                      ? null
                      : _createStudent,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      '테스트 학생 생성',
                    ),
            ),

            if (_resultMessage !=
                null) ...[
              const SizedBox(
                height: 24,
              ),
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
