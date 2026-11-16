import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_strings.dart';

class AboutDeveloperScreen extends StatelessWidget {
  const AboutDeveloperScreen({super.key});

  static const phone = '780155801';
  static const internationalPhone = '+967780155801';
  static const email = 'engosamaali7@gmail.com';
  static const whatsappMessage =
      'السلام عليكم، المهندس أسامة القدسي. كنت أتصفح تطبيقك (إدارة المشتريات والحسابات) وأرغب في الاستفسار عن...';
  static const whatsappMessageEn =
      'Hello Eng. Osama Al-Qudsi. I was browsing your app (Purchase and Accounts Management) and would like to ask about...';

  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      if (!context.mounted) return;
      _failure(context);
    } catch (_) {
      if (context.mounted) _failure(context);
    }
  }

  void _failure(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(context,
          'تعذر فتح التطبيق الخارجي. تأكد من توفر تطبيق مناسب.',
          'No available app can open this link.')),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr(context, 'عن المطور', 'About the Developer'))),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(Icons.engineering_rounded, size: 43,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 15),
              Text(tr(context, 'المهندس أسامة علي القدسي',
                  'Eng. Osama Ali Al-Qudsi'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(tr(context, 'مطور التطبيق', 'Application Developer'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Text(
                    tr(context,
                      'مهندس برمجيات ومطور حلول تقنية متكاملة. يهدف إلى بناء تطبيقات وأنظمة رقمية عالية الأداء تتميز بسهولة الاستخدام، الأمان العالي، والتصميم العصري لتلبية احتياجات الأفراد والشركات بكفاءة واحترافية.',
                      'Software Engineer and Integrated Technology Solutions Developer. Dedicated to building high-performance applications and digital systems that combine ease of use, strong security, and modern design to meet the needs of individuals and businesses efficiently and professionally.'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(tr(context, 'معلومات التواصل', 'Contact information'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.phone_outlined),
                      title: Text(tr(context, 'اتصال هاتفي', 'Call')),
                      subtitle: const Text(phone, textDirection: TextDirection.ltr),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => _open(
                          context, Uri.parse('tel:$internationalPhone')),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.chat_outlined),
                      title: const Text('WhatsApp'),
                      subtitle: const Text(phone, textDirection: TextDirection.ltr),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => _open(context, Uri.https(
                          'wa.me', '/967780155801', {'text':
                            Localizations.localeOf(context).languageCode == 'ar'
                              ? whatsappMessage : whatsappMessageEn})),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: Text(tr(context, 'البريد الإلكتروني', 'Email')),
                      subtitle: const Text(email, textDirection: TextDirection.ltr),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => _open(context, Uri(
                          scheme: 'mailto', path: email)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
