extension ListExtensions<T> on List<T> {
  /// Execute the [callback] for each item in the `List`, providing the
  /// current index for each item to the [callback] as the first argument.
  ///
  ///### Example 1: Strings
  /// ```
  /// final a = ['a', 'b', 'c'];
  ///
  /// a.mapWithIndex((index, item) => '$item$index');
  ///   -> ['a0', 'b1', 'c2']
  /// ```
  ///
  /// ### Example 2: Widgets
  /// ```
  /// final items = [
  ///   'item1',
  ///   'item2',
  ///   'item3',
  /// ];
  ///
  /// items.mapWithIndex(index, item) {
  ///   final evenColor = Colors.red;
  ///   final oddColor = Colors.black;
  ///   final selected = index % 2 == 0 ? evenColor : oddColor;
  ///
  ///   return Container(
  ///     color: selected,
  ///     child: Text(item),
  ///   );
  /// });
  ///```
  List<E> mapWithIndex<E>(E Function(int, T) callback) {
    if (length <= 0) return [];

    return asMap()
        .map((index, element) => MapEntry(
              index,
              callback(index, element),
            ))
        .values
        .toList();
  }

  /// Groups list elements according to the value returned by the [callback].
  ///
  /// Returns a `Map` in which keys are the values returned by the [callback]
  /// and values are a `List` of grouped elements.
  Map<K, List<T>> groupBy<K>(K Function(T) callback) {
    return fold(<K, List<T>>{}, (map, element) {
      return map..putIfAbsent(callback(element), () => <T>[]).add(element);
    });
  }
}
