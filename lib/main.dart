import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gas Smoke Simulator Server',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const FuelFormScreen(),
    );
  }
}

class FuelFormScreen extends StatefulWidget {
  const FuelFormScreen({super.key});

  @override
  State<FuelFormScreen> createState() => FuelFormScreenState();
}

class FuelFormScreenState extends State<FuelFormScreen> {
  String selectedFuelType = '2or3wheeler';
  int randomNo = 1000;
  final TextEditingController licenseKeyController = TextEditingController();
  bool isActivated = false;
  bool isLoading = true;
  HttpServer? _server;
  String serverStatus = 'Server Starting...';
  List<String> logMessages = [];
  String lastSentData = 'No data sent yet';
  String deviceId = '';
  int lambdaCount = 0;

  @override
  void initState() {
    super.initState();
    generateRandomNo();
    initializeDeviceAndCheckLicense();
    startLocalServer();
  }

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  void generateRandomNo() {
    final random = Random();
    setState(() {
      randomNo = random.nextInt(8999) + 1000;
    });
  }

  Future<void> initializeDeviceAndCheckLicense() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id; // Unique Hardware ID
      } else {
        deviceId = "NON_ANDROID_DEVICE";
      }

      // Prothome local check
      final prefs = await SharedPreferences.getInstance();
      bool localActivated = prefs.getBool('is_activated') ?? false;
      String? expiryStr = prefs.getString('expiry_date');

      if (localActivated && expiryStr != null) {
        DateTime expiryDate = DateTime.parse(expiryStr);
        if (DateTime.now().isBefore(expiryDate)) {
          setState(() {
            isActivated = true;
            isLoading = false;
          });
          return;
        }
      }

      // Online Firestore Check
      await verifyLicenseOnline(silent: true);
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> verifyLicenseOnline({bool silent = false}) async {
    String key = licenseKeyController.text.trim();
    if (key.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      key = prefs.getString('saved_license_key') ?? '';
    }

    if (key.isEmpty) {
      setState({
        isLoading = false,
        isActivated = false,
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('licenses').doc(key).get();

      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;
        String registeredDevice = data['device_id'] ?? '';
        Timestamp expiryTimestamp = data['expiry_date'];
        DateTime expiryDate = expiryTimestamp.toDate();

        // Device Binding Check: Jodi device ID empty thake, tahole ei current device ID-ti bind kore nebo
        if (registeredDevice.isEmpty) {
          await FirebaseFirestore.instance.collection('licenses').doc(key).update({
            'device_id': deviceId,
          });
          registeredDevice = deviceId;
        }

        // Check if device matches and not expired
        if (registeredDevice == deviceId && DateTime.now().isBefore(expiryDate)) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_activated', true);
          await prefs.setString('expiry_date', expiryDate.toIso8601String());
          await prefs.setString('saved_license_key', key);

          setState(() {
            isActivated = true;
            isLoading = false;
          });

          if (!silent) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("License Verified Successfully Online!")),
            );
          }
        } else {
          setState(() {
            isActivated = false;
            isLoading = false;
          });
          if (!silent) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Invalid Device or License Expired!")),
            );
          }
        }
      } else {
        setState(() {
          isActivated = false;
          isLoading = false;
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("License Key not found in server!")),
          );
        }
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connection Error: $e")),
        );
      }
    }
  }

  Future<void> startLocalServer() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 5555);
      setState(() {
        serverStatus = 'Server Running on port 5555';
      });

      _server!.listen((HttpRequest request) {
        String path = request.uri.path;
        addLog('Incoming request: $path');
        
        String jsonResponse = getURLContents(path);
        
        request.response
          ..headers.contentType = ContentType.json
          ..headers.add('Access-Control-Allow-Origin', '*')
          ..headers.set('Server', 'Microsoft-HTTPAPI/2.0')
          ..write(jsonResponse)
          ..close();
      });
    } catch (e) {
      setState(() {
        serverStatus = 'Server Error: $e';
      });
    }
  }

  void addLog(String msg) {
    setState(() {
      logMessages.insert(0, '${DateTime.now().toLocal().toString().split('.').first}: $msg');
      if (logMessages.length > 50) logMessages.removeLast();
    });
  }

  double kval(double hu) {
    double numVal = -0.002325;
    double num2 = log(1.0 - hu / 100.0);
    return numVal * num2 * 1000.0;
  }

  double lambdaCalc(String coStr, String co2Str, String hcStr, String o2Str) {
    try {
      double co = double.parse(coStr);
      double co2 = double.parse(co2Str);
      double hc = double.parse(hcStr);
      double o2 = double.parse(o2Str);

      double num = co2 + co / 2.0 + o2;
      double num2 = 0.43 * (3.5 / (3.5 + (co / co2))) - 0.00875;
      double num3 = co + co2;
      double num4 = 1.422775 * (num3 + 0.0006 * hc);
      double num5 = (num + num2 * num3) / num4;
      return num5;
    } catch (e) {
      return 6.525;
    }
  }

  Map<String, dynamic> getRandomPetrolData() {
    final random = Random();
    String co = "${random.nextInt(1) + 1}.${random.nextInt(89) + 10}";
    String co2 = "${(random.nextInt(5) + 7).toString().padLeft(2, '0')}.${random.nextInt(10)}${random.nextInt(10)}";
    String hc = "${random.nextInt(1700) + 300}";
    String o2 = "${random.nextInt(5) + 9}.${(random.nextInt(49) + 1).toString().padLeft(2, '0')}";

    return {
      "CO": co,
      "CO2": co2,
      "Date": "${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}",
      "HC": hc,
      "Lambda": "6.525",
      "Lambda_CO": co,
      "O2": o2,
      "RPM": "0000",
      "Status": "OK",
      "Time": "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
      "Reserve": "8",
    };
  }

  Map<String, dynamic> getRandomBs3PetrolData() {
    final random = Random();
    String co = "0.${random.nextInt(30) + 10}";
    String co2 = "${random.nextInt(2) + 13}.${random.nextInt(10)}${random.nextInt(10)}";
    String hc = "${random.nextInt(500) + 150}";
    String o2 = "${random.nextInt(4) + 1}.${random.nextInt(50).toString().padLeft(2, '0')}";

    return {
      "CO": co,
      "CO2": co2,
      "Date": "${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}",
      "HC": hc,
      "Lambda": "6.553",
      "Lambda_CO": co,
      "O2": o2,
      "RPM": "0000",
      "Status": "OK",
      "Time": "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
      "Reserve": "8",
    };
  }

  Map<String, dynamic> getRandomLambdaIdleData() {
    final random = Random();
    String co = "0.${random.nextInt(10) + 10}";
    String co2 = "${random.nextInt(2) + 13}.${random.nextInt(10)}${random.nextInt(10)}";
    String hc = "${random.nextInt(190) + 10}";
    String o2 = "0.${random.nextInt(50).toString().padLeft(2, '0')}";
    double lam = lambdaCalc(co, co2, hc, o2);

    return {
      "CO": co,
      "CO2": co2,
      "Date": "${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}",
      "HC": hc,
      "Lambda": lam.toStringAsFixed(4),
      "Lambda_CO": "0.15",
      "O2": o2,
      "RPM": "${random.nextInt(300) + 2350}",
      "Status": "OK",
      "Time": "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
      "Reserve": "8",
    };
  }

  Map<String, dynamic> getRandomLambdaHighData() {
    final random = Random();
    String co = "0.${random.nextInt(10) + 10}";
    String co2 = "${random.nextInt(2) + 13}.${random.nextInt(10)}${random.nextInt(10)}";
    String hc = "${random.nextInt(190) + 10}";
    String o2 = "0.${random.nextInt(50).toString().padLeft(2, '0')}";
    double lam = lambdaCalc(co, co2, hc, o2);

    return {
      "CO": co,
      "CO2": co2,
      "Date": "${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}",
      "HC": hc,
      "Lambda": lam.toStringAsFixed(4),
      "Lambda_CO": co,
      "O2": o2,
      "RPM": "${random.nextInt(400) + 2300}",
      "Status": "OK",
      "Time": "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
      "Reserve": "8",
    };
  }

  Map<String, dynamic> getRandomDieselData() {
    final random = Random();
    int num = random.nextInt(12) + 8;
    double num2 = (random.nextInt(5) + num).toDouble();
    double num3 = (random.nextInt(5) + num).toDouble();
    double num4 = (random.nextInt(5) + num).toDouble();
    double hu = (num2 + num3 + num4) / 3.0;
    double p5 = kval(num2);
    double p6 = kval(num3);
    double p7 = kval(num4);
    double huVal = kval(hu);

    int r1 = random.nextInt(2500) + 2500;
    int r2 = r1 + random.nextInt(300);
    int r3 = r1 + random.nextInt(300);

    int t1 = random.nextInt(10) + 750;
    int t2 = t1 + random.nextInt(10);
    int t3 = t1 + random.nextInt(10);
    int avgT = (t1 + t2 + t3) ~/ 3;
    int avgR = (r1 + r2 + r3) ~/ 3;

    return {
      "Date": "${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}",
      "Test1": "TR01;${p5.toStringAsFixed(3)};$t1;$r1;31",
      "Test2": "TR02;${p6.toStringAsFixed(3)};$t2;$r2;31",
      "Test3": "TR03;${p7.toStringAsFixed(3)};$t3;$r3;31",
      "Test_AVG": "#TA;${huVal.toStringAsFixed(3)}",
      "Test_Status": "#TS0",
      "Flush_Cyl": "#PT;$avgT;$avgR;31",
      "Status": "OK",
      "Time": "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
    };
  }

  String getURLContents(String uri) {
    if (!isActivated) {
      setState(() {
        lastSentData = "Blocked: App is locked! Online License required.";
      });
      return jsonEncode({"error": "App is locked. Remote authentication required."});
    }

    Map<String, dynamic> data = {};
    
    if (uri == "/i3sys/gas") {
      if (selectedFuelType == 'diesel') {
        setState(() {
          lastSentData = "Blocked: Gas requested but Diesel selected!";
        });
        return jsonEncode({"error": "Invalid fuel type selection for gas endpoint"});
      }

      if (selectedFuelType == '2or3wheeler') {
        data = getRandomPetrolData();
      } else if (selectedFuelType == 'bs3') {
        data = getRandomBs3PetrolData();
      } else if (selectedFuelType == 'lambda') {
        if (lambdaCount > 1) lambdaCount = 0;
        if (lambdaCount == 0) {
          data = getRandomLambdaIdleData();
        } else {
          data = getRandomLambdaHighData();
        }
        lambdaCount++;
      }
    } else if (uri == "/i3sys/smoke") {
      if (selectedFuelType != 'diesel') {
        setState(() {
          lastSentData = "Blocked: Smoke requested but Gas/Lambda selected!";
        });
        return jsonEncode({"error": "Invalid fuel type selection for smoke endpoint"});
      }

      if (selectedFuelType == 'diesel') {
        data = getRandomDieselData();
      }
    } else {
      return jsonEncode({"error": "Unknown endpoint"});
    }

    String finalJson = jsonEncode(data);
    setState(() {
      lastSentData = finalJson;
    });

    return finalJson;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gas Smoke App Server (Secure)")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      border: Border.all(color: Colors.green),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Text(serverStatus, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
                  ),
                  const SizedBox(height: 10),
                  
                  // License Input Box (Jodi activated na thake)
                  if (!isActivated) ...[
                    Container(
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8.0),
                        color: Colors.red.shade50,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("App Locked! Enter Online License Key:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: licenseKeyController,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    hintText: 'Enter License Key (e.g. CLIENT001)',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: () => verifyLicenseOnline(silent: false),
                                child: const Text("Activate"),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text("Device ID: $deviceId", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Jodi license active thake, tobei fuel selection options gulo show korbe
                  if (isActivated) ...[
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('2 or 3 wheeler', style: TextStyle(fontSize: 12)),
                                  value: '2or3wheeler',
                                  groupValue: selectedFuelType,
                                  onChanged: (val) => setState(() => selectedFuelType = val!),
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('4 wheeler bs3', style: TextStyle(fontSize: 12)),
                                  value: 'bs3',
                                  groupValue: selectedFuelType,
                                  onChanged: (val) => setState(() => selectedFuelType = val!),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('Lambda', style: TextStyle(fontSize: 12)),
                                  value: 'lambda',
                                  groupValue: selectedFuelType,
                                  onChanged: (val) => setState(() => selectedFuelType = val!),
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('Diesel', style: TextStyle(fontSize: 12)),
                                  value: 'diesel',
                                  groupValue: selectedFuelType,
                                  onChanged: (val) => setState(() => selectedFuelType = val!),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text("Last Sent Data to Website:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 5),
                    Container(
                      height: 70,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        border: Border.all(color: Colors.blue.shade200),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: SingleChildScrollView(
                        child: Text(lastSentData, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  const Text("Incoming Server Requests Log:", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8.0),
                      color: Colors.black12,
                      child: ListView.builder(
                        itemCount: logMessages.length,
                        itemBuilder: (context, index) {
                          return Text(logMessages[index], style: const TextStyle(fontFamily: 'monospace', fontSize: 11));
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
