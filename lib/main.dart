import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:exif/exif.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' as pw;
import 'package:pdf/widgets.dart' as pww;
import 'package:printing/printing.dart';

void main() {
  runApp(const InspectionApp());
}

class InspectionApp extends StatelessWidget {
  const InspectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inspection Record Form',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const InspectionFormPage(),
    );
  }
}

class PhotoData {
  final Uint8List bytes;
  final String timeStr;
  final String gpsStr;

  PhotoData({
    required this.bytes,
    required this.timeStr,
    required this.gpsStr,
  });
}

class InspectionFormPage extends StatefulWidget {
  const InspectionFormPage({super.key});

  @override
  State<InspectionFormPage> createState() => _InspectionFormPageState();
}

class _InspectionFormPageState extends State<InspectionFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _projectNoController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final _startTimeController = TextEditingController();
  final _endTimeController = TextEditingController();
  final _inspectionTypeController = TextEditingController(text: 'General');
  final _itemInspectedController = TextEditingController();
  final _findingsController = TextEditingController(text: 'Please refer to the photos attached');
  final _actionTakenController = TextEditingController();
  final _witnessingPartiesController = TextEditingController(text: 'Nil');

  // General Conditions
  final Map<String, String> _generalConditions = {
    'A. Site Safety (Including Accident/Fire Prevention, Environment/Hygiene/First-Aid At Workplace, Manual Handling And F&IU Regulations If Applicable)': 'Yes',
    'B. Site Security/Cleanliness': 'Yes',
    'C. Progress Against The Agreed Programme': 'Yes',
    'D. Environmental Issue/Waste Management': 'Yes',
    'E. Appropriate Workers With Adequate Protection (Including Personal Protective Equipment)': 'Yes',
  };

  final List<PhotoData> _photos = [];
  bool _isGeneratingPdf = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDateController.text = DateFormat('dd/MM/yyyy').format(now);
    _endDateController.text = DateFormat('dd/MM/yyyy').format(now);
    _startTimeController.text = '09:00';
    _endTimeController.text = '10:00';
  }

  // --- Bug Fix: Strict GPS Validation ---
  double? _parseExifGps(IfdTag? tag, IfdTag? refTag) {
    if (tag == null || tag.values == null) return null;
    try {
      final values = tag.values.toList();
      if (values.length < 3) return null;
      
      double parseRatio(dynamic val) {
        if (val is num) return val.toDouble();
        final s = val.toString();
        if (s.contains('/')) {
          final parts = s.split('/');
          final num = double.tryParse(parts[0].trim()) ?? 0.0;
          final den = double.tryParse(parts[1].trim()) ?? 1.0;
          return den == 0 ? 0.0 : num / den;
        }
        return double.tryParse(s) ?? 0.0;
      }

      double degrees = parseRatio(values[0]);
      double minutes = parseRatio(values[1]);
      double seconds = parseRatio(values[2]);

      double result = degrees + (minutes / 60.0) + (seconds / 3600.0);
      
      // Fallback for NaN or infinite coordinates
      if (result.isNaN || result.isInfinite) return null;

      if (refTag != null) {
        String ref = refTag.toString().toUpperCase();
        if (ref.contains('S') || ref.contains('W')) {
          result = -result;
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  // --- Bug Fix: Exception handling for corrupted image bytes ---
  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage();
    
    if (pickedFiles.isEmpty) return;

    for (var file in pickedFiles) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;

        String timeStr = 'N/A';
        String gpsStr = 'N/A';

        try {
          final tags = await readExifFromBytes(bytes);
          
          if (tags.containsKey('Image DateTime')) {
            timeStr = tags['Image DateTime'].toString();
          }

          final lat = _parseExifGps(tags['GPS GPSLatitude'], tags['GPS GPSLatitudeRef']);
          final lon = _parseExifGps(tags['GPS GPSLongitude'], tags['GPS GPSLongitudeRef']);

          if (lat != null && lon != null && lat != 0.0 && lon != 0.0) {
            gpsStr = '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
          }
        } catch (exifError) {
          debugPrint('EXIF parsing failed: $exifError');
        }

        setState(() {
          _photos.add(PhotoData(bytes: bytes, timeStr: timeStr, gpsStr: gpsStr));
        });
      } catch (e) {
        debugPrint('Exception: Could not decompress image - $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load image: ${file.name}')),
          );
        }
      }
    }
  }

  // --- Bug Fix: Robust live location fallback ---
  Future<String> _getSubmissionLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return 'Location services disabled.';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return 'Location permission denied.';
      }
      if (permission == LocationPermission.deniedForever) {
        return 'Location permission permanently denied.';
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
      
      return '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
    } catch (_) {
      return 'Location unavailable.';
    }
  }

  Future<void> _generatePdf() async {
    setState(() => _isGeneratingPdf = true);
    
    final pdf = pww.Document();
    final submissionTime = DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now());
    final liveLocation = await _getSubmissionLocation();
    final footerText = 'Submitted: $submissionTime HKT GPS: $liveLocation';

    // Page 1: Form Data
    pdf.addPage(
      pww.MultiPage(
        pageFormat: pw.PdfPageFormat.a4,
        margin: const pww.EdgeInsets.all(32),
        footer: (context) => pww.Row(
          mainAxisAlignment: pww.MainAxisAlignment.spaceBetween,
          children: [
            pww.Text(footerText, style: const pww.TextStyle(fontSize: 8)),
            pww.Text('OP10-1', style: const pww.TextStyle(fontSize: 8)),
          ],
        ),
        build: (context) => [
          pww.Center(
            child: pww.Text('Inspection Record Form', style: pww.TextStyle(fontSize: 18, fontWeight: pww.FontWeight.bold)),
          ),
          pww.SizedBox(height: 20),
          _buildPdfHeaderData(),
          pww.SizedBox(height: 10),
          _buildPdfGeneralConditions(),
          pww.SizedBox(height: 10),
          _buildPdfTextRow('Item Inspected:', _itemInspectedController.text.isEmpty ? 'Nil' : _itemInspectedController.text),
          _buildPdfTextRow('Inspection Findings/Results:', _findingsController.text),
          _buildPdfTextRow('Action Taken:', _actionTakenController.text.isEmpty ? 'Nil' : _actionTakenController.text),
          _buildPdfTextRow('Other Witnessing Parties (if any):', _witnessingPartiesController.text),
          pww.SizedBox(height: 30),
          pww.Row(
            mainAxisAlignment: pww.MainAxisAlignment.spaceBetween,
            children: [
              pww.Text('Inspected by: ________________________'),
              pww.Text('Approved by: ________________________'),
            ],
          ),
          pww.SizedBox(height: 10),
          pww.Align(
            alignment: pww.Alignment.centerRight,
            child: pww.Text('Signature Date: ________________________'),
          )
        ],
      ),
    );

    // Page 2+: Photos
    if (_photos.isNotEmpty) {
      pdf.addPage(
        pww.MultiPage(
          pageFormat: pw.PdfPageFormat.a4,
          margin: const pww.EdgeInsets.all(32),
          footer: (context) => pww.Row(
            mainAxisAlignment: pww.MainAxisAlignment.spaceBetween,
            children: [
              pww.Text(footerText, style: const pww.TextStyle(fontSize: 8)),
              pww.Text('OP10-1', style: const pww.TextStyle(fontSize: 8)),
            ],
          ),
          build: (context) => [
            pww.Text('Photos Attached', style: pww.TextStyle(fontSize: 14, fontWeight: pww.FontWeight.bold)),
            pww.SizedBox(height: 10),
            pww.Table(
              border: pww.TableBorder.all(),
              children: _photos.asMap().entries.map((entry) {
                int idx = entry.key;
                PhotoData photo = entry.value;
                pww.MemoryImage? memImg;
                
                try {
                  memImg = pww.MemoryImage(photo.bytes);
                } catch (e) {
                  debugPrint('PDF Image parsing error: $e');
                }

                return pww.TableRow(
                  children: [
                    pww.Padding(
                      padding: const pww.EdgeInsets.all(8),
                      child: memImg != null 
                          ? pww.Image(memImg, height: 150, fit: pww.BoxFit.contain)
                          : pww.Text('Image failed to load', style: const pww.TextStyle(color: pw.PdfColors.red)),
                    ),
                    pww.Padding(
                      padding: const pww.EdgeInsets.all(8),
                      child: pww.Column(
                        crossAxisAlignment: pww.CrossAxisAlignment.start,
                        children: [
                          pww.Text('Photo ${idx + 1}', style: pww.TextStyle(fontWeight: pww.FontWeight.bold)),
                          pww.SizedBox(height: 4),
                          pww.Text('Time: ${photo.timeStr}'),
                          pww.Text('GPS: ${photo.gpsStr}'),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      );
    }

    setState(() => _isGeneratingPdf = false);

    await Printing.layoutPdf(
      onLayout: (pw.PdfPageFormat format) async => pdf.save(),
    );
  }

  pww.Widget _buildPdfHeaderData() {
    return pww.Row(
      mainAxisAlignment: pww.MainAxisAlignment.spaceBetween,
      children: [
        pww.Column(
          crossAxisAlignment: pww.CrossAxisAlignment.start,
          children: [
            pww.Text('Project/Contract No.: ${_projectNoController.text}'),
            pww.Text('Start Date: ${_startDateController.text}'),
            pww.Text('Start Time: ${_startTimeController.text}'),
            pww.Text('Inspection Type: ${_inspectionTypeController.text}'),
          ],
        ),
        pww.Column(
          crossAxisAlignment: pww.CrossAxisAlignment.start,
          children: [
            pww.Text('End Date: ${_endDateController.text}'),
            pww.Text('End Time: ${_endTimeController.text}'),
          ],
        ),
      ],
    );
  }

  pww.Widget _buildPdfGeneralConditions() {
    return pww.Column(
      crossAxisAlignment: pww.CrossAxisAlignment.start,
      children: [
        pww.Text('General Conditions', style: pww.TextStyle(fontWeight: pww.FontWeight.bold)),
        pww.SizedBox(height: 5),
        pww.Table(
          border: pww.TableBorder.all(),
          columnWidths: {
            0: const pww.FlexColumnWidth(3),
            1: const pww.FlexColumnWidth(1),
            2: const pww.FlexColumnWidth(1),
          },
          children: [
            pww.TableRow(
              children: ['Item', 'Satisfactory', 'Remarks'].map((t) => pww.Padding(
                padding: const pww.EdgeInsets.all(4), 
                child: pww.Text(t, style: pww.TextStyle(fontWeight: pww.FontWeight.bold))
              )).toList(),
            ),
            ..._generalConditions.entries.map((e) => pww.TableRow(
              children: [
                pww.Padding(padding: const pww.EdgeInsets.all(4), child: pww.Text(e.key, style: const pww.TextStyle(fontSize: 8))),
                pww.Padding(padding: const pww.EdgeInsets.all(4), child: pww.Center(child: pww.Text(e.value))),
                pww.Padding(padding: const pww.EdgeInsets.all(4), child: pww.Text('')),
              ],
            )),
          ],
        ),
      ],
    );
  }

  pww.Widget _buildPdfTextRow(String label, String value) {
    return pww.Padding(
      padding: const pww.EdgeInsets.only(top: 8),
      child: pww.Column(
        crossAxisAlignment: pww.CrossAxisAlignment.start,
        children: [
          pww.Text(label, style: pww.TextStyle(fontWeight: pww.FontWeight.bold)),
          pww.Text(value),
        ],
      ),
    );
  }

  // --- Bug Fix: UI Overflows solved using Flexible/Expanded ---
  Widget _buildConditionRow(String label) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, // <-- Fixed
      children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Radio<String>(
                value: 'Yes',
                groupValue: _generalConditions[label],
                onChanged: (val) => setState(() => _generalConditions[label] = val!),
              ),
              const Text('Yes'),
              Radio<String>(
                value: 'No',
                groupValue: _generalConditions[label],
                onChanged: (val) => setState(() => _generalConditions[label] = val!),
              ),
              const Text('No'),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspection Record'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              onPressed: _isGeneratingPdf ? null : _generatePdf,
              icon: _isGeneratingPdf 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
              label: const Text('Generate PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // General Conditions Section
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('General Conditions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ..._generalConditions.keys.map((key) => _buildConditionRow(key)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Photos Section
              const Text('Photos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400, width: 1),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade50,
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.camera_alt, size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Tap to take or upload photos', style: TextStyle(fontSize: 16, color: Colors.indigo)),
                      SizedBox(height: 4),
                      Text('EXIF GPS and timestamp captured from photo file (shows N/A if missing)', 
                        textAlign: TextAlign.center, 
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              if (_photos.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _photos.map((photo) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          photo.bytes,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => 
                            Container(
                              width: 100, height: 100, color: Colors.red.shade100,
                              child: const Icon(Icons.broken_image, color: Colors.red),
                            ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _photos.remove(photo);
                            });
                          },
                        ),
                      )
                    ],
                  )).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
