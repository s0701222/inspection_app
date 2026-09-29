import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:exif/exif.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const InspectionApp());
}

class InspectionApp extends StatelessWidget {
  const InspectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inspection App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const InspectionHomePage(),
    );
  }
}

class InspectionHomePage extends StatefulWidget {
  const InspectionHomePage({super.key});

  @override
  State<InspectionHomePage> createState() => _InspectionHomePageState();
}

class _InspectionHomePageState extends State<InspectionHomePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _inspectorController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  
  File? _imageFile;
  String _gpsCoords = 'No GPS data captured yet';

  // Request runtime permissions including Android media location
  Future<void> _requestPermissions() async {
    await [
      Permission.photos,
      Permission.storage,
      Permission.accessMediaLocation,
    ].request();
  }

  Future<void> _pickImage() async {
    // Ensure permissions are granted before accessing the gallery
    await _requestPermissions();

    final picker = ImagePicker();
    
    // CRITICAL: Do NOT use imageQuality compression, as it strips EXIF metadata!
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
      await _extractExifGps(_imageFile!);
    }
  }

  Future<void> _extractExifGps(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final data = await readExifFromBytes(bytes);

      if (data.isEmpty) {
        setState(() {
          _gpsCoords = 'No EXIF metadata found in image';
        });
        return;
      }

      if (data.containsKey('GPS GPSLatitude') && data.containsKey('GPS GPSLongitude')) {
        final latRef = data['GPS GPSLatitudeRef']?.printable ?? 'N';
        final lonRef = data['GPS GPSLongitudeRef']?.printable ?? 'E';
        
        final latList = data['GPS GPSLatitude']!.values;
        final lonList = data['GPS GPSLongitude']!.values;

        double lat = _convertToDegree(latList);
        if (latRef == 'S') lat = -lat;

        double lon = _convertToDegree(lonList);
        if (lonRef == 'W') lon = -lon;

        setState(() {
          _gpsCoords = 'Lat: ${lat.toStringAsFixed(6)}, Lon: ${lon.toStringAsFixed(6)}';
        });
      } else {
        setState(() {
          _gpsCoords = 'GPS coordinates scrubbed or missing';
        });
      }
    } catch (e) {
      setState(() {
        _gpsCoords = 'Error reading EXIF data: $e';
      });
    }
  }

  double _convertToDegree(List<dynamic> list) {
    double d = _evalRational(list[0]);
    double m = _evalRational(list[1]);
    double s = _evalRational(list[2]);
    return d + (m / 60.0) + (s / 3600.0);
  }

  double _evalRational(dynamic val) {
    if (val.toString().contains('/')) {
      final parts = val.toString().split('/');
      if (parts.length == 2) {
        final numerator = double.tryParse(parts[0]) ?? 0.0;
        final denominator = double.tryParse(parts[1]) ?? 1.0;
        if (denominator != 0) return numerator / denominator;
      }
    }
    return double.tryParse(val.toString()) ?? 0.0;
  }

  Future<void> _generatePdf() async {
    final pdf = pw.Document();
    
    pw.MemoryImage? netImage;
    if (_imageFile != null) {
      final imageBytes = await _imageFile!.readAsBytes();
      netImage = pw.MemoryImage(imageBytes);
    }

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Inspection Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text('Inspector: ${_inspectorController.text}'),
              pw.Text('Location Name: ${_locationController.text}'),
              pw.Text('GPS Coordinates: $_gpsCoords'),
              pw.SizedBox(height: 15),
              if (netImage != null)
                pw.Expanded(
                  child: pw.Image(netImage, fit: pw.BoxFit.contain),
                ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inspection Form')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _inspectorController,
                decoration: const InputDecoration(labelText: 'Inspector Name'),
              ),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Location / Site Name'),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library),
                label: const Text('Pick Photo from Gallery'),
              ),
              const SizedBox(height: 15),
              if (_imageFile != null)
                SizedBox(
                  height: 200,
                  child: Image.file(_imageFile!, fit: BoxFit.cover),
                ),
              const SizedBox(height: 10),
              Text(
                _gpsCoords,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _generatePdf,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(14)),
                child: const Text('Generate & Print PDF Report', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}