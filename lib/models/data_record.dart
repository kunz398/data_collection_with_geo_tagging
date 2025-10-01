class DataRecord {
  final int? id;
  final String name;
  final DateTime dateOfBirth;
  final String gender;
  final String phoneNumber;
  final String email;
  final String address;
  final double latitude;
  final double longitude;
  final String locationMethod; // 'current', 'pin', 'address'
  final String notes;
  final DateTime createdAt;

  DataRecord({
    this.id,
    required this.name,
    required this.dateOfBirth,
    required this.gender,
    required this.phoneNumber,
    required this.email,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.locationMethod,
    required this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'date_of_birth': dateOfBirth.toIso8601String(),
      'gender': gender,
      'phone_number': phoneNumber,
      'email': email,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'location_method': locationMethod,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory DataRecord.fromMap(Map<String, dynamic> map) {
    return DataRecord(
      id: map['id'],
      name: map['name'],
      dateOfBirth: DateTime.parse(map['date_of_birth']),
      gender: map['gender'],
      phoneNumber: map['phone_number'],
      email: map['email'],
      address: map['address'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      locationMethod: map['location_method'],
      notes: map['notes'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  DataRecord copyWith({
    int? id,
    String? name,
    DateTime? dateOfBirth,
    String? gender,
    String? phoneNumber,
    String? email,
    String? address,
    double? latitude,
    double? longitude,
    String? locationMethod,
    String? notes,
    DateTime? createdAt,
  }) {
    return DataRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationMethod: locationMethod ?? this.locationMethod,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}