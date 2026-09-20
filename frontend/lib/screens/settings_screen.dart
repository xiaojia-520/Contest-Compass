import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/desktop_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class _ProviderPreset {
  const _ProviderPreset(this.id, this.label, this.model, [this.apiBase = '']);
  final String id;
  final String label;
  final String model;
  final String apiBase;
}

const presets = [
  _ProviderPreset('openai', 'OpenAI', 'openai/gpt-5-mini'),
  _ProviderPreset('deepseek', 'DeepSeek', 'deepseek/deepseek-chat'),
  _ProviderPreset('dashscope', '通义千问', 'dashscope/qwen-plus'),
  _ProviderPreset('anthropic', 'Anthropic', 'anthropic/claude-sonnet-4-5'),
  _ProviderPreset('gemini', 'Google Gemini', 'gemini/gemini-2.5-flash'),
  _ProviderPreset(
    'ollama',
    '本地 Ollama',
    'ollama/qwen3',
    'http://localhost:11434',
  ),
  _ProviderPreset('custom', 'OpenAI 兼容 / 自定义', 'openai/your-model'),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final model = TextEditingController();
  final apiBase = TextEditingController();
  final apiKey = TextEditingController();
  String provider = 'openai';
  bool loading = true;
  bool saving = false;
  bool testing = false;
  bool hasStoredKey = false;
  bool obscure = true;
  bool startupEnabled = false;
  bool checkingUpdate = false;
  List<dynamic> usage = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final config = await widget.state.loadModelConfig();
      usage = await widget.state.api.get('/usage') as List<dynamic>;
      startupEnabled = await DesktopService.instance.isLaunchAtStartupEnabled();
      if (config != null) {
        provider = config['provider'] as String? ?? 'custom';
        if (!presets.any((item) => item.id == provider)) provider = 'custom';
        model.text = config['model_name'] as String? ?? '';
        apiBase.text = config['api_base'] as String? ?? '';
        hasStoredKey = config['has_api_key'] as bool? ?? false;
      } else {
        model.text = presets.first.model;
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void selectProvider(String? value) {
    if (value == null) return;
    final preset = presets.firstWhere((item) => item.id == value);
    setState(() {
      provider = value;
      model.text = preset.model;
      apiBase.text = preset.apiBase;
    });
  }

  Future<void> save() async {
    if (model.text.trim().isEmpty) {
      showError(context, '请填写 LiteLLM 模型名');
      return;
    }
    setState(() => saving = true);
    try {
      await widget.state.saveModelConfig({
        'provider': provider,
        'model_name': model.text.trim(),
        'api_base': apiBase.text.trim().isEmpty ? null : apiBase.text.trim(),
        'api_key': apiKey.text.trim().isEmpty ? null : apiKey.text.trim(),
      });
      apiKey.clear();
      hasStoredKey = widget.state.modelConfig?['has_api_key'] as bool? ?? false;
      if (mounted) showSuccess(context, '模型配置已加密保存');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> testConnection() async {
    setState(() => testing = true);
    try {
      await save();
      if (!mounted) return;
      final response = await widget.state.api.post(
        '/model-config/test',
      ) as Map<String, dynamic>;
      if (mounted) showSuccess(context, '连接成功：${response['message']}');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Future<void> toggleReminders(bool value) async {
    try {
      await widget.state.setRemindersEnabled(value);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> toggleStartup(bool value) async {
    try {
      await DesktopService.instance.setLaunchAtStartup(value);
      if (mounted) setState(() => startupEnabled = value);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> checkUpdate() async {
    setState(() => checkingUpdate = true);
    try {
      final update = await widget.state.updates.check();
      if (!mounted) return;
      if (update == null) {
        showSuccess(context, '当前已经是最新版本');
        return;
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: !update.mandatory,
        builder: (context) => AlertDialog(
          title: Text('发现新版本 ${update.version}'),
          content: Text(update.notes.isEmpty ? '新版本已经可以下载。' : update.notes),
          actions: [
            if (!update.mandatory)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('稍后'),
              ),
            ElevatedButton(
              onPressed: () => widget.state.updates.openDownload(update),
              child: const Text('前往下载'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final totalTokens = usage.fold<int>(
      0,
      (sum, row) => sum + ((row as Map)['total_tokens'] as int? ?? 0),
    );
    final successful = usage
        .where((row) => (row as Map)['success'] == true)
        .length;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width >= 1000 ? 56 : 22,
        vertical: 34,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('模型设置', subtitle: '使用你自己的模型额度。密钥只发送给后端，并以密文保存。'),
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE9E1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.hub_outlined, color: coral),
                        ),
                        const SizedBox(width: 13),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'LiteLLM 通用连接',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                '可随时切换供应商，无需修改应用代码',
                                style: TextStyle(color: inkSoft),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('provider-select'),
                      initialValue: provider,
                      decoration: const InputDecoration(labelText: '模型供应商'),
                      items: presets
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: selectProvider,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('model-name'),
                      controller: model,
                      decoration: const InputDecoration(
                        labelText: 'LiteLLM 模型名',
                        hintText: '例如 deepseek/deepseek-chat',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('api-base'),
                      controller: apiBase,
                      decoration: const InputDecoration(
                        labelText: 'API 地址（官方供应商可留空）',
                        hintText: 'https://example.com/v1',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('api-key'),
                      controller: apiKey,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: hasStoredKey
                            ? 'API Key（已保存；留空则不修改）'
                            : 'API Key',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, size: 17, color: mint),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '密钥使用 Fernet 加密保存；页面刷新或跨设备登录后不会返回明文。',
                            style: TextStyle(fontSize: 13, color: inkSoft),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          key: const ValueKey('save-model'),
                          onPressed: saving ? null : save,
                          icon: const Icon(Icons.lock_outline),
                          label: Text(saving ? '保存中…' : '加密保存'),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('test-model'),
                          onPressed: testing ? null : testConnection,
                          icon: const Icon(Icons.cable_rounded),
                          label: Text(testing ? '测试中…' : '测试连接'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: widget.state.remindersEnabled,
                      onChanged: toggleReminders,
                      secondary: const Icon(
                        Icons.notifications_active_outlined,
                        color: coral,
                      ),
                      title: const Text('比赛截止提醒'),
                      subtitle: const Text('截止前 7 天、3 天和 1 天的上午 9:00 提醒'),
                    ),
                    if (DesktopService.instance.supported)
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: startupEnabled,
                        onChanged: toggleStartup,
                        secondary: const Icon(Icons.power_settings_new_rounded),
                        title: const Text('开机自启'),
                        subtitle: const Text('默认关闭，可随时在这里更改'),
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.system_update_alt_rounded),
                      title: const Text('版本更新'),
                      subtitle: const Text(
                        '检查 Android、iOS、Windows 或 macOS 新版本',
                      ),
                      trailing: OutlinedButton(
                        onPressed: checkingUpdate ? null : checkUpdate,
                        child: Text(checkingUpdate ? '检查中…' : '检查更新'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final metrics = [
                      _Metric(label: '调用次数', value: '${usage.length}'),
                      _Metric(label: '成功调用', value: '$successful'),
                      _Metric(label: '累计 Token', value: '$totalTokens'),
                    ];
                    if (constraints.maxWidth < 520) {
                      return Column(
                        children: [
                          metrics[0],
                          const Divider(height: 28, color: line),
                          metrics[1],
                          const Divider(height: 28, color: line),
                          metrics[2],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: metrics[0]),
                        const SizedBox(
                          height: 50,
                          child: VerticalDivider(color: line),
                        ),
                        Expanded(child: metrics[1]),
                        const SizedBox(
                          height: 50,
                          child: VerticalDivider(color: line),
                        ),
                        Expanded(child: metrics[2]),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 5),
      Text(label, style: const TextStyle(color: inkSoft)),
    ],
  );
}
