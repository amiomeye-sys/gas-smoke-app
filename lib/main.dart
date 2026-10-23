import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gas Smoke Simulator',
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
  final TextEditingController secretKeyController = TextEditingController();
  bool isActivated = false;

  @override
  void initState() {
    super.initState();
    generateRandomNo();
  }

  void generateRandomNo() {
    final random = Random();
    setState(() {
      randomNo = random.nextInt(8999) + 1000;
    });
  }

  double kval(double hu) {
    double num = -0.002325;
    double num2 = log(1.0 - hu / 100.0);
    return num * num2 * 1000.0;
  }

  Map<String, dynamic> getRandomPetrolData() {
    final random = Random();
    String co = "${random.nextInt(1) + 1}.${random.nextInt(89) + 10}";
    String co2 =
        "${(random.nextInt(5) + 7).toString().padLeft(2, '0')}.${random.nextInt(10)}";
    String hc = "${random.nextInt(1700) + 300}";
    String o2 =
        "${random.nextInt(5) + 9}.${(random.nextInt(49) + 1).toString().padLeft(2, '0')}";

    return {
      "CO": co,
      "CO2": co2,
      "Date":
          "${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}",
      "HC": hc,
      "Lambda": "6.525",
      "Lambda_CO": co,
      "O2": o2,
      "RPM": "0000",
      "Status": "OK",
      "Time":
          "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
      "Reserve": "8",
    };
  }

  Map<String, dynamic> getRandomDieselData() {
    final random = Random();
    int num = random.nextInt(12) + 8;
    double hu = (num + num + num) / 3.0;
    double p5 = kval(num.toDouble());

    return {
      "Date":
          "${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().year}",
      "Test1": "TR01;${p5.toStringAsFixed(3)};750;2500;31",
      "Test_AVG": "#TA;${kval(hu).toStringAsFixed(3)}",
      "Test_Status": "#TS0",
      "Status": "OK",
      "Time":
          "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
    };
  }

  String getURLContents(String uri) {
    Map<String, dynamic> data = {};
    if (uri == "/i3sys/gas") {
      if (selectedFuelType == '2or3wheeler') {
        data = getRandomPetrolData();
      } else if (selectedFuelType == 'bs3') {
        data = getRandomPetrolData();
      }
    } else if (uri == "/i3sys/smoke") {
      if (selectedFuelType == 'diesel') {
        data = getRandomDieselData();
      }
    }
    return jsonEncode(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gas Smoke App")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                          title: const Text('2 or 3 wheeler',
                              style: TextStyle(fontSize: 12)),
                          value: '2or3wheeler',
                          groupValue: selectedFuelType,
                          onChanged: (val) =>
                              setState(() => selectedFuelType = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('4 wheeler bs3',
                              style: TextStyle(fontSize: 12)),
                          value: 'bs3',
                          groupValue: selectedFuelType,
                          onChanged: (val) =>
                              setState(() => selectedFuelType = val!),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Lambda',
                              style: TextStyle(fontSize: 12)),
                          value: 'lambda',
                          groupValue: selectedFuelType,
                          onChanged: (val) =>
                              setState(() => selectedFuelType = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Diesel',
                              style: TextStyle(fontSize: 12)),
                          value: 'diesel',
                          groupValue: selectedFuelType,
                          onChanged: (val) =>
                              setState(() => selectedFuelType = val!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!isActivated)
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Please Activate Software",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text("Please Enter Secret Key"),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(randomNo.toString(),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: secretKeyController,
                            obscureText: true,
                            decoration: const InputDecoration(
                                border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              isActivated = true;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text("Product Activated")),
                            );
                          },
                          child: const Text("Go"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            const Text("Generated JSON Output Test:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.black12,
                child: SingleChildScrollView(
                  child: Text(
                    getURLContents(selectedFuelType == 'diesel'
                        ? '/i3sys/smoke'
                        : '/i3sys/gas'),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
