import 'package:flutter/material.dart';
import 'package:dart_ping/dart_ping.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('pingResults');
  runApp(PingApp());
}

class PingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Host Pinger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: PingScreen(),
    );
  }
}

class PingScreen extends StatefulWidget {
  @override
  _PingScreenState createState() => _PingScreenState();
}

class _PingScreenState extends State<PingScreen> {
  final TextEditingController _hostController = TextEditingController();
  bool _isPinging = false;
  List<Map<String, dynamic>> _results = [];

  // Ping a host
  void _pingHost(String host) async {
    setState(() {
      _isPinging = true;
    });

    try {
      final ping = Ping(host, count: 4); // Ping 4 times
      String combinedResults = '';
      int successCount = 0;

      await for (final PingData data in ping.stream) {
        combinedResults += data.toString() + '\n';

        if (data.response != null && data.response!.ip != null) {
          successCount++;
        }
      }

      // Determine the status code
      int statusCode;
      if (successCount == 4) {
        statusCode = 200; // All pings succeeded
      } else if (successCount > 1) {
        statusCode = 300; // Partial success
      } else {
        statusCode = 400; // All pings failed
      }

      // Save to Hive
      final box = Hive.box('pingResults');
      box.add({
        'host': host,
        'timestamp': DateTime.now().toString(),
        'result': combinedResults,
        'status': statusCode.toString(),
        'isExpanded': false, // Track expanded state
      });

      // Keep only the last 10 results
      if (box.length > 10) {
        box.deleteAt(0);
      }

      _refreshResults();
    } catch (e) {
      final box = Hive.box('pingResults');
      box.add({
        'host': host,
        'timestamp': DateTime.now().toString(),
        'result': 'Ping failed: $e',
        'status': '500',
        'isExpanded': false,
      });
      _refreshResults();
    } finally {
      setState(() {
        _isPinging = false;
      });
    }
  }

  // Clear all results
  void _clearResults() {
    final box = Hive.box('pingResults');
    box.clear();
    setState(() {
      _results.clear();
    });
  }

  // Refresh results from Hive
  void _refreshResults() {
    final box = Hive.box('pingResults');
    final data = List.generate(
      box.length,
          (index) {
        final entry = box.getAt(box.length - 1 - index);
        return Map<String, dynamic>.from(entry);
      },
    );

    setState(() {
      _results = data;
    });
  }

  @override
  void initState() {
    super.initState();
    _refreshResults(); // Load initial results
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Host Pinger'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _hostController,
              decoration: InputDecoration(
                labelText: 'Enter Host',
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () {
                    _hostController.clear();
                  },
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _clearResults,
                  icon: Icon(Icons.delete),
                  label: Text('Clear All Results'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[100], // Optional: change button color
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[100], disabledBackgroundColor: Colors.yellow[100]),
                  onPressed: _isPinging
                      ? null
                      : () {
                    final host = _hostController.text;
                    if (host.isNotEmpty) {
                      _pingHost(host);
                    }
                  },
                  child: Text(_isPinging ? 'Pinging...' : 'Ping'),
                ),
              ],
            ),
            SizedBox(height: 10),
            Expanded(
              child: _results.isEmpty
                  ? Center(child: Text("No saved results."))
                  : SingleChildScrollView(
                child: ExpansionPanelList(
                  elevation: 1,
                  expandedHeaderPadding: EdgeInsets.all(8.0),
                  expansionCallback: (index, isExpanded) {
                    setState(() {
                      _results[index]['isExpanded'] =
                      !_results[index]['isExpanded'];
                    });
                  },
                  children: _results.map((result) {
                    return ExpansionPanel(
                      isExpanded: result['isExpanded'],
                      headerBuilder: (context, isExpanded) {
                        return ListTile(
                          title: Text(result['host']),
                          subtitle: Text("Status: ${result['status']}"),
                        );
                      },
                      body: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Host: ${result['host']}',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 8),
                            Text('Status: ${result['status']}'),
                            SizedBox(height: 8),
                            Text('Timestamp: ${result['timestamp']}'),
                            Divider(),
                            Text('Details:\n${result['result']}'),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
