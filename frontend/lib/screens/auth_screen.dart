import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.state});
  final AppState state;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final account = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = false;
  bool obscure = true;

  @override
  void dispose() {
    account.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    try {
      await widget.state.authenticate(
        register: register,
        account: account.text,
        email: email.text,
        password: password.text,
      );
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Row(
              children: [
                if (wide)
                  Expanded(
                    flex: 11,
                    child: Container(
                      height: double.infinity,
                      padding: const EdgeInsets.all(64),
                      decoration: const BoxDecoration(
                        color: ink,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF112B3C), Color(0xFF244B54)],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const BrandMark(onDark: true),
                          const Spacer(),
                          const Text(
                            '让好项目，\n遇见对的比赛。',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              height: 1.18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            '基于真实赛事资料，从项目理解、智能匹配到参赛规划，\n一次完成。',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .72),
                              fontSize: 17,
                              height: 1.7,
                            ),
                          ),
                          const SizedBox(height: 42),
                          const Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _FeatureChip(
                                icon: Icons.manage_search_rounded,
                                text: '语义匹配',
                              ),
                              _FeatureChip(
                                icon: Icons.route_rounded,
                                text: '参赛路线',
                              ),
                              _FeatureChip(
                                icon: Icons.forum_outlined,
                                text: '持续追问',
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            '你的模型 · 你的额度 · 加密保存',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .52),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  flex: 9,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 72 : 24,
                        vertical: 36,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!wide) ...[
                                const BrandMark(),
                                const SizedBox(height: 44),
                              ],
                              Text(
                                register ? '创建你的账号' : '欢迎回来',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                register
                                    ? '保存多个项目，并在不同设备继续规划。'
                                    : '继续完善项目，找到下一场值得参加的比赛。',
                              ),
                              const SizedBox(height: 34),
                              TextFormField(
                                key: const ValueKey('account-field'),
                                controller: account,
                                decoration: InputDecoration(
                                  labelText: register ? '用户名' : '用户名或邮箱',
                                  prefixIcon: const Icon(Icons.person_outline),
                                ),
                                validator: (value) =>
                                    (value ?? '').trim().length < 3
                                    ? '至少输入 3 个字符'
                                    : null,
                              ),
                              if (register) ...[
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: email,
                                  decoration: const InputDecoration(
                                    labelText: '邮箱（选填）',
                                    prefixIcon: Icon(Icons.mail_outline),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                ),
                              ],
                              const SizedBox(height: 16),
                              TextFormField(
                                key: const ValueKey('password-field'),
                                controller: password,
                                obscureText: obscure,
                                onFieldSubmitted: (_) => submit(),
                                decoration: InputDecoration(
                                  labelText: '密码',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    onPressed: () =>
                                        setState(() => obscure = !obscure),
                                    icon: Icon(
                                      obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: (value) => (value ?? '').length < 8
                                    ? '密码至少 8 位'
                                    : null,
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                key: const ValueKey('auth-submit'),
                                onPressed: widget.state.busy ? null : submit,
                                child: widget.state.busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(register ? '注册并开始' : '登录'),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () =>
                                    setState(() => register = !register),
                                child: Text(
                                  register ? '已有账号？返回登录' : '第一次使用？创建账号',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: .14)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: const Color(0xFFFFB39F)),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
