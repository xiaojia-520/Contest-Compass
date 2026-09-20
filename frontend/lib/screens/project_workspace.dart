import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ProjectWorkspace extends StatefulWidget {
  const ProjectWorkspace({
    super.key,
    required this.state,
    required this.initialProject,
  });
  final AppState state;
  final AppProject initialProject;

  @override
  State<ProjectWorkspace> createState() => _ProjectWorkspaceState();
}

class _ProjectWorkspaceState extends State<ProjectWorkspace>
    with SingleTickerProviderStateMixin {
  late AppProject project;
  late TabController tabs;
  late final TextEditingController title;
  late final TextEditingController description;
  late final TextEditingController markdown;
  late final TextEditingController school;
  late final TextEditingController education;
  late final TextEditingController grade;
  late final TextEditingController major;
  late final TextEditingController region;
  late final TextEditingController teamSize;
  late final TextEditingController weeklyHours;
  bool saving = false;
  late bool remindersEnabled;

  @override
  void initState() {
    super.initState();
    project = widget.initialProject;
    tabs = TabController(length: 3, vsync: this);
    title = TextEditingController(text: project.title);
    description = TextEditingController(text: project.description);
    markdown = TextEditingController(text: project.markdownContent);
    school = TextEditingController(text: project.school);
    education = TextEditingController(text: project.educationLevel);
    grade = TextEditingController(text: project.grade);
    major = TextEditingController(text: project.major);
    region = TextEditingController(text: project.region);
    teamSize = TextEditingController(text: '${project.teamSize}');
    weeklyHours = TextEditingController(text: '${project.weeklyHours}');
    remindersEnabled = project.remindersEnabled;
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty) {
      showError(context, '项目名称不能为空');
      return;
    }
    setState(() => saving = true);
    project
      ..title = title.text.trim()
      ..description = description.text.trim()
      ..markdownContent = markdown.text
      ..school = school.text.trim()
      ..educationLevel = education.text.trim()
      ..grade = grade.text.trim()
      ..major = major.text.trim()
      ..region = region.text.trim()
      ..teamSize = int.tryParse(teamSize.text) ?? 1
      ..weeklyHours = int.tryParse(weeklyHours.text) ?? 5;
    project.remindersEnabled = remindersEnabled;
    try {
      project = await widget.state.saveProject(project);
      await widget.state.syncReminders();
      if (mounted) showSuccess(context, '项目资料已保存');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> importMarkdown() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    if (file.size > 2000000 || file.bytes == null) {
      if (mounted) showError(context, '文件需小于 2 MB，并使用 UTF-8 编码');
      return;
    }
    try {
      markdown.text = utf8.decode(file.bytes!, allowMalformed: false);
      if (mounted) showSuccess(context, '已导入 ${file.name}，保存后生效');
    } catch (_) {
      if (mounted) showError(context, 'Markdown 文件必须使用 UTF-8 编码');
    }
  }

  @override
  void dispose() {
    tabs.dispose();
    for (final controller in [
      title,
      description,
      markdown,
      school,
      education,
      grade,
      major,
      region,
      teamSize,
      weeklyHours,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFDF8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const Text('项目工作台', style: TextStyle(fontSize: 11, color: inkSoft)),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: compact ? 6 : 16),
            child: compact
                ? IconButton.filled(
                    key: const ValueKey('save-project'),
                    tooltip: saving ? '保存中…' : '保存资料',
                    onPressed: saving ? null : save,
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                  )
                : ElevatedButton.icon(
                    key: const ValueKey('save-project'),
                    onPressed: saving ? null : save,
                    icon: const Icon(Icons.save_outlined, size: 19),
                    label: Text(saving ? '保存中…' : '保存资料'),
                  ),
          ),
        ],
        bottom: TabBar(
          controller: tabs,
          isScrollable: compact,
          tabs: const [
            Tab(icon: Icon(Icons.description_outlined), text: '项目资料'),
            Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'AI 竞赛报告'),
            Tab(icon: Icon(Icons.forum_outlined), text: 'AI 顾问'),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabs,
        children: [
          ProjectForm(
            title: title,
            description: description,
            markdown: markdown,
            school: school,
            education: education,
            grade: grade,
            major: major,
            region: region,
            teamSize: teamSize,
            weeklyHours: weeklyHours,
            remindersEnabled: remindersEnabled,
            onRemindersChanged: (value) =>
                setState(() => remindersEnabled = value),
            onImport: importMarkdown,
          ),
          RecommendationView(
            state: widget.state,
            projectId: project.id,
            onBeforeGenerate: save,
          ),
          ChatView(state: widget.state, projectId: project.id),
        ],
      ),
    );
  }
}

class ProjectForm extends StatelessWidget {
  const ProjectForm({
    super.key,
    required this.title,
    required this.description,
    required this.markdown,
    required this.school,
    required this.education,
    required this.grade,
    required this.major,
    required this.region,
    required this.teamSize,
    required this.weeklyHours,
    required this.remindersEnabled,
    required this.onRemindersChanged,
    required this.onImport,
  });
  final TextEditingController title;
  final TextEditingController description;
  final TextEditingController markdown;
  final TextEditingController school;
  final TextEditingController education;
  final TextEditingController grade;
  final TextEditingController major;
  final TextEditingController region;
  final TextEditingController teamSize;
  final TextEditingController weeklyHours;
  final bool remindersEnabled;
  final ValueChanged<bool> onRemindersChanged;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('把项目讲清楚', subtitle: '信息越具体，比赛匹配、资格判断和备赛建议越准确。'),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('项目内容', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 18),
                    TextField(
                      key: const ValueKey('edit-title'),
                      controller: title,
                      decoration: const InputDecoration(labelText: '项目名称'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: description,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: '项目简介',
                        hintText: '解决什么问题？核心方案是什么？目前完成到什么程度？',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Markdown 项目文档',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('import-markdown'),
                          onPressed: onImport,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('导入 .md'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('markdown-content'),
                      controller: markdown,
                      minLines: 10,
                      maxLines: 24,
                      decoration: const InputDecoration(
                        hintText: '# 项目背景\n\n## 技术方案\n\n## 已有成果',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '团队与参赛条件',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text('用于筛除不符合学历、地域或团队规模要求的比赛。'),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final twoColumns = constraints.maxWidth >= 650;
                        final fields = [
                          _LabeledField(controller: school, label: '学校'),
                          _LabeledField(
                            controller: education,
                            label: '学历',
                            hint: '本科 / 专科 / 研究生',
                          ),
                          _LabeledField(controller: grade, label: '年级'),
                          _LabeledField(controller: major, label: '专业方向'),
                          _LabeledField(controller: region, label: '所在地区'),
                          _LabeledField(
                            controller: teamSize,
                            label: '团队人数',
                            number: true,
                          ),
                          _LabeledField(
                            controller: weeklyHours,
                            label: '每周可投入小时',
                            number: true,
                          ),
                        ];
                        if (!twoColumns) {
                          return Column(
                            children: fields
                                .map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: item,
                                  ),
                                )
                                .toList(),
                          );
                        }
                        return Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: fields
                              .map(
                                (item) => SizedBox(
                                  width: (constraints.maxWidth - 14) / 2,
                                  child: item,
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: remindersEnabled,
                      onChanged: onRemindersChanged,
                      title: const Text('比赛截止提醒'),
                      subtitle: const Text('在匹配比赛截止前 7 天、3 天和 1 天提醒'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    ),
  );
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.controller,
    required this.label,
    this.hint,
    this.number = false,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool number;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );
}

class RecommendationView extends StatefulWidget {
  const RecommendationView({
    super.key,
    required this.state,
    required this.projectId,
    required this.onBeforeGenerate,
  });
  final AppState state;
  final int projectId;
  final Future<void> Function() onBeforeGenerate;

  @override
  State<RecommendationView> createState() => _RecommendationViewState();
}

class _RecommendationViewState extends State<RecommendationView> {
  Map<String, dynamic>? result;
  bool loading = true;
  bool generating = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.state.api.get(
        '/projects/${widget.projectId}/recommendations/latest',
      );
      if (data != null) result = Map<String, dynamic>.from(data as Map);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> generate() async {
    setState(() => generating = true);
    try {
      await widget.onBeforeGenerate();
      final data = await widget.state.api.post(
        '/projects/${widget.projectId}/recommend',
      );
      result = Map<String, dynamic>.from(data as Map);
      await widget.state.syncReminders();
      if (mounted) showSuccess(context, '竞赛分析报告已生成');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (result == null) {
      return EmptyPanel(
        icon: Icons.auto_awesome_rounded,
        title: '生成第一份竞赛匹配报告',
        message: '系统将先从当前可报名/即将开始的赛事中语义召回，再由你的模型进行匹配度重排和备赛规划。',
        action: ElevatedButton.icon(
          key: const ValueKey('generate-report'),
          onPressed: generating ? null : generate,
          icon: const Icon(Icons.auto_awesome),
          label: Text(generating ? 'AI 正在分析…' : '开始智能匹配'),
        ),
      );
    }
    final report = Map<String, dynamic>.from(result!['report'] as Map? ?? {});
    final candidates = (result!['candidates'] as List<dynamic>? ?? [])
        .cast<Map>();
    final byId = {for (final item in candidates) item['contest_id']: item};
    final matches = (report['matches'] as List<dynamic>? ?? []).cast<Map>();
    final matchCards = matches
        .map(
          (item) =>
              _MatchCard(match: item, competition: byId[item['contest_id']]),
        )
        .toList();
    final reportWidgets = <Widget>[
      SectionTitle(
        'AI 竞赛报告',
        subtitle: report['summary']?.toString() ?? '',
        trailing: OutlinedButton.icon(
          onPressed: generating ? null : generate,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(generating ? '生成中…' : '重新分析'),
        ),
      ),
      const SizedBox(height: 24),
    ];
    reportWidgets.addAll(matchCards);
    reportWidgets.addAll([
      const SizedBox(height: 6),
      _ListCard(
        title: '材料清单',
        icon: Icons.checklist_rounded,
        items: report['material_checklist'] as List<dynamic>? ?? [],
      ),
      _TimelineCard(items: report['timeline'] as List<dynamic>? ?? []),
      _ListCard(
        title: '项目改进建议',
        icon: Icons.trending_up_rounded,
        items: report['improvement_suggestions'] as List<dynamic>? ?? [],
      ),
      const SizedBox(height: 12),
      Text(
        report['disclaimer']?.toString() ?? 'AI 建议仅供参考，请以赛事官网为准。',
        style: const TextStyle(fontSize: 12, color: inkSoft),
      ),
      const SizedBox(height: 44),
    ]);
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: reportWidgets,
          ),
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.competition});
  final Map match;
  final Map? competition;
  @override
  Widget build(BuildContext context) {
    final score = match['match_score']?.toString() ?? '--';
    final end = competition?['register_end_at'] as int?;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE9E1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      score,
                      style: const TextStyle(
                        color: coral,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        competition?['contest_name']?.toString() ?? '比赛信息',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 5,
                        children: [
                          if (competition?['level_name'] != null)
                            Text(competition!['level_name'].toString()),
                          if (end != null)
                            Text(
                              '报名截止 ${DateFormat('yyyy-MM-dd').format(DateTime.fromMillisecondsSinceEpoch(end * 1000))}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (competition?['source_url'] != null)
                  IconButton(
                    tooltip: '打开赛事官网',
                    onPressed: () => launchUrl(
                      Uri.parse(competition!['source_url'].toString()),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
              ],
            ),
            const Divider(height: 28, color: line),
            Text(
              match['why_match']?.toString() ?? '',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '资格判断：${match['eligibility'] ?? '需确认'}',
              style: const TextStyle(color: mint, fontWeight: FontWeight.w700),
            ),
            if (match['preparation'] is List) ...[
              const SizedBox(height: 13),
              ...((match['preparation'] as List).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '•  ',
                        style: TextStyle(
                          color: coral,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Expanded(child: Text(item.toString())),
                    ],
                  ),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.icon,
    required this.items,
  });
  final String title;
  final IconData icon;
  final List<dynamic> items;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: mint),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: mint,
                    size: 18,
                  ),
                  const SizedBox(width: 9),
                  Expanded(child: Text(item.toString())),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.items});
  final List<dynamic> items;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: coral),
              const SizedBox(width: 10),
              Text('备赛时间计划', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          ...items.map((raw) {
            final item = raw is Map ? raw : <String, dynamic>{};
            final tasks = item['tasks'] is List
                ? item['tasks'] as List
                : const [];
            return Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: const BoxDecoration(
                      color: coral,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['phase'] ?? '阶段'} · ${item['date_range'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(tasks.join('；')),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    ),
  );
}

class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.state, required this.projectId});
  final AppState state;
  final int projectId;
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final input = TextEditingController();
  final scroll = ScrollController();
  List<ChatMessage> messages = [];
  bool loading = true;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await widget.state.api.get(
        '/projects/${widget.projectId}/messages',
      ) as List<dynamic>;
      messages = data
          .map(
            (item) =>
                ChatMessage.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    input.clear();
    try {
      final data = await widget.state.api.post(
        '/projects/${widget.projectId}/chat',
        {'message': text},
      ) as Map<String, dynamic>;
      messages.add(
        ChatMessage.fromJson(
          Map<String, dynamic>.from(data['user_message'] as Map),
        ),
      );
      messages.add(
        ChatMessage.fromJson(
          Map<String, dynamic>.from(data['assistant_message'] as Map),
        ),
      );
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const EmptyPanel(
                  icon: Icons.forum_outlined,
                  title: '继续追问 AI 顾问',
                  message: '可以询问某场比赛的准备重点、修改项目方向，或让 AI 调整材料清单和时间安排。',
                )
              : ListView.builder(
                  controller: scroll,
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.sizeOf(context).width < 600
                        ? 14
                        : 24,
                    vertical: 28,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final mine = message.role == 'user';
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 760),
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: mine ? ink : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: mine ? null : Border.all(color: line),
                        ),
                        child: mine
                            ? Text(
                                message.content,
                                style: const TextStyle(color: Colors.white),
                              )
                            : MarkdownBody(
                                data: message.content,
                                selectable: true,
                              ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          color: const Color(0xFFFFFDF8),
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 600 ? 12 : 20,
            14,
            MediaQuery.sizeOf(context).width < 600 ? 12 : 20,
            20,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('chat-input'),
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
                      onSubmitted: (_) => send(),
                      decoration: const InputDecoration(
                        hintText: '例如：比较前两场比赛，哪场更适合两人团队？',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    key: const ValueKey('send-message'),
                    onPressed: sending ? null : send,
                    padding: const EdgeInsets.all(15),
                    icon: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
