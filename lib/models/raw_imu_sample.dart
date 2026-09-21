class RawImuSample {
  final int tMs;
  final int epochMs;
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;

  RawImuSample({
    required this.tMs,
    required this.epochMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  String toCsvLine() {
    return "$tMs,$epochMs,$ax,$ay,$az,$gx,$gy,$gz";
  }
}
