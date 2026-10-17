import 'package:flutter/material.dart';

import 'api.dart';
import 'mark.dart';
import 'models.dart';
import 'theme.dart';
import 'workspace.dart';

void main() {
  runApp(const WoollyApp());
}

class WoollyApp extends StatelessWidget {
  const WoollyApp({super.key, this.api});

  final WoollyApi? api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woolly',
      debugShowCheckedModeBanner: false,
      theme: woollyTheme(),
      home: SignInPage(api: api ?? WoollyApi()),
    );
  }
}

class SignInPage extends StatelessWidget {
  const SignInPage({super.key, required this.api});

  final WoollyApi api;

  static const accounts = [
    Person(id: '11111111-1111-4111-8111-111111111111', name: 'Cool Client', role: 'client'),
    Person(id: '22222222-2222-4222-8222-222222222222', name: 'Worker One', role: 'worker'),
    Person(id: '33333333-3333-4333-8333-333333333333', name: 'Worker Dos', role: 'worker'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
            children: [
              const WoollyBrand(markHeight: 36),
              const SizedBox(height: 16),
              const Text('Sign in', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, height: 1.1)),
              const SizedBox(height: 8),
              const Text('Client and worker are separate workplaces.', style: TextStyle(color: muted)),
              const SizedBox(height: 28),
              for (final person in accounts) ...[
                _AccountRow(
                  person: person,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => WorkspacePage(api: api, person: person)),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: line),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(width: 3, height: 32, color: amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(person.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(person.isClient ? 'Client' : 'Worker', style: const TextStyle(color: muted, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, size: 16, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
