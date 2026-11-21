/// 会话目标（goal）投影模型与动作入参。
///
/// 协议事实来源：dsh-remote-bridge `src/host/ws-goals.ts`（读 `goal` 帧取
/// 会话投影 `goal`；写 `goal-edit/pause/resume/clear` 代理内核 goals Remote，
/// 必须带 compare-and-set 的 `ref:{id,revision}`），字段形状对照
/// dsh-go `packages/dsh_client/lib/src/goals_api.dart`（GoalSnapshot /
/// GoalProjection / GoalView）。
///
/// 目标由内核的 create_goal / update_goal 工具写投影，App 只读投影、发动作，
/// 不自己维护轮次。
library;

/// 目标的持久阶段（wire 值与内核一致）。
enum GoalPhase {
  active('active'),
  paused('paused'),
  blocked('blocked'),
  complete('complete');

  const GoalPhase(this.wire);

  final String wire;

  static GoalPhase? fromWire(Object? v) {
    for (final p in values) {
      if (p.wire == v) return p;
    }
    return null;
  }
}

/// compare-and-set 标识：每次持久修改 revision +1。
class GoalRef {
  const GoalRef(this.id, this.revision);

  final String id;
  final int revision;

  static GoalRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final revision = json['revision'];
    if (id is! String || id.isEmpty || revision is! int) return null;
    return GoalRef(id, revision);
  }

  Map<String, dynamic> toJson() => {'id': id, 'revision': revision};

  @override
  bool operator ==(Object other) =>
      other is GoalRef && other.id == id && other.revision == revision;

  @override
  int get hashCode => Object.hash(id, revision);

  @override
  String toString() => 'GoalRef($id@$revision)';
}

/// 目标受阻原因（phase == blocked 才有）。
class GoalBlockReason {
  const GoalBlockReason({required this.code, required this.message});

  final String code;
  final String message;

  static GoalBlockReason? fromJson(Object? json) {
    if (json is! Map) return null;
    final message = json['message'];
    if (message is! String || message.trim().isEmpty) return null;
    final code = json['code'];
    return GoalBlockReason(
      code: code is String ? code : '',
      message: message,
    );
  }
}

/// 一个持久目标版本。
class GoalSnapshot {
  const GoalSnapshot({
    required this.id,
    required this.revision,
    required this.objective,
    required this.phase,
    required this.maxGoalRounds,
    this.blockedReason,
  });

  final String id;
  final int revision;
  final String objective;
  final GoalPhase phase;
  final int maxGoalRounds;
  final GoalBlockReason? blockedReason;

  GoalRef get ref => GoalRef(id, revision);

  static GoalSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final ref = GoalRef.fromJson(json);
    final objective = json['objective'];
    final phase = GoalPhase.fromWire(json['phase']);
    if (ref == null || objective is! String || phase == null) return null;
    final max = json['maxGoalRounds'];
    return GoalSnapshot(
      id: ref.id,
      revision: ref.revision,
      objective: objective,
      phase: phase,
      maxGoalRounds: max is int ? max : 0,
      blockedReason: phase == GoalPhase.blocked
          ? GoalBlockReason.fromJson(json['blockedReason'])
          : null,
    );
  }
}

/// 会话投影 `goal` 的值：当前目标 + 已开始的续跑轮次。
class GoalProjection {
  const GoalProjection({required this.goal, this.roundsStarted = 0});

  final GoalSnapshot goal;

  /// 已开始的自动续跑轮次（0 = 尚未续跑）。
  final int roundsStarted;

  GoalRef get ref => goal.ref;

  static GoalProjection? fromJson(Object? json) {
    if (json is! Map) return null;
    final goal = GoalSnapshot.fromJson(json['goal']);
    if (goal == null) return null;
    final rounds = json['roundsStarted'];
    return GoalProjection(
      goal: goal,
      roundsStarted: rounds is int ? rounds : 0,
    );
  }
}

/// 从会话投影（history 应答的 `projections`，形如 `{values: {...}}`）取目标。
/// 缺失或形状不认识 → null（列表/会话照常显示，不报错）。
GoalProjection? goalOf(Map<String, dynamic>? projections) {
  if (projections == null) return null;
  final values = projections['values'];
  final bag = values is Map ? values : projections;
  return GoalProjection.fromJson(bag['goal']);
}

/// 目标条上的一行摘要：目标文字的第一条非空行。
String goalHeadline(String objective) {
  for (final line in objective.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return objective.trim();
}

/// 状态词的统一口径（目标条与操作面板共用）。
String goalPhaseLabel(GoalPhase phase) => switch (phase) {
  GoalPhase.active => '进行中',
  GoalPhase.paused => '已暂停',
  GoalPhase.blocked => '受阻',
  GoalPhase.complete => '已完成',
};

/// 目标条右侧的状态词：正常进行不写（只留目标），异常/暂停才显式标注。
String? goalStateLabel(GoalProjection goal) => switch (goal.goal.phase) {
  GoalPhase.active => null,
  GoalPhase.paused => '已暂停',
  GoalPhase.blocked => '受阻',
  GoalPhase.complete => '已完成',
};

/// 面板状态行：`已暂停 · 第 3 / 256 轮`（轮次为 0 时不带轮次段）。
String goalStatusLine(GoalProjection goal) {
  final rounds = goal.roundsStarted;
  final max = goal.goal.maxGoalRounds;
  final status = goalPhaseLabel(goal.goal.phase);
  if (rounds <= 0) return status;
  return max > 0 ? '$status · 第 $rounds / $max 轮' : '$status · 第 $rounds 轮';
}

/// 现在能不能暂停：只有进行中的目标可以暂停（已暂停/受阻/完成都不行）。
bool goalCanPause(GoalProjection goal) => goal.goal.phase == GoalPhase.active;

/// 现在能不能继续：暂停的目标可以恢复。
bool goalCanResume(GoalProjection goal) => goal.goal.phase == GoalPhase.paused;
