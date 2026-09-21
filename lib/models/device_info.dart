class DeviceInfo {
  final String firmware;
  final int odr;
  final int accRangeG;
  final int gyrRangeDps;
  final double lsb2ms2;
  final double lsb2dps;

  DeviceInfo({
    required this.firmware,
    required this.odr,
    required this.accRangeG,
    required this.gyrRangeDps,
    required this.lsb2ms2,
    required this.lsb2dps,
  });

  factory DeviceInfo.parse(String info) {
    // FW=1.1.0;ODR=50;ACC_RANGE_G=4;GYR_RANGE_DPS=500;LSB2MS2=0.00119629;LSB2DPS=0.01525879
    final Map<String, String> parts = {};
    final pairs = info.split(';');
    for (var pair in pairs) {
      final kv = pair.split('=');
      if (kv.length == 2) {
        parts[kv[0].trim()] = kv[1].trim();
      }
    }

    return DeviceInfo(
      firmware: parts['FW'] ?? 'unknown',
      odr: int.tryParse(parts['ODR'] ?? '50') ?? 50,
      accRangeG: int.tryParse(parts['ACC_RANGE_G'] ?? '4') ?? 4,
      gyrRangeDps: int.tryParse(parts['GYR_RANGE_DPS'] ?? '500') ?? 500,
      lsb2ms2: double.tryParse(parts['LSB2MS2'] ?? '0.00119629') ?? 0.00119629,
      lsb2dps: double.tryParse(parts['LSB2DPS'] ?? '0.01525879') ?? 0.01525879,
    );
  }

  @override
  String toString() {
    return 'DeviceInfo(FW: $firmware, ODR: $odr, AccRange: $accRangeG G, GyrRange: $gyrRangeDps DPS)';
  }
}
