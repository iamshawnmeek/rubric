extension IterableExtensions<T> on Iterable<T> {
  /// Interlace the "separator" between each item.
  ///
  ///### Example 1: Strings
  /// ```
  /// final a = ['a', 'a', 'a'];
  ///
  /// a.joinWith('b'); -> ['a', 'b', 'a', 'b', 'a']
  /// ```
  ///
  /// ### Example 2: Widgets
  /// ```
  /// final widgets = <Widget>[
  ///   Text('item1'),
  ///   Text('item2'),
  ///   Text('item3'),
  /// ];
  ///
  /// widgets.joinWith(Divider()); -> [
  ///   Text('item1'),
  ///   Divider(),
  ///   Text('item2'),
  ///   Divider(),
  ///   Text('item3'),
  /// ]
  /// ```
  List<T> joinWith<T>(T separator) {
    if (length <= 0) return [separator];
    if (length == 1) return List<T>.from(this);

    return List<T>.from(map((current) => [
          current,
          separator,
        ]).expand((w) => w))
      ..removeLast();
  }
}
