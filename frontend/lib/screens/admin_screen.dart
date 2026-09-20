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
  List<dynamic> releases = [];
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
      releases =
          await widget.state.api.get('/admin/app-releases') as List<dynamic>;
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> addRelease() async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ReleaseDialog(),
    );
    if (payload == null) return;
    try {
      await widget.state.api.post('/admin/app-releases', payload);
      await load();
      if (mounted) showSuccess(context, '版本记录已创建');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> editRelease(Map<String, dynamic> release) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ReleaseDialog(initial: release),
    );
    if (payload == null) return;
    try {
      await widget.state.api.put(
        '/admin/app-releases/${release['id']}',
        payload,
      );
      await load();
      if (mounted) showSuccess(context, '版本记录已更新');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> deleteRelease(Map<String, dynamic> release) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除版本记录'),
        content: Text('确定删除 ${release['platform']} ${release['version']} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.state.api.delete('/admin/app-releases/${release['id']}');
      await load();
      if (mounted) showSuccess(context, '版本记录已删除');
    } catch (error) {
      if (mounted) showError(context, error);
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
          SectionTitle(
            '客户端版本',
            subtitle: '维护各平台的版本号、强制更新策略和外部 HTTPS 下载地址。',
            trailing: ElevatedButton.icon(
              onPressed: addRelease,
              icon: const Icon(Icons.add_rounded),
              label: const Text('发布版本'),
            ),
          ),
          const SizedBox(height: 12),
          if (releases.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无客户端版本记录'),
              ),
            )
          else
            ...releases.take(8).map((raw) {
              final release = Map<String, dynamic>.from(raw as Map);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.apps_rounded, color: mint),
                  title: Text(
                    '${release['platform']} · ${release['version']} '
                    '(${release['build_number']})',
                  ),
                  subtitle: Text(
                    '${release['published'] == true ? '已发布' : '草稿'} · '
                    '${release['download_url'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: '版本操作',
                    onSelected: (value) {
                      if (value == 'edit') editRelease(release);
                      if (value == 'delete') deleteRelease(release);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: release['published'] == true ? mint : inkSoft,
                    ),
                  ),
                ),
              );
            }),
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

class _ReleaseDialog extends StatefulWidget {
  const _ReleaseDialog({this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<_ReleaseDialog> createState() => _ReleaseDialogState();
}

class _ReleaseDialogState extends State<_ReleaseDialog> {
  final formKey = GlobalKey<FormState>();
  final version = TextEditingController();
  final buildNumber = TextEditingController();
  final minimum = TextEditingController();
  final url = TextEditingController();
  final notes = TextEditingController();
  final sha256 = TextEditingController();
  String platform = 'android';
  bool published = false;
  bool mandatory = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    platform = initial?['platform']?.toString() ?? 'android';
    version.text = initial?['version']?.toString() ?? '1.0.0';
    buildNumber.text = initial?['build_number']?.toString() ?? '1';
    minimum.text = initial?['minimum_supported_version']?.toString() ?? '';
    url.text = initial?['download_url']?.toString() ?? '';
    notes.text = initial?['release_notes']?.toString() ?? '';
    sha256.text = initial?['sha256']?.toString() ?? '';
    published = initial?['published'] == true;
    mandatory = initial?['mandatory'] == true;
  }

  @override
  void dispose() {
    version.dispose();
    buildNumber.dispose();
    minimum.dispose();
    url.dispose();
    notes.dispose();
    sha256.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '发布客户端版本' : '编辑客户端版本'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: platform,
                decoration: const InputDecoration(labelText: '平台'),
                items: const [
                  DropdownMenuItem(value: 'android', child: Text('Android')),
                  DropdownMenuItem(value: 'ios', child: Text('iOS')),
                  DropdownMenuItem(value: 'windows', child: Text('Windows')),
                  DropdownMenuItem(value: 'macos', child: Text('macOS')),
                  DropdownMenuItem(value: 'web', child: Text('Web')),
                ],
                onChanged: (value) => setState(() => platform = value!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: version,
                decoration: const InputDecoration(labelText: '版本号（如 1.2.0）'),
                validator: (value) =>
                    RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value?.trim() ?? '')
                    ? null
                    : '请输入三段式版本号',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: buildNumber,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '构建号'),
                validator: (value) {
                  final parsed = int.tryParse(value?.trim() ?? '');
                  return parsed != null && parsed > 0 ? null : '请输入正整数构建号';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: minimum,
                decoration: const InputDecoration(labelText: '最低支持版本（选填）'),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  return text.isEmpty ||
                          RegExp(r'^\d+\.\d+\.\d+$').hasMatch(text)
                      ? null
                      : '请输入三段式版本号';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: url,
                decoration: const InputDecoration(labelText: 'HTTPS 下载地址'),
                validator: (value) => (value ?? '').startsWith('https://')
                    ? null
                    : '下载地址必须使用 HTTPS',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: notes,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: '更新说明'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: sha256,
                decoration: const InputDecoration(labelText: 'SHA-256（选填）'),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  return text.isEmpty ||
                          RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(text)
                      ? null
                      : '请输入 64 位 SHA-256';
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: published,
                onChanged: (value) => setState(() => published = value),
                title: const Text('立即发布'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: mandatory,
                onChanged: (value) => setState(() => mandatory = value),
                title: const Text('强制更新'),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      ElevatedButton(
        onPressed: () {
          if (!formKey.currentState!.validate()) return;
          Navigator.pop(context, {
            'platform': platform,
            'version': version.text.trim(),
            'build_number': int.tryParse(buildNumber.text) ?? 1,
            'minimum_supported_version': minimum.text.trim().isEmpty
                ? null
                : minimum.text.trim(),
            'release_notes': notes.text.trim(),
            'download_url': url.text.trim(),
            'sha256': sha256.text.trim().isEmpty
                ? null
                : sha256.text.trim().toLowerCase(),
            'mandatory': mandatory,
            'published': published,
          });
        },
        child: const Text('保存'),
      ),
    ],
  );
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
