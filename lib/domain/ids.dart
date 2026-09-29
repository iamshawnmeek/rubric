import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A new random identifier for any entity.
String newId() => _uuid.v4();
