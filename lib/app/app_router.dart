import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/business_profile_gate.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const BusinessProfileGate(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('Navigation error: ${state.error}')),
  ),
);
