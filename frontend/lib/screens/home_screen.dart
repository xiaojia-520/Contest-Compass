import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'project_workspace.dart';
import 'settings_screen.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final isAdmin = widget.state.user?['is_admin'] == true;
        final content = switch (selected) {
          0 => ProjectsPage(state: widget.state),
          1 => SettingsScreen(state: widget.state),
          2 when isAdmin => AdminScreen(state: widget.state),
          _ => ProjectsPage(state: widget.state),
        };
        return Scaffold(
          appBar: wide
              ? null
              : AppBar(
                  title: const BrandMark(),
                  backgroundColor: canvas,
                  actions: [
                    IconButton(
                      tooltip: '退出登录',
                      onPressed: widget.state.logout,
                      icon: const Icon(Icons.logout_rounded),
                    ),
                  ],
                ),
          drawer: wide
              ? null
              : NavigationDrawer(
                  selectedIndex: selected,
                  onDestinationSelected: (value) {
                    setState(() => selected = value);
                    Navigator.pop(context);
                  },
                  children: [
                    const SizedBox(height: 16),
                    const NavigationDrawerDestination(
                      icon: Icon(Icons.grid_view_rounded),
                      label: Text('我的项目'),
                    ),
                    const NavigationDrawerDestination(
                      icon: Icon(Icons.tune_rounded),
                      label: Text('模型设置'),
                    ),
                    if (isAdmin)
                      const NavigationDrawerDestination(
                        icon: Icon(Icons.admin_panel_settings_outlined),
                        label: Text('任务管理'),
                      ),
                  ],
                ),
          body: Row(
            children: [
              if (wide)
                Container(
                  width: 244,
                  color: const Color(0xFFFFFDF8),
                  padding: const EdgeInsets.fromLTRB(18, 26, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: BrandMark(),
                      ),
                      const SizedBox(height: 42),
                      _NavItem(
                        icon: Icons.grid_view_rounded,
                        label: '我的项目',
                        selected: selected == 0,
                        onTap: () => setState(() => selected = 0),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(height: 8),
                        _NavItem(
                          icon: Icons.admin_panel_settings_outlined,
                          label: '任务管理',
                          selected: selected == 2,
                          onTap: () => setState(() => selected = 2),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _NavItem(
                        icon: Icons.tune_rounded,
                        label: '模型设置',
                        selected: selected == 1,
                        onTap: () => setState(() => selected = 1),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2EFE7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: mint,
                              foregroundColor: Colors.white,
                              child: Text(
                                (widget.state.user?['username'] as String? ??
                                        '用')
                                    .characters
                                    .first,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.state.user?['username'] as String? ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '退出登录',
                              onPressed: widget.state.logout,
                              icon: const Icon(Icons.logout_rounded, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFFFE9E1) : Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: selected ? coral : inkSoft, size: 21),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected ? coral : ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key, required this.state});
  final AppState state;

  Future<void> addProject(BuildContext context) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const NewProjectDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      final project = await state.createProject(result);
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ProjectWorkspace(state: state, initialProject: project),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width >= 1000 ? 56 : 22,
        vertical: 34,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            '我的项目',
            subtitle: '把作品资料整理在这里，AI 会持续理解并更新参赛策略。',
            trailing: ElevatedButton.icon(
              key: const ValueKey('new-project'),
              onPressed: () => addProject(context),
              icon: const Icon(Icons.add),
              label: const Text('新建项目'),
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: state.projects.isEmpty
                ? Card(
                    child: EmptyPanel(
                      icon: Icons.rocket_launch_outlined,
                      title: '从第一个项目开始',
                      message: '输入项目介绍或导入 Markdown，几分钟内获得比赛匹配与完整备赛方案。',
                      action: ElevatedButton.icon(
                        onPressed: () => addProject(context),
                        icon: const Icon(Icons.add),
                        label: const Text('创建项目'),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1000
                          ? 3
                          : constraints.maxWidth >= 620
                          ? 2
                          : 1;
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 18,
                          childAspectRatio: 1.42,
                        ),
                        itemCount: state.projects.length,
                        itemBuilder: (context, index) => ProjectCard(
                          project: state.projects[index],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProjectWorkspace(
                                state: state,
                                initialProject: state.projects[index],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({super.key, required this.project, required this.onTap});
  final AppProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        key: ValueKey('project-${project.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4F2EE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: mint,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_outward_rounded,
                    color: inkSoft,
                    size: 20,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                project.title,
                style: Theme.of(context).textTheme.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                project.description.isEmpty ? '等待补充项目介绍' : project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                '更新于 ${DateFormat('MM月dd日 HH:mm').format(project.updatedAt.toLocal())}',
                style: const TextStyle(fontSize: 12, color: inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key});
  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final key = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建项目'),
    content: SizedBox(
      width: 500,
      child: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('project-title'),
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '项目名称'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? '请输入项目名称' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('project-description'),
              controller: description,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '一句话介绍',
                hintText: '例如：用计算机视觉识别农作物病害的移动端系统',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      ElevatedButton(
        key: const ValueKey('create-project'),
        onPressed: () {
          if (!key.currentState!.validate()) return;
          Navigator.pop(context, {
            'title': title.text.trim(),
            'description': description.text.trim(),
            'markdown_content': '',
            'school': '',
            'education_level': '',
            'grade': '',
            'major': '',
            'region': '',
            'team_size': 1,
            'weekly_hours': 5,
          });
        },
        child: const Text('创建并完善'),
      ),
    ],
  );
}
