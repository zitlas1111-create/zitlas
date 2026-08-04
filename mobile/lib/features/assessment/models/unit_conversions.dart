/// `cmToFtIn()`/`ftInToCm()`/`kgToLbs()`/`lbsToKg()` in `ai-coach.js` — exact
/// ports, including the same rounding/clamping behavior, used by the
/// height/weight wheel pickers' unit toggle.
library;

int cmToFt(double cm) {
  final totalIn = cm / 2.54;
  var ft = totalIn ~/ 12;
  var inches = (totalIn - ft * 12).round();
  if (inches == 12) {
    ft++;
    inches = 0;
  }
  return ft.clamp(3, 8).toInt();
}

int cmToIn(double cm) {
  final totalIn = cm / 2.54;
  final ft = (totalIn ~/ 12).clamp(3, 8);
  var inches = (totalIn - ft * 12).round();
  if (inches == 12) inches = 0;
  return inches.clamp(0, 11);
}

double ftInToCm(int ft, int inches) => (ft * 30.48 + inches * 2.54).roundToDouble();

int kgToLbs(double kg) => (kg * 2.20462).round();

double lbsToKg(int lbs) => ((lbs * 0.45359237) * 10).round() / 10;
