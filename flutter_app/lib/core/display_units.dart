abstract final class DisplayUnits {
  static double distance(num km, bool miles) => km * (miles ? 0.6213712 : 1);
  static double temperature(num celsius, bool fahrenheit) =>
      celsius * (fahrenheit ? 9 / 5 : 1) + (fahrenheit ? 32 : 0);
  static String temperatureText(num? celsius, bool fahrenheit) =>
      celsius == null
      ? '—'
      : temperature(celsius, fahrenheit).toStringAsFixed(0);
}
