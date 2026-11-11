abstract final class HexBytes {
  static String format(Iterable<int> bytes) => bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
  static List<int> parse(String text) {
    final clean = text.replaceAll(RegExp(r'\s'), '');
    if (clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(clean)) {
      throw const FormatException('Enter pairs of hexadecimal digits.');
    }
    return [
      for (var i = 0; i < clean.length; i += 2)
        int.parse(clean.substring(i, i + 2), radix: 16),
    ];
  }
}
