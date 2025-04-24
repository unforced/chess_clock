import 'dart:async';
import 'dart:io'; // Import Platform
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart'; // Import device_info_plus
import 'dart:convert'; // Import for jsonDecode
import 'dart:typed_data'; // Import for Uint8List and BytesBuilder
import 'package:tuple/tuple.dart'; // Keep tuple if needed elsewhere, maybe not required now

// BLE Specifications from BLE_SPECS.md
const String targetDeviceName = "ChessClock";
final Guid serviceUuid = Guid("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
final Guid characteristicUuid = Guid("beb5483e-36e1-4688-b7f5-ea07361b26a8");

// Define a class to hold turn history data
class TurnData {
  final int turnNumber;
  final int playerMoved; // 0 = initial/reset, 1 = P1 moved, 2 = P2 moved
  final int p1TimeSec;
  final int p2TimeSec;
  Uint8List? imageBytes; // Make image bytes mutable or recreate TurnData?
                       // Let's make it mutable for simplicity here.

  TurnData({
    required this.turnNumber,
    required this.playerMoved,
    required this.p1TimeSec,
    required this.p2TimeSec,
    this.imageBytes,
  });

  @override
  String toString() {
    String formatTime(int totalSeconds) {
      int minutes = totalSeconds ~/ 60;
      int seconds = totalSeconds % 60;
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    String imageStatus = imageBytes == null ? "" : " (Image: ${imageBytes!.lengthInBytes} bytes)";
    return 'Turn $turnNumber: P$playerMoved moved (P1: ${formatTime(p1TimeSec)}, P2: ${formatTime(p2TimeSec)})$imageStatus';
  }
}

enum BleConnectionStatus { disconnected, scanning, connecting, connected }

class BleService with ChangeNotifier {
  BleConnectionStatus _connectionStatus = BleConnectionStatus.disconnected;
  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _notificationSubscription; // For characteristic notifications
  BluetoothCharacteristic? _targetCharacteristic;

  String _lastMessage = "N/A";

  // --- Game State Variables ---
  int? _lastPlayerMoved;
  int _player1Time = 0;
  int _player2Time = 0;
  final List<TurnData> _turnHistory = [];
  int _turnCounter = 0;
  final List<List<TurnData>> _gameHistoryLog = []; // To store completed games

  // --- Countdown Timers ---
  Timer? _p1Timer;
  Timer? _p2Timer;

  // --- Image Reception State ---
  bool _isReceivingImage = false;
  int _expectedImageSize = 0;
  BytesBuilder _imageBytesBuilder = BytesBuilder();
  Uint8List? _latestImageBytes; // Holds the most recently completed image

  // --- Public Getters for Game State ---
  BleConnectionStatus get connectionStatus => _connectionStatus;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  String get lastMessage => _lastMessage;
  int? get lastPlayerMoved => _lastPlayerMoved; // Whose turn just *ended*
  int get player1Time => _player1Time;
  int get player2Time => _player2Time;
  List<TurnData> get turnHistory => List.unmodifiable(_turnHistory); // Read-only view
  int get currentTurnPlayer => (_lastPlayerMoved == 1) ? 2 : 1; // Whose turn is it *now*
  List<List<TurnData>> get gameHistoryLog => List.unmodifiable(_gameHistoryLog); // Read-only view
  Uint8List? get latestImageBytes => _latestImageBytes;

  BleService() {
    // Listen to adapter state changes
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      if (kDebugMode) {
        print('Adapter State Changed: $state');
      }
      if (state == BluetoothAdapterState.off) {
        _cleanupConnection();
        _updateStatus(BleConnectionStatus.disconnected, notify: true);
      }
      // You might want to prompt the user to turn on Bluetooth here
    });
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      var androidInfo = await DeviceInfoPlugin().androidInfo;
      Map<Permission, PermissionStatus> statuses;

      if (androidInfo.version.sdkInt <= 30) { // Android 11 or lower
        statuses = await [
          Permission.bluetooth,
          Permission.locationWhenInUse, // Fine location needed for scanning
        ].request();
      } else { // Android 12 or higher
        statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse, // Still potentially needed
        ].request();
      }
      if (kDebugMode) {
        print("Permission Statuses: $statuses");
      }
      // Check if all necessary permissions are granted
      bool permissionsGranted = statuses.values.every((status) => status.isGranted);
      if (!permissionsGranted) {
        throw Exception("Bluetooth permissions not granted");
      }
    }
    // Add iOS permission requests here if needed in the future
  }


  void _updateStatus(BleConnectionStatus status, {bool notify = true}) {
    _connectionStatus = status;
    if (notify) notifyListeners();
  }

  Future<void> startScan() async {
    if (_connectionStatus != BleConnectionStatus.disconnected) return; // Don't scan if already busy

    await _requestPermissions(); // Request permissions before scanning

    _updateStatus(BleConnectionStatus.scanning);
    if (kDebugMode) {
      print("Starting BLE Scan for '$targetDeviceName'");
    }

    try {
      // Ensure Bluetooth is on
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        if (kDebugMode) {
          print("Bluetooth adapter is off.");
        }
        if (Platform.isAndroid) {
           await FlutterBluePlus.turnOn();
        }
        // Wait a bit for the adapter to turn on
        await Future.delayed(const Duration(seconds: 2));
        if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
          throw Exception("Bluetooth is not enabled");
        }
      }

      await FlutterBluePlus.startScan(
          withNames: [targetDeviceName], // Filter by name
          timeout: const Duration(seconds: 10));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName == targetDeviceName) {
            if (kDebugMode) {
              print('Found target device: ${r.device.platformName} (${r.device.remoteId})');
            }
            stopScan(); // Stop scanning once found
            connect(r.device);
            break;
          }
        }
      }, onError: (e) {
        if (kDebugMode) {
          print("Scan Error: $e");
        }
        _updateStatus(BleConnectionStatus.disconnected, notify: true);
      });

      // Handle scan timeout
      _scanSubscription?.onDone(() {
        if (_connectionStatus == BleConnectionStatus.scanning) {
          if (kDebugMode) {
            print("Scan timed out.");
          }
          _updateStatus(BleConnectionStatus.disconnected, notify: true);
        }
      });

    } catch (e) {
      if (kDebugMode) {
        print("Error starting scan: $e");
      }
       _updateStatus(BleConnectionStatus.disconnected, notify: true);
       // Consider throwing or displaying error to user
       // throw Exception("Could not start scan: $e");
    }
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;
     if (_connectionStatus == BleConnectionStatus.scanning) {
       _updateStatus(BleConnectionStatus.disconnected); // Only revert if still scanning
     }
  }

  Future<void> connect(BluetoothDevice device) async {
    if (_connectionStatus == BleConnectionStatus.connected || _connectionStatus == BleConnectionStatus.connecting) {
      return; // Already connected or connecting
    }
    _updateStatus(BleConnectionStatus.connecting);
    if (kDebugMode) {
      print("Connecting to ${device.platformName} (${device.remoteId})...");
    }

    // Cancel any previous connection state subscription
    await _connectionStateSubscription?.cancel();

    try {
      // Listen to connection state changes
      _connectionStateSubscription = device.connectionState.listen((state) async {
        if (kDebugMode) {
          print("Device ${device.remoteId} state: $state // Current App Status: $_connectionStatus");
        }

        // --- V3 State Handling: Ignore initial disconnect during connection attempt ---
        if (_connectionStatus == BleConnectionStatus.connecting) {
          if (state == BluetoothConnectionState.connected) {
            // Successfully connected!
            _connectedDevice = device;
            _updateStatus(BleConnectionStatus.connected); // Update status FIRST
            if (kDebugMode) {
              print("Connected successfully via stream!");
            }
            await _discoverServicesAndSubscribe(); // Discover after confirming connected status
          } else if (state == BluetoothConnectionState.disconnected) {
            // *** Ignore this initial disconnect event. ***
            // The actual connection failure/timeout will be caught by the try/catch block below.
            if (kDebugMode) {
              print("Ignoring initial disconnected event while connecting...");
            }
          }
        } else if (_connectionStatus == BleConnectionStatus.connected) {
          if (state == BluetoothConnectionState.disconnected) {
            // Handle disconnects that happen *after* we were successfully connected.
            if (kDebugMode) {
              print("Device disconnected (while previously connected).");
            }
            _cleanupConnection();
            _updateStatus(BleConnectionStatus.disconnected, notify: true);
          }
        } else {
           // Handle unexpected states
           if (kDebugMode) {
             print("Received unexpected device state '$state' while in app status '$_connectionStatus'");
           }
           // If app thinks it's disconnected but gets a connected event, potentially try to recover?
           // For now, just log it.
        }
        // --- End V3 State Handling ---

      }, onError: (e) {
        if (kDebugMode) {
          print("Connection State Stream Error: $e");
        }
        // Don't assume disconnect here, the connect() call might still be trying
        // Cleanup will happen if connect() fails or if a disconnect event occurs later.
      });

      // Connect to the device. If this fails or times out, it will throw an exception.
      if (kDebugMode) {
        print("Attempting device.connect()...");
      }
      await device.connect(autoConnect: false);
      if (kDebugMode) {
         // This might print before or after the stream emits 'connected'
         print("device.connect() completed without throwing an error.");
      }

    } catch (e) {
      if (kDebugMode) {
        print("Error during device.connect(): $e");
      }
      _cleanupConnection(); // Clean up if connect() call itself fails
      _updateStatus(BleConnectionStatus.disconnected, notify: true);
    }
  }

  Future<void> _discoverServicesAndSubscribe() async {
    if (_connectedDevice == null || _connectionStatus != BleConnectionStatus.connected) return;

    try {
       List<BluetoothService> services = await _connectedDevice!.discoverServices();
       if (kDebugMode) {
         print("Discovering services...");
       }
       for (BluetoothService service in services) {
         if (service.uuid == serviceUuid) {
           if (kDebugMode) {
              print("Found target service: ${service.uuid}");
           }
           for (BluetoothCharacteristic characteristic in service.characteristics) {
             if (characteristic.uuid == characteristicUuid) {
               if (kDebugMode) {
                 print("Found target characteristic: ${characteristic.uuid}");
               }
               _targetCharacteristic = characteristic;
               await _subscribeToNotifications(characteristic);
               return; // Found what we needed
             }
           }
         }
       }
       if (kDebugMode) {
          print("Target service/characteristic not found.");
       }
        disconnect(); // Disconnect if characteristic not found
    } catch (e) {
       if (kDebugMode) {
          print("Error discovering services: $e");
       }
       disconnect();
    }
  }

  Future<void> _subscribeToNotifications(BluetoothCharacteristic characteristic) async {
     if (!characteristic.properties.notify) {
       if (kDebugMode) {
          print("Characteristic does not support notifications.");
       }
       return;
     }

    await _notificationSubscription?.cancel(); // Cancel previous subscription if any

     try {
        await characteristic.setNotifyValue(true);
         if (kDebugMode) {
           print("Subscribed to notifications for ${characteristic.uuid}");
         }

        _notificationSubscription = characteristic.onValueReceived.listen((value) {
          // Attempt to parse as JSON first
          String? receivedJsonString;
          dynamic decodedData;
          try {
            receivedJsonString = String.fromCharCodes(value);
            decodedData = jsonDecode(receivedJsonString);
          } catch (e) {
            // Not JSON
            decodedData = null;
          }

          if (decodedData != null && decodedData is Map<String, dynamic>) {
            // --- Handle JSON Messages ---
            if (kDebugMode) print("JSON Received: $receivedJsonString");

            if (decodedData.containsKey('player_moved')) {
              // --- Game State Update ---
              _isReceivingImage = false; // Stop any pending image reception if game state changes
              _imageBytesBuilder.clear();

              int playerMoved = decodedData['player_moved'];
              int p1Time = decodedData['p1_time_sec'];
              int p2Time = decodedData['p2_time_sec'];

              _stopAllTimers();
              _lastPlayerMoved = playerMoved;
              _player1Time = p1Time;
              _player2Time = p2Time;

              if (playerMoved == 1 || playerMoved == 2) {
                _turnCounter++;
                // Add turn data *without* image initially
                final newTurn = TurnData(
                  turnNumber: _turnCounter,
                  playerMoved: playerMoved,
                  p1TimeSec: p1Time,
                  p2TimeSec: p2Time,
                  imageBytes: null, // Explicitly null for now
                );
                _turnHistory.add(newTurn);
                if (kDebugMode) print("Added turn $_turnCounter to history (no image yet)");

                if (playerMoved == 1) _startP2Timer(); else _startP1Timer();

              } else if (playerMoved == 0) {
                // Reset/Start Game
                 if (_turnHistory.isNotEmpty) {
                     _gameHistoryLog.add(List<TurnData>.from(_turnHistory));
                 }
                _turnHistory.clear();
                _turnCounter = 0;
                _latestImageBytes = null; // Clear latest image on reset
              }
              notifyListeners(); // Notify for game state change

            } else if (decodedData.containsKey('type') && decodedData['type'] == 'image_start') {
              // --- Image Start ---
              if (decodedData.containsKey('size') && decodedData['size'] is int) {
                _expectedImageSize = decodedData['size'];
                _imageBytesBuilder = BytesBuilder(); // Reset builder
                _isReceivingImage = true;
                if (kDebugMode) print("Image Start: Expecting $_expectedImageSize bytes");
              } else {
                 if (kDebugMode) print("Error: image_start JSON missing valid size.");
              }

            } else if (decodedData.containsKey('type') && decodedData['type'] == 'image_end') {
              // --- Image End ---
              if (!_isReceivingImage) {
                 if (kDebugMode) print("Warning: Received image_end without active image reception.");
                 return; // Ignore if not expecting image
              }

              final receivedBytes = _imageBytesBuilder.toBytes();
              final receivedSize = receivedBytes.lengthInBytes;
              if (kDebugMode) print("Image End: Received $receivedSize bytes (Expected: $_expectedImageSize)");

              if (receivedSize == _expectedImageSize) {
                // Success!
                _latestImageBytes = receivedBytes; // Store as the latest image
                if (_turnHistory.isNotEmpty) {
                  _turnHistory.last.imageBytes = receivedBytes; // Associate with last turn
                  if (kDebugMode) print("Image reception complete. Stored as latest and associated with Turn ${_turnHistory.last.turnNumber}.");
                  notifyListeners();
                } else {
                   if (kDebugMode) print("Warning: Image received but no turn history to associate it with (Stored as latest anyway).");
                    notifyListeners(); // Still notify UI about the latest image
                }
              } else {
                if (kDebugMode) print("Error: Image size mismatch! Expected $_expectedImageSize, got $receivedSize");
                _latestImageBytes = null; // Clear latest image on error
              }

              // Reset image reception state
              _isReceivingImage = false;
              _expectedImageSize = 0;
              _imageBytesBuilder.clear();

            } else {
               if (kDebugMode) print("Warning: Received unknown JSON format: $receivedJsonString");
            }

          } else if (_isReceivingImage || _expectedImageSize > 0) {
            // --- Handle Raw Image Data Chunk ---
            // Buffer if we are actively receiving OR if we expect an image (size > 0)
            // This helps catch chunks arriving right after image_start before _isReceivingImage is set.
            _imageBytesBuilder.add(value);
            if (kDebugMode) {
                print("Image Chunk Received: ${value.length} bytes. Total buffered: ${_imageBytesBuilder.length}. (Receiving: $_isReceivingImage, Expected: $_expectedImageSize)");
            }
            // Set receiving flag to true if we just started buffering based on expected size
            if (!_isReceivingImage && _expectedImageSize > 0) {
                if (kDebugMode) print("INFO: Started buffering image chunks based on expected size > 0.");
                _isReceivingImage = true;
            }
          } else {
            // --- Unexpected Non-JSON Data ---
            if (kDebugMode) {
               print("Warning: Received unexpected non-JSON data outside of image transfer: $value");
            }
          }
        }, onError: (e) {
           if (kDebugMode) print("Notification Stream Error: $e");
           _stopAllTimers();
           _latestImageBytes = null; // Clear latest image
           _isReceivingImage = false;
           _imageBytesBuilder.clear();
        });

         // Optional: Read initial value? The spec says "Clock Ready" is sent on creation,
         // but a read might be useful depending on ESP32 behaviour.
         // List<int> initialValue = await characteristic.read();
         // print("Initial characteristic value: ${String.fromCharCodes(initialValue)}");

     } catch (e) {
        if (kDebugMode) {
           print("Error enabling notifications: $e");
        }
        _stopAllTimers();
        disconnect();
     }
  }

  // --- Timer Management Methods ---

  void _startP1Timer() {
    _p1Timer?.cancel();
    if (_player1Time <= 0) return;
    _p1Timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_player1Time > 0) {
        _player1Time--;
        // *** Keep timer callback logs ***
        if (kDebugMode) print("[Timer P1 Callback] P1 Time: $_player1Time. Notifying listeners...");
        notifyListeners();
      } else {
        if (kDebugMode) print("[Timer P1 Callback] P1 Time is 0. Cancelling timer.");
        timer.cancel();
      }
    });
  }

  void _stopP1Timer() {
     if (_p1Timer?.isActive ?? false) {
       _p1Timer?.cancel();
       _p1Timer = null;
     }
   }

  void _startP2Timer() {
    _p2Timer?.cancel();
    if (_player2Time <= 0) return;
    _p2Timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_player2Time > 0) {
        _player2Time--;
         // *** Keep timer callback logs ***
        if (kDebugMode) print("[Timer P2 Callback] P2 Time: $_player2Time. Notifying listeners...");
        notifyListeners();
      } else {
        if (kDebugMode) print("[Timer P2 Callback] P2 Time is 0. Cancelling timer.");
        timer.cancel();
      }
    });
  }

   void _stopP2Timer() {
      if (_p2Timer?.isActive ?? false) {
       _p2Timer?.cancel();
       _p2Timer = null;
     }
   }

  void _stopAllTimers() {
    _stopP1Timer();
    _stopP2Timer();
  }

  void disconnect() {
    _connectedDevice?.disconnect();
     _cleanupConnection(); // Clean up immediately on manual disconnect
     _updateStatus(BleConnectionStatus.disconnected, notify: true);
  }

  // Cleanup resources
  void _cleanupConnection() {
    if (kDebugMode) {
      print("Cleaning up connection resources...");
    }
    _connectionStateSubscription?.cancel();
    _notificationSubscription?.cancel();
    _targetCharacteristic = null;
    _connectedDevice = null;
    _lastMessage = "N/A"; // Reset last message

    // Reset game state on disconnect
    _lastPlayerMoved = null;
    _player1Time = 0;
    _player2Time = 0;
    _turnHistory.clear();
    _turnCounter = 0;
    _stopAllTimers(); // Stop timers on disconnect
    // Reset image state on disconnect
    _latestImageBytes = null;
    _isReceivingImage = false;
    _expectedImageSize = 0;
    _imageBytesBuilder.clear();
    // Optionally clear gameHistoryLog on disconnect? Or keep it persistent?
    // _gameHistoryLog.clear(); // Uncomment to clear log on disconnect
    // Don't call notifyListeners here directly, it's handled by disconnect or state listeners
  }

  @override
  void dispose() {
    if (kDebugMode) {
      print("Disposing BleService...");
    }
    _stopAllTimers(); // Stop timers on dispose
    stopScan();
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _notificationSubscription?.cancel();
    _connectedDevice?.disconnect(); // Ensure disconnect on dispose
    // Reset image state on dispose
    _latestImageBytes = null;
    _isReceivingImage = false;
    _expectedImageSize = 0;
    _imageBytesBuilder.clear();
    super.dispose();
  }
} 