class UserProfile {
  final String uid;
  final String name;
  final String lastName;
  final String fixedPhone;
  final String cellPhone;
  final String photoUrl;
  final int? diagnosisYear;
  final String experience;
  final String specialistName;
  final String specialistType;
  final String hospital;
  final String consultationTime;
  final String supportGroup;
  final bool isPublic;

  UserProfile({
    required this.uid,
    required this.name,
    required this.lastName,
    required this.fixedPhone,
    required this.cellPhone,
    required this.photoUrl,
    this.diagnosisYear,
    required this.experience,
    required this.specialistName,
    required this.specialistType,
    required this.hospital,
    required this.consultationTime,
    required this.supportGroup,
    required this.isPublic,
  });

  factory UserProfile.fromFirestore(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      name: data['name'] ?? '',
      lastName: data['lastName'] ?? '',
      fixedPhone: data['fixedPhone'] ?? '',
      cellPhone: data['cellPhone'] ?? '',
      photoUrl: data['photoUrl'] ?? '',
      diagnosisYear: data['diagnosisYear'],
      experience: data['experience'] ?? '',
      specialistName: data['specialistName'] ?? '',
      specialistType: data['specialistType'] ?? 'Neurología',
      hospital: data['hospital'] ?? '',
      consultationTime: data['consultationTime'] ?? '',
      supportGroup: data['supportGroup'] ?? '',
      isPublic: data['isPublic'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'lastName': lastName,
      'fixedPhone': fixedPhone,
      'cellPhone': cellPhone,
      'photoUrl': photoUrl,
      'diagnosisYear': diagnosisYear,
      'experience': experience,
      'specialistName': specialistName,
      'specialistType': specialistType,
      'hospital': hospital,
      'consultationTime': consultationTime,
      'supportGroup': supportGroup,
      'isPublic': isPublic,
    };
  }
}
