import 'package:double_linked_list/double_linked_list.dart';
import 'package:rubric/weight/slider.dart';

class WeightController extends DoubleLinkedList<Slider> {
  WeightController.fromIterable(Iterable<Slider> contents)
      : super.fromIterable(contents);
}
