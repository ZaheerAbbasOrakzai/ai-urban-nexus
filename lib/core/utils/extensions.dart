// lib/core/utils/extensions.dart
import 'package:flutter/material.dart';

extension ContextExtension on BuildContext {
  void pop() => Navigator.of(this).pop();
  void push(String route) => Navigator.of(this).pushNamed(route);
  void go(String route) => Navigator.of(this).pushNamedAndRemoveUntil(route, (r) => false);
}