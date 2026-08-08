/// View-model state for one template's occurrence history (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// The template the history belongs to.
final historyTemplateProvider = FutureProvider.autoDispose
    .family<RecurringTemplate?, String>(
      (ref, templateId) =>
          ref.watch(recurringRepositoryProvider).templateById(templateId),
    );
