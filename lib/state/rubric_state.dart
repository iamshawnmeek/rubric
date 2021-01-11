import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubric/domain/rubric.dart';

final rubricProviderRef =
    StateNotifierProvider<RubricState>((ref) => RubricState());

//mechanism to update the Rubric class with the new objective
class RubricState extends StateNotifier<Rubric> {
  RubricState() : super(Rubric(objectives: []));

//TODO: Add method to update objectives: 1.11.21
}
