import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/domain/rubric.dart';

final rubricProviderRef =
    StateProvider<Rubric>((ref) => Rubric(objectives: []));
