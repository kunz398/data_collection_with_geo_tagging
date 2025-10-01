# SPC Data Collection App

A Flutter-based data collection application with geotagging capabilities, developed for the SPC (Pacific Community) GEM Team for use in Tonga and other Pacific Island nations.

## Features

### Data Collection Form
- **Personal Information**: Name, Date of Birth, Gender, Phone Number, Email
- **Location Information**: Three methods for capturing location data
- **Additional Notes**: Optional field for extra information
- **Local Storage**: SQLite database for offline functionality

### Geotagging Capabilities (3 Methods)
1. **Current Location**: Uses device GPS to get current coordinates
2. **Pin on Map**: Interactive MapLibre map for manual location selection
3. **Address Search**: Text-based address search with geocoding

### Data Management
- **Records List**: View all collected data records
- **Record Details**: Detailed view with map visualization
- **Data Export**: Ready for backend integration
- **Delete Records**: Remove unwanted entries

## Technology Stack

- **Framework**: Flutter 3.x
- **Map Library**: MapLibre GL (Open Source)
- **Database**: SQLite (via sqflite)
- **Location Services**: Geolocator & Geocoding packages
- **Form Management**: Flutter Form Builder
- **Permissions**: Permission Handler

## Getting Started

### Prerequisites
- Flutter SDK (3.9.0 or higher)
- Android Studio / VS Code
- Android SDK / iOS Development Tools

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   flutter run
   ```

### Permissions

The app requires the following permissions:
- **Location Access**: For current location and GPS functionality
- **Internet Access**: For map tiles and geocoding services

## Architecture

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── data_record.dart     # Data model
├── services/
│   ├── database_service.dart # SQLite operations
│   └── location_service.dart # Location utilities
├── screens/
│   ├── data_collection_screen.dart # Main form
│   ├── records_list_screen.dart    # Records listing
│   └── record_detail_screen.dart   # Record details
└── widgets/
    └── location_picker.dart   # Location selection widget
```

## Data Model

Each collected record contains:
- Personal details (name, DOB, gender, contact info)
- Geographic coordinates (latitude, longitude)
- Address information
- Location collection method
- Creation timestamp
- Optional notes

## Future Backend Integration

The app is designed to integrate with a PostgreSQL backend:
- Records stored in local SQLite for offline operation
- Ready for sync with centralized database
- HTTP service layer prepared for API integration
- Data format compatible with national dashboard requirements

## Development Roadmap

### Phase 1 (Current)
- ✅ Basic data collection form
- ✅ Three geotagging methods
- ✅ Local data storage
- ✅ Records management

### Phase 2 (Planned)
- [ ] Backend API integration
- [ ] Data synchronization
- [ ] Patient data form templates (MOH Tonga)
- [ ] Environmental data collection
- [ ] Offline-first architecture improvements

### Phase 3 (Future)
- [ ] Multi-language support
- [ ] Advanced analytics
- [ ] Integration with national dashboard
- [ ] Multi-country deployment

## Contributing

This is an open-source project developed for Pacific Island nations. Contributions are welcome for:
- Feature enhancements
- Bug fixes
- Localization
- Documentation improvements

## License

This project is developed as open-source software for Pacific Island communities.

## Contact

For questions or support, please contact the SPC GEM Team.

---

**Note**: This application supports Tonga's data collection requirements and is designed to eventually integrate with the national dashboard while providing interim data custodianship through SPC. new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
