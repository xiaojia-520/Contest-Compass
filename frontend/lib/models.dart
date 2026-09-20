class AppProject {
  AppProject({
    required this.id,
    required this.title,
    required this.description,
    required this.markdownContent,
    required this.school,
    required this.educationLevel,
    required this.grade,
    required this.major,
    required this.region,
    required this.teamSize,
    required this.weeklyHours,
    required this.remindersEnabled,
    required this.updatedAt,
  });

  final int id;
  String title;
  String description;
  String markdownContent;
  String school;
  String educationLevel;
  String grade;
  String major;
  String region;
  int teamSize;
  int weeklyHours;
  bool remindersEnabled;
  DateTime updatedAt;

  factory AppProject.fromJson(Map<String, dynamic> json) => AppProject(
    id: json['id'] as int,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    markdownContent: json['markdown_content'] as String? ?? '',
    school: json['school'] as String? ?? '',
    educationLevel: json['education_level'] as String? ?? '',
    grade: json['grade'] as String? ?? '',
    major: json['major'] as String? ?? '',
    region: json['region'] as String? ?? '',
    teamSize: json['team_size'] as int? ?? 1,
    weeklyHours: json['weekly_hours'] as int? ?? 5,
    remindersEnabled: json['reminders_enabled'] as bool? ?? true,
    updatedAt:
        DateTime.tryParse(json['updated_at'] as String? ?? '') ??
        DateTime.now(),
  );

  Map<String, dynamic> toPayload() => {
    'title': title,
    'description': description,
    'markdown_content': markdownContent,
    'school': school,
    'education_level': educationLevel,
    'grade': grade,
    'major': major,
    'region': region,
    'team_size': teamSize,
    'weekly_hours': weeklyHours,
    'reminders_enabled': remindersEnabled,
  };
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.sources,
  });
  final int id;
  final String role;
  final String content;
  final List<dynamic> sources;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as int,
    role: json['role'] as String,
    content: json['content'] as String,
    sources: json['sources'] as List<dynamic>? ?? [],
  );
}
