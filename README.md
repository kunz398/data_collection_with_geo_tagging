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
