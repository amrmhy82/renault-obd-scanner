/// بيانات السيارة نفسها (وليس قراءات حية). هذه هي الأساس الذي ترتبط به
/// لاحقًا بيانات أخرى (PIDs مدعومة، بروفايل بروتوكول رينو الخاص، إلخ) —
/// دون أن نفترض أن كل رينو فلوانس 2017 متطابقة تمامًا.
class VehicleProfile {
  String make;
  String model;
  int? year;
  String? vin;
  String? engine;
  String? transmission;
  String? fuelType;
  String? plateNumber;
  String? obdAdapterName;

  VehicleProfile({
    this.make = 'Renault',
    this.model = 'Fluence',
    this.year = 2017,
    this.vin,
    this.engine,
    this.transmission,
    this.fuelType = 'بنزين',
    this.plateNumber,
    this.obdAdapterName,
  });

  Map<String, dynamic> toJson() => {
        'make': make,
        'model': model,
        'year': year,
        'vin': vin,
        'engine': engine,
        'transmission': transmission,
        'fuelType': fuelType,
        'plate': plateNumber,
        'adapter': obdAdapterName,
      };

  factory VehicleProfile.fromJson(Map<String, dynamic> j) => VehicleProfile(
        make: j['make'] as String? ?? 'Renault',
        model: j['model'] as String? ?? 'Fluence',
        year: j['year'] as int?,
        vin: j['vin'] as String?,
        engine: j['engine'] as String?,
        transmission: j['transmission'] as String?,
        fuelType: j['fuelType'] as String?,
        plateNumber: j['plate'] as String?,
        obdAdapterName: j['adapter'] as String?,
      );
}
