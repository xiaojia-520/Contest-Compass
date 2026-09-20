import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.state});
  final AppState state;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? overview;
  bool loading = true;
  String? triggering;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final data = await widget.state.api.get('/admin/overview');
      overview = Map<String, dynamic>.from(data as Map);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> trigger(String type, String label) async {
    setState(() => triggering = type);
    try {
      await widget.state.api.post('/admin/jobs/$type');
      if (mounted) showSuccess(context, '$label已加入任务队列');
      await load();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => triggering = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading && overview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = overview ?? <String, dynamic>{};
    final jobs = data['recent_jobs'] as List<dynamic>? ?? [];
    final active = data['active_job'] as Map?;
    final schedules = Map<String, dynamic>.from(
      data['schedules'] as Map? ?? {},
    );
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width >= 1000 ? 56 : 22,
          vertical: 34,
        ),
        children: [
          SectionTitle(
            '后台任务',
            subtitle: '管理赛事增量抓取、每周全量校准与向量索引。',
            trailing: IconButton(
              tooltip: '刷新',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _MetricCard(
                label: 'Redis',
                value: data['redis_ok'] == true ? '正常' : '异常',
              ),
              _MetricCard(
                label: 'Worker',
                value: data['worker_ok'] == true ? '在线' : '离线',
              ),
              _MetricCard(
                label: '赛事总数',
                value: '${data['competition_total'] ?? '-'}',
              ),
              _MetricCard(
                label: '有效赛事',
                value: '${data['competition_eligible'] ?? '-'}',
              ),
              _MetricCard(
                label: '向量数量',
                value: '${data['vector_count'] ?? '-'}',
              ),
            ],
          ),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('自动调度', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _ScheduleRow(label: '增量抓取', value: schedules['incremental']),
                  _ScheduleRow(label: '全量校准', value: schedules['full']),
                  _ScheduleRow(label: '记录清理', value: schedules['cleanup']),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('手动操作', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    active == null
                        ? '当前没有运行中的维护任务。'
                        : '当前任务：${active['job_type']} · ${active['status']}',
                    style: const TextStyle(color: inkSoft),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _TaskButton(
                        label: '立即增量抓取',
                        icon: Icons.sync_rounded,
                        busy: triggering == 'incremental',
                        disabled: active != null || triggering != null,
                        onPressed: () => trigger('incremental', '增量抓取'),
                      ),
                      _TaskButton(
                        label: '立即全量校准',
                        icon: Icons.travel_explore_rounded,
                        busy: triggering == 'full',
                        disabled: active != null || triggering != null,
                        onPressed: () => trigger('full', '全量校准'),
                      ),
                      _TaskButton(
                        label: '重建向量索引',
                        icon: Icons.hub_outlined,
                        busy: triggering == 'reindex',
                        disabled: active != null || triggering != null,
                        onPressed: () => trigger('reindex', '索引重建'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text('最近运行记录', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (jobs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无任务记录'),
              ),
            )
          else
            ...jobs.map(
              (raw) => _JobCard(job: Map<String, dynamic>.from(raw as Map)),
            ),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.label, required this.value});
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            value?.toString() ?? '-',
            style: const TextStyle(color: inkSoft),
          ),
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 168,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: inkSoft, fontSize: 12)),
            const SizedBox(height: 7),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    ),
  );
}

class _TaskButton extends StatelessWidget {
  const _TaskButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.disabled,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final bool busy;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: disabled ? null : onPressed,
    icon: busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon),
    label: Text(label),
  );
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final created = DateTime.tryParse(job['created_at']?.toString() ?? '')
        ?.toLocal();
    final metrics = job['metrics'] as Map? ?? {};
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          job['status'] == 'success'
              ? Icons.check_circle_outline
              : Icons.pending_actions_outlined,
          color: job['status'] == 'success' ? mint : coral,
        ),
        title: Text('${job['job_type']} · ${job['status']}'),
        subtitle: Text(
          [
            if (created != null)
              DateFormat('yyyy-MM-dd HH:mm:ss').format(created),
            '触发：${job['trigger']}',
            if (metrics.isNotEmpty) '已记录运行指标',
            if (job['error_message'] != null) job['error_message'].toString(),
          ].join('  ·  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text('第 ${job['attempt'] ?? 0} 次'),
      ),
    );
  }
}
