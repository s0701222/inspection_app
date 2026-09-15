import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
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
      title: 'Inspection Record Form',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const InspectionFormScreen(),
    );
  }
}

// 照片資料結構模型
class PhotoItem {
  final Uint8List bytes;
  final String timestamp;
  final String gpsLocation;

  PhotoItem({
    required this.bytes,
    required this.timestamp,
    required this.gpsLocation,
  });
}

// 通用條件 (General Condition) 資料模型
class GeneralConditionItem {
  final String code;
  final String title;
  final String description;
  bool isSatisfactory; // true = Yes, false = No
  TextEditingController remarksController;

  GeneralConditionItem({
    required this.code,
    required this.title,
    required this.description,
    this.isSatisfactory = true, // 預設為 Yes
  }) : remarksController = TextEditingController();
}

class InspectionFormScreen extends StatefulWidget {
  const InspectionFormScreen({super.key});

  @override
  State<InspectionFormScreen> createState() => _InspectionFormScreenState();
}

class _InspectionFormScreenState extends State<InspectionFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // 1. 基本資訊控制器 (遵守無預設文字規則)
  final TextEditingController _projectNoController = TextEditingController(); // 預設空白
  
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  TimeOfDay? _startTime; // 預設 --:--
  TimeOfDay? _endTime;   // 預設 --:--

  String _inspectionType = 'General'; // 預設 General

  // 2. General Conditions A - E
  final List<GeneralConditionItem> _conditions = [
    GeneralConditionItem(
      code: 'A',
      title: 'A. Site Safety',
      description: '(including accident/fire prevention, environment/hygiene/first-aid at workplace, manual handling and F&IU regulations if applicable)',
    ),
    GeneralConditionItem(
      code: 'B',
      title: 'B. Site Security/Cleanliness',
      description: '',
    ),
    GeneralConditionItem(
      code: 'C',
      title: 'C. Progress against the agreed programme',
      description: '',
    ),
    GeneralConditionItem(
      code: 'D',
      title: 'D. Environmental issue/Waste Management',
      description: '',
    ),
    GeneralConditionItem(
      code: 'E',
      title: 'E. Appropriate workers with adequate protection',
      description: '(including Personal Protective Equipment)',
    ),
  ];

  // 3. 輸入文字框 (僅指定 3 項預設值，其餘空白)
  final TextEditingController _itemInspectedController = TextEditingController(); // 預設空白
  final TextEditingController _findingsController = TextEditingController(text: 'Please refer to the photos attached'); // 指定預設值
  final TextEditingController _actionTakenController = TextEditingController(text: 'Nil'); // 指定預設值
  final TextEditingController _witnessingPartiesController = TextEditingController(text: 'Nil'); // 指定預設值

  // 照片列表
  final List<PhotoItem> _photos = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLocating = false;

  // 取得即時 GPS 座標輔助函式
  Future<String> _getGpsLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return 'Location unavailable';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return 'Location unavailable';
      }
      if (permission == LocationPermission.deniedForever) return 'Location unavailable';

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 5)),
      );
      return '${position.latitude.toStringAsFixed(6)}°N, ${position.longitude.toStringAsFixed(6)}°E';
    } catch (e) {
      return 'Location unavailable';
    }
  }

  // 拍攝或上傳照片並記錄時間/GPS
  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 80);
    if (pickedFile == null) return;

    setState(() => _isLocating = true);

    final Uint8List bytes = await pickedFile.readAsBytes();
    final String timestamp = DateFormat("dd MMM yyyy, HH:mm 'HKT'").format(DateTime.now());
    final String gps = await _getGpsLocation();

    setState(() {
      _photos.add(PhotoItem(bytes: bytes, timestamp: timestamp, gpsLocation: gps));
      _isLocating = false;
    });
  }

  // 選取日期
  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  // 選取時間
  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  // 格式化時間顯示
  String _formatTimeOfDay(TimeOfDay? time) {
    if (time == null) return '--:--';
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('HH:mm').format(dt);
  }

  // 產出 PDF 報表邏輯
  Future<void> _generatePdf() async {
    final pdf = pw.Document();

    // 取得提交當下的時間與 GPS
    final String submitTime = DateFormat("dd MMM yyyy, HH:mm 'HKT'").format(DateTime.now());
    final String submitGps = await _getGpsLocation();

    final String startDateStr = DateFormat('dd MMM yyyy').format(_startDate);
    final String endDateStr = DateFormat('dd MMM yyyy').format(_endDate);
    final String dateRangeStr = (startDateStr == endDateStr) ? startDateStr : '$startDateStr – $endDateStr';
    final String timeRangeStr = '${_formatTimeOfDay(_startTime)} – ${_formatTimeOfDay(_endTime)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (pw.Context context) {
          return pw.Row(
            mainpw: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Submitted: $submitTime · GPS: $submitGps',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
              pw.Text(
                'OP10-1',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            // 標題
            pw.Text(
              'Inspection Record Form',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),

            // 基本資訊表格
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              children: [
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Project/Contract No.: ${_projectNoController.text}', style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Inspection Date:\n$dateRangeStr', style: const pw.TextStyle(fontSize: 9)),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Time: $timeRangeStr', style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Inspection Type: $_inspectionType', style: const pw.TextStyle(fontSize: 9)),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),

            // General Conditions 表格
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3.5),
                1: const pw.FlexColumnWidth(1.0),
                2: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('General Conditions', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Satisfactory', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Remarks', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                ..._conditions.map((cond) {
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Column(
                          crosspw: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(cond.title, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                            if (cond.description.isNotEmpty)
                              pw.Text(cond.description, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(cond.isSatisfactory ? 'Yes' : 'No', style: const pw.TextStyle(fontSize: 8)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(cond.remarksController.text, style: const pw.TextStyle(fontSize: 8)),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 10),

            // 項目文字欄位
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
              child: pw.Column(
                crosspw: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Item Inspected:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_itemInspectedController.text, style: const pw.TextStyle(fontSize: 9)),
                  pw.SizedBox(height: 6),
                  pw.Text('Inspection Findings/Results:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_findingsController.text, style: const pw.TextStyle(fontSize: 9)),
                  pw.SizedBox(height: 6),
                  pw.Text('Action Taken:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_actionTakenController.text, style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // 簽名欄位區域
            pw.Container(
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
              child: pw.Row(
                mainpw: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Inspected by:', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('Signed by:', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('Signature Date:', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // Witnessing Parties
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
              child: pw.Column(
                crosspw: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Other Witnessing Parties (if any):', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(_witnessingPartiesController.text, style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.SizedBox(height: 15),

            // 照片附件頁面 (Photos Attached)
            if (_photos.isNotEmpty) ...[
              pw.Header(level: 1, text: 'Photos Attached', textStyle: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              ...List.generate(_photos.length, (index) {
                final item = _photos[index];
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 12),
                  child: pw.Row(
                    crosspw: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 160,
                        height: 120,
                        child: pw.Image(pw.MemoryImage(item.bytes), fit: pw.BoxFit.cover),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Column(
                        crosspw: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Photo ${index + 1}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text('Time: ${item.timestamp}', style: const pw.TextStyle(fontSize: 8)),
                          pw.Text('GPS: ${item.gpsLocation}', style: const pw.TextStyle(fontSize: 8)),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ];
        },
      ),
    );

    // 啟動列印/分享/儲存 PDF 預覽視窗
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    final String startDateStr = DateFormat('dd/MM/yyyy').format(_startDate);
    final String endDateStr = DateFormat('dd/MM/yyyy').format(_endDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspection Record Form', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ElevatedButton.icon(
              onPressed: _generatePdf,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Generate PDF'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
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
              // Project/Contract No.
              const Text('Project/Contract No. *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              TextFormField(
                controller: _projectNoController,
                decoration: const InputDecoration(
                  hintText: 'e.g. HK/2026/0042',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),

              // Date & Time Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Start Date'),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _selectDate(context, true),
                          child: InputDecorator(
                            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [Text(startDateStr), const Icon(Icons.calendar_today, size: 16)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('End Date'),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _selectDate(context, false),
                          child: InputDecorator(
                            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [Text(endDateStr), const Icon(Icons.calendar_today, size: 16)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Start Time'),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _selectTime(context, true),
                          child: InputDecorator(
                            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [Text(_formatTimeOfDay(_startTime)), const Icon(Icons.access_time, size: 16)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('End Time'),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _selectTime(context, false),
                          child: InputDecorator(
                            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [Text(_formatTimeOfDay(_endTime)), const Icon(Icons.access_time, size: 16)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Inspection Type Dropdown
              const Text('Inspection Type'),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: _inspectionType,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                items: ['General', 'Safety', 'Environmental', 'Special']
                    .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (val) => setState(() => _inspectionType = val!),
              ),
              const SizedBox(height: 16),

              // General Conditions 區塊
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('General Conditions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    ..._conditions.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (item.description.isNotEmpty)
                              Text(item.description, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                            Row(
                              children: [
                                Radio<bool>(
                                  value: true,
                                  groupValue: item.isSatisfactory,
                                  onChanged: (val) => setState(() => item.isSatisfactory = val!),
                                ),
                                const Text('Yes'),
                                Radio<bool>(
                                  value: false,
                                  groupValue: item.isSatisfactory,
                                  onChanged: (val) => setState(() => item.isSatisfactory = val!),
                                ),
                                const Text('No'),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: item.remarksController,
                                    decoration: const InputDecoration(
                                      hintText: 'Remarks',
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Item Inspected
              const Text('Item Inspected'),
              const SizedBox(height: 4),
              TextFormField(
                controller: _itemInspectedController,
                maxLines: 2,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),

              // Inspection Findings/Results
              const Text('Inspection Findings/Results'),
              const SizedBox(height: 4),
              TextFormField(
                controller: _findingsController,
                maxLines: 2,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),

              // Action Taken
              const Text('Action Taken'),
              const SizedBox(height: 4),
              TextFormField(
                controller: _actionTakenController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),

              // Other Witnessing Parties
              const Text('Other Witnessing Parties (if any)'),
              const SizedBox(height: 4),
              TextFormField(
                controller: _witnessingPartiesController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),

              // Photos 上傳區塊
              const Text('Photos'),
              const SizedBox(height: 6),
              InkWell(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Wrap(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.camera_alt),
                            title: const Text('Take Photo'),
                            onTap: () {
                              Navigator.pop(ctx);
                              _pickImage(ImageSource.camera);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.photo_library),
                            title: const Text('Choose from Gallery'),
                            onTap: () {
                              Navigator.pop(ctx);
                              _pickImage(ImageSource.gallery);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue.shade300, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.blue.shade50.withOpacity(0.3),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.camera_alt_outlined, color: Colors.blue, size: 32),
                      const SizedBox(height: 8),
                      const Text('Tap to take or upload photos', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('GPS and time captured — photos stay on your device until the PDF is made', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      if (_isLocating) ...[
                        const SizedBox(height: 8),
                        const CircularProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),

              // 已上傳照片預覽列表
              if (_photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _photos.length,
                  itemBuilder: (ctx, idx) {
                    final p = _photos[idx];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Image.memory(p.bytes, width: 50, height: 50, fit: BoxFit.cover),
                        title: Text('Photo ${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text('Time: ${p.timestamp}\nGPS: ${p.gpsLocation}', style: const TextStyle(fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => setState(() => _photos.removeAt(idx)),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
