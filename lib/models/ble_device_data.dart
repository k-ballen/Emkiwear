class TremorSample {
  final int tMs;
  final double roll;
  final double pitch;
  final double linAcc;
  final double gyroMag;
  final double tremorAmp;

  TremorSample({
    required this.tMs,
    required this.roll,
    required this.pitch,
    required this.linAcc,
    required this.gyroMag,
    required this.tremorAmp,
  });

  @override
  String toString() {
    return 'Sample(t: $tMs, roll: ${roll.toStringAsFixed(2)}, pitch: ${pitch.toStringAsFixed(2)}, amp: ${tremorAmp.toStringAsFixed(2)})';
  }
}

class TremorStatus {
  final int tMs;
  final bool tremorPresent;
  final bool freqStable;
  final double domFreq;
  final double tremorAmp;
  final double movement;
  final int bandFrac;
  final int duty;
  final int episode;

  TremorStatus({
    required this.tMs,
    required this.tremorPresent,
    required this.freqStable,
    required this.domFreq,
    required this.tremorAmp,
    required this.movement,
    required this.bandFrac,
    required this.duty,
    required this.episode,
  });

  @override
  String toString() {
    return 'Status(tremor: $tremorPresent, freq: ${domFreq.toStringAsFixed(1)}Hz, amp: ${tremorAmp.toStringAsFixed(1)}dps)';
  }
}

class RawSample {
  final int ax, ay, az, gx, gy, gz;
  RawSample(this.ax, this.ay, this.az, this.gx, this.gy, this.gz);
}

class RawFifoPacket {
  final int seqPrimera;
  final int t0Us;
  final int nMuestras;
  final List<RawSample> samples;

  RawFifoPacket(this.seqPrimera, this.t0Us, this.nMuestras, this.samples);
}
