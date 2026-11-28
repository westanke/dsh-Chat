/// 后台任务（jobs）协议模型 + 会话级控制器。
///
/// 协议事实来源：dsh-remote-bridge `src/host/ws-jobs.ts`、
/// `docs/project/API.md`「后台任务」段（约 1056-1113 行）。
///
/// 三种请求帧（都回 `data.requestId`）：
/// - `job-list`   → `{sessionId, jobs:[JobInfo]}`（与 REST GET …/jobs 同形）
/// - `job-output` → `{jobId, output, nextCursor, truncated}`（cursor 省略 = 从最旧保留字节开始）
/// - `job-kill`   → `{jobId, killed}`（killed=true 只表示**请求已受理**，任务可能还在收尾）
///
/// 推送不占新 kind，走既有 `event` 帧的 `chat.job.updated`（非终态）与
/// `chat.job.finished`（终态 completed/killed/failed）。桥上**没有回放**：
/// 重连（`GatewayState.ready`）后必须重新拉一次 job-list 才有基线。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gateway.dart';

/// 桥侧任务状态（`JobInfo.status` 的线值）。
///
/// [unknown] 是防御口：桥只发前五种，遇到未登记状态时按「已结束」归组，
/// 而不是让它永远占着「运行中」的计数。
enum JobStatus {
  running('running', '运行中'),
  stopping('stopping', '停止中'),
  completed('completed', '已完成'),
  killed('killed', '已终止'),
  failed('failed', '失败'),
  unknown('unknown', '未知');

  const JobStatus(this.wire, this.label);

  /// 协议线值。
  final String wire;

  /// 中文状态名（面板展示用）。
  final String label;

  static JobStatus fromWire(Object? raw) {
    final value = raw is String ? raw : '';
    for (final s in JobStatus.values) {
      if (s.wire == value) return s;
    }
    return JobStatus.unknown;
  }

  /// 终态：桥不再为它推任何帧（completed / killed / failed）。
  bool get isTerminal => this == completed || this == killed || this == failed;

  /// 还在跑（含「停止中」：kill 已受理、进程尚未退出）。
  bool get isLive => this == running || this == stopping;
}

/// 面板分组用的三态状态机：运行中 / 已结束 / 失败。
///
/// 与 [JobStatus] 分开是有意的：线值是协议事实（五种），分组是 UI 口径
/// （三种）。`stopping` 仍占运行中计数，`unknown` 不占。
enum JobPhase { running, finished, failed }

/// 一条后台任务（`job-list` 的 `jobs[]`，与 REST 行同形）。
///
/// 可空字段桥侧**整键省略**（不是 null）：`owner` 无主任务、
/// `progress` 终态清空、`detail` 只有终态才带原因、`finishedAt` 未结束没有。
class JobInfo {
  const JobInfo({
    required this.id,
    required this.kind,
    required this.label,
    this.owner,
    required this.status,
    this.progress,
    this.detail,
    required this.startedAt,
    this.finishedAt,
  });

  factory JobInfo.fromJson(Map<String, dynamic> json) => JobInfo(
    id: json['id'] is String ? json['id'] as String : '',
    kind: json['kind'] is String ? json['kind'] as String : '',
    label: json['label'] is String ? json['label'] as String : '',
    owner: json['owner'] is String ? json['owner'] as String : null,
    status: JobStatus.fromWire(json['status']),
    progress: json['progress'] is String ? json['progress'] as String : null,
    detail: json['detail'] is String ? json['detail'] as String : null,
    startedAt: _intOf(json['startedAt']) ?? 0,
    finishedAt: _intOf(json['finishedAt']),
  );

  final String id;

  /// 任务种类（桥原样透传，如 `bash` / `subagent`）。
  final String kind;

  /// 任务标题（列表主文案）。
  final String label;

  /// 发起者；无主（全局）任务没有这个键。
  final String? owner;

  final JobStatus status;

  /// 运行中的最新进度行；终态时桥清空。
  final String? progress;

  /// 终态原因（如 `exit code: 3`）；只有终态才有。
  final String? detail;

  /// 开始时间（epoch ms）。
  final int startedAt;

  /// 结束时间（epoch ms）；未结束没有。
  final int? finishedAt;

  JobPhase get phase => switch (status) {
    JobStatus.running || JobStatus.stopping => JobPhase.running,
    JobStatus.failed => JobPhase.failed,
    JobStatus.completed ||
    JobStatus.killed ||
    JobStatus.unknown => JobPhase.finished,
  };

  bool get isLive => phase == JobPhase.running;

  /// 列表第二行的补充细节：进度 → 终态原因，都没有就空串。
  String get progressLine {
    final p = progress?.trim();
    if (p != null && p.isNotEmpty) return p;
    final d = detail?.trim();
    return d ?? '';
  }

  JobInfo copyWith({
    JobStatus? status,
    String? progress,
    bool clearProgress = false,
    String? detail,
    int? finishedAt,
  }) => JobInfo(
    id: id,
    kind: kind,
    label: label,
    owner: owner,
    status: status ?? this.status,
    progress: clearProgress ? null : (progress ?? this.progress),
    detail: detail ?? this.detail,
    startedAt: startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
  );

  /// 显式序列化：只写协议里存在的键，不把 null 摊成 `"owner": null`。
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'label': label,
    if (owner != null) 'owner': owner,
    'status': status.wire,
    if (progress != null) 'progress': progress,
    if (detail != null) 'detail': detail,
    'startedAt': startedAt,
    if (finishedAt != null) 'finishedAt': finishedAt,
  };
}

/// 一次 `job-output` 应答。
class JobOutput {
  const JobOutput({
    required this.jobId,
    required this.output,
    required this.nextCursor,
    required this.truncated,
  });

  factory JobOutput.fromJson(Map<String, dynamic> json) => JobOutput(
    jobId: json['jobId'] is String ? json['jobId'] as String : '',
    output: json['output'] is String ? json['output'] as String : '',
    nextCursor: _intOf(json['nextCursor']) ?? 0,
    truncated: json['truncated'] == true,
  );

  final String jobId;

  /// 输出正文（与 REST `text` 等价）。
  final String output;

  /// 下一次续读的字节游标（与 REST `next` 等价）。
  final int nextCursor;

  /// 是否因为保留缓冲已被裁剪（与 REST `lossy` 等价）：为真时较早的部分
  /// 永远拿不回来了，UI 要给「已截断」提示。
  final bool truncated;

  bool get isEmpty => output.isEmpty;

  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    'output': output,
    'nextCursor': nextCursor,
    'truncated': truncated,
  };
}

/// 任务列表 / 输出的协议错误 → 用户能照着做的一句话。
String jobErrorMessage(RequestException e) => switch (e.code) {
  'NOT_FOUND' || 'JOB_NOT_FOUND' => '任务不存在，可能已被清理',
  'SESSION_NOT_FOUND' => '会话不存在或无权访问',
  'UPSTREAM_UNAVAILABLE' => '桥端任务服务暂时不可用，请稍后重试',
  'MISSING_PARAMS' || 'BAD_REQUEST' => '请求参数不正确（${e.message}）',
  'NOT_CONNECTED' => '连接未建立，请检查网络后重试',
  'TIMEOUT' => '请求超时，请重试',
  'NO_SESSION' => '尚未选择会话',
  _ => e.message.isEmpty ? '任务操作失败（${e.code}）' : e.message,
};

/// 任务时间的人话展示：今天 14:05 / 昨天 09:12 / 11月27日 18:40。
///
/// [now] 由调用方给，纯函数便于单测（不读全局时钟）。
String formatJobTime(int epochMs, {DateTime? now}) {
  if (epochMs <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final n = now ?? DateTime.now();
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今天 $hm';
  if (diff == 1) return '昨天 $hm';
  if (t.year == n.year) return '${t.month}月${t.day}日 $hm';
  return '${t.year}年${t.month}月${t.day}日 $hm';
}

int? _intOf(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}

/// 一个会话的后台任务列表：拉取、接收推送、kill、重连后重建基线。
///
/// 一个会话一个实例（`ChatPage` 持有）；换会话调 [bind] 而不是重建，
/// 免得 capsule 引用旧对象。所有网络错误收敛到 [error]（中文人话），
/// 网络调用本身只抛 [RequestException]。
class JobsController extends ChangeNotifier {
  JobsController({
    required this.gateway,
    String? sessionId,
    this.refreshDebounce = const Duration(milliseconds: 400),
  }) {
    _pushSub = gateway.jobPushes.listen(_onPush);
    _stateSub = gateway.state.listen(_onState);
    bind(sessionId);
  }

  final GatewayClient gateway;

  /// 收到「未知任务」推送时防抖重拉列表的等待。
  final Duration refreshDebounce;

  StreamSubscription<JobPush>? _pushSub;
  StreamSubscription<GatewayState>? _stateSub;
  Timer? _refreshTimer;
  bool _disposed = false;
  bool _refreshing = false;
  bool _refreshQueued = false;

  String? _sessionId;
  Map<String, JobInfo> _jobs = const {};
  bool _loaded = false;
  bool _loading = false;
  String? _error;

  /// 当前绑定的会话；null = 未绑定（列表恒为空）。
  String? get sessionId => _sessionId;

  /// 是否至少成功拉取过一次（区分「空列表」与「还没拉」）。
  bool get isLoaded => _loaded;

  bool get loading => _loading;

  /// 最近一次拉取的错误（中文人话）；成功后清空。
  String? get error => _error;

  /// 全部任务：运行中在前（按开始时间正序，避免行跳动），已结束在后
  /// （按结束/开始时间倒序，新的在上面）。
  List<JobInfo> get jobs {
    final live = <JobInfo>[];
    final done = <JobInfo>[];
    for (final job in _jobs.values) {
      (job.isLive ? live : done).add(job);
    }
    live.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    done.sort((a, b) {
      final fa = a.finishedAt ?? a.startedAt;
      final fb = b.finishedAt ?? b.startedAt;
      return fb.compareTo(fa);
    });
    return [...live, ...done];
  }

  List<JobInfo> get runningJobs =>
      jobs.where((j) => j.phase == JobPhase.running).toList(growable: false);

  List<JobInfo> get finishedJobs =>
      jobs.where((j) => j.phase != JobPhase.running).toList(growable: false);

  /// 运行中数量（含「停止中」）；capsule 只认这个数。
  int get runningCount => _jobs.values.where((j) => j.isLive).length;

  JobInfo? jobById(String id) => _jobs[id];

  /// 绑定会话：清空旧列表，连接已就绪时立刻拉一次基线。
  ///
  /// 断线时只清空、不发请求——重连由 [GatewayState.ready] 触发重拉。
  void bind(String? sessionId) {
    final next = (sessionId == null || sessionId.isEmpty) ? null : sessionId;
    if (next == _sessionId) return;
    _sessionId = next;
    _jobs = const {};
    _loaded = false;
    _loading = false;
    _error = null;
    _refreshTimer?.cancel();
    _notify();
    if (next != null && gateway.currentState == GatewayState.ready) {
      unawaited(refresh());
    }
  }

  /// 拉一次 job-list 基线。并发调用合并：在途时只记一次「完了再来」。
  Future<void> refresh() async {
    if (_disposed) return;
    final sid = _sessionId;
    if (sid == null) return;
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    _loading = true;
    _notify();
    try {
      final data = await gateway.request('job-list', {'sessionId': sid});
      if (_disposed || sid != _sessionId) return;
      final rawList = data['jobs'];
      final parsed = <String, JobInfo>{};
      if (rawList is List) {
        for (final raw in rawList) {
          if (raw is Map) {
            final job = JobInfo.fromJson(Map<String, dynamic>.from(raw));
            if (job.id.isNotEmpty) parsed[job.id] = job;
          }
        }
      }
      _jobs = parsed;
      _loaded = true;
      _error = null;
    } on RequestException catch (e) {
      if (!_disposed && sid == _sessionId) _error = jobErrorMessage(e);
    } catch (e) {
      if (!_disposed && sid == _sessionId) _error = '任务列表加载失败：$e';
    } finally {
      _refreshing = false;
      _loading = false;
      _notify();
      if (_refreshQueued && !_disposed) {
        _refreshQueued = false;
        unawaited(refresh());
      }
    }
  }

  /// 读任务输出（`cursor` 省略 = 从最旧保留字节开始）。
  ///
  /// 大任务输出可能上百 KB，用 60s 超时而不是通用的 30s。
  Future<JobOutput> output(String jobId, {int? cursor}) async {
    final sid = _sessionId;
    if (sid == null) throw RequestException('NO_SESSION', '尚未选择会话');
    final data = await gateway.requestWithTimeout('job-output', {
      'sessionId': sid,
      'jobId': jobId,
      'cursor': ?cursor,
    }, const Duration(seconds: 60));
    return JobOutput.fromJson({'jobId': jobId, ...data});
  }

  /// 请求停止任务。返回 true = 桥已受理（任务进入 stopping，等推送收尾）。
  ///
  /// 已结束的任务桥回 `killed:false`，这不是错误，UI 说「任务已经结束」即可。
  Future<bool> kill(String jobId) async {
    final sid = _sessionId;
    if (sid == null) return false;
    final data = await gateway.request('job-kill', {
      'sessionId': sid,
      'jobId': jobId,
    });
    final killed = data['killed'] == true;
    final job = _jobs[jobId];
    if (killed &&
        job != null &&
        job.isLive &&
        job.status != JobStatus.stopping) {
      _jobs = {..._jobs, jobId: job.copyWith(status: JobStatus.stopping)};
      _notify();
    }
    return killed;
  }

  void _onState(GatewayState state) {
    // 桥侧推送没有回放：每次（重）连上都要重新拉基线。
    if (state == GatewayState.ready && _sessionId != null) {
      unawaited(refresh());
    }
  }

  void _onPush(JobPush push) {
    _applyPush(
      sessionId: push.sessionId,
      jobId: push.jobId,
      status: push.status,
      progress: push.progress,
      finishedAt: push.finishedAt,
      terminal: push.terminal,
    );
  }

  void _applyPush({
    required String sessionId,
    required String jobId,
    required String status,
    required String? progress,
    required int? finishedAt,
    required bool terminal,
  }) {
    if (_disposed || sessionId != _sessionId) return;
    final job = _jobs[jobId];
    if (job == null) {
      // 列表还没包含它（例如刚启动的任务）：补一次基线，别指望推送带全字段。
      _scheduleRefresh();
      return;
    }
    final next = JobStatus.fromWire(status);
    final cleared = terminal || next.isTerminal;
    _jobs = {
      ..._jobs,
      jobId: job.copyWith(
        status: next,
        progress: progress,
        clearProgress: cleared,
        finishedAt: cleared ? (finishedAt ?? job.finishedAt) : finishedAt,
      ),
    };
    _notify();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(refreshDebounce, () {
      if (!_disposed) unawaited(refresh());
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    unawaited(_pushSub?.cancel());
    unawaited(_stateSub?.cancel());
    super.dispose();
  }
}
