import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ble_service.dart'; // Import the BleService
import 'package:tuple/tuple.dart';
import 'package:flutter/foundation.dart'; // Import for kDebugMode

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => BleService(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Companion',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const ChessClockScreen(),
    );
  }
}

// Helper function to format time
String formatTime(int totalSeconds) {
  if (totalSeconds < 0) totalSeconds = 0; // Ensure non-negative
  int minutes = totalSeconds ~/ 60;
  int seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

class ChessClockScreen extends StatelessWidget {
  const ChessClockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Clock Companion'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // --- Game History Button ---
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'View Game History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GameHistoryScreen()),
              );
            },
          ),
          // Show connection status icon in AppBar
          Consumer<BleService>(
            builder: (context, bleService, child) {
              IconData icon;
              Color color;
              switch (bleService.connectionStatus) {
                case BleConnectionStatus.connected:
                  icon = Icons.bluetooth_connected;
                  color = Colors.lightGreenAccent;
                  break;
                case BleConnectionStatus.connecting:
                case BleConnectionStatus.scanning:
                  icon = Icons.bluetooth_searching;
                  color = Colors.yellow;
                  break;
                case BleConnectionStatus.disconnected:
                default:
                  icon = Icons.bluetooth_disabled;
                  color = Colors.redAccent;
                  break;
              }
              return Padding(
                padding: const EdgeInsets.only(right: 15.0),
                child: Icon(icon, color: color),
              );
            },
          )
        ],
      ),
      body: Consumer<BleService>(
        builder: (context, bleService, child) {
          // Show connection controls if not connected
          if (bleService.connectionStatus != BleConnectionStatus.connected) {
            return _buildConnectionView(context, bleService);
          }

          // Show game state view if connected
          return _buildGameStateView(context, bleService);
        },
      ),
    );
  }

  // --- Builds the view shown when not connected ---
  Widget _buildConnectionView(BuildContext context, BleService bleService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            'Status: ${bleService.connectionStatus.toString().split('.').last}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 30),
          if (bleService.connectionStatus == BleConnectionStatus.disconnected)
            ElevatedButton.icon(
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Scan for ChessClock'),
              onPressed: () {
                try {
                  bleService.startScan();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error starting scan: $e')),
                  );
                }
              },
            ),
          if (bleService.connectionStatus == BleConnectionStatus.scanning ||
              bleService.connectionStatus == BleConnectionStatus.connecting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text("Searching..."),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- Builds the main game state view when connected ---
  Widget _buildGameStateView(BuildContext context, BleService bleService) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Selector<BleService, Tuple3<int, int, int?>>(
            selector: (_, service) => Tuple3(
              service.player1Time,
              service.player2Time,
              service.lastPlayerMoved,
            ),
            builder: (context, data, child) {
              final p1Time = data.item1;
              final p2Time = data.item2;
              final lastMoved = data.item3;
              final currentTurnPlayer = lastMoved == null ? 0 : (lastMoved == 1 ? 2 : 1);
              if (kDebugMode) {
                  // UI Rebuild Log for Times/Turn
                  print("[UI BUILD Time Selector] P1: $p1Time, P2: $p2Time, LastMoved: $lastMoved, CurrentTurn: $currentTurnPlayer");
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildPlayerTimeCard(context, "Player 1", p1Time, currentTurnPlayer == 1),
                  _buildPlayerTimeCard(context, "Player 2", p2Time, currentTurnPlayer == 2),
                ],
              );
            },
          ),
        ),
        Consumer<BleService>(
             builder: (context, service, child) {
                if (service.lastPlayerMoved == 0) {
                   // Changed message to be neutral
                   return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text("Game Ready", style: textTheme.titleMedium?.copyWith(color: Colors.green)),
                    );
                } else {
                  return const SizedBox.shrink();
                }
            },
        ),
        Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text("Turn History", style: textTheme.titleLarge),
        ),
        Expanded(
          child: Consumer<BleService>(
            builder: (context, service, child) {
              final history = service.turnHistory;
               if (kDebugMode) {
                  // UI Rebuild Log for History
                  print("[UI BUILD History Consumer] History has ${history.length} items.");
                  // Optionally log the actual items if needed for deeper debugging
                  // for(var i=0; i < history.length; i++) {
                  //   print("[UI BUILD History Consumer] Item $i: ${history[i]}");
                  // }
               }
              return history.isEmpty
                  ? const Center(child: Text("No moves recorded yet."))
                  : ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        // Build items in reverse order to show latest first
                        final turnData = history[history.length - 1 - index];
                        if (kDebugMode) {
                           print("[UI BUILD History ItemBuilder] Building item for Turn ${turnData.turnNumber}");
                        }
                        return Card(
                           margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                           child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(turnData.toString(), style: textTheme.bodyMedium),
                                  // Display Image IN the history item if available
                                  if (turnData.imageBytes != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Center(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight: MediaQuery.of(context).size.height * 0.2, // Slightly smaller height in list
                                          ),
                                          child: Image.memory(
                                            turnData.imageBytes!,
                                            fit: BoxFit.contain,
                                            errorBuilder: (context, error, stackTrace) {
                                              if (kDebugMode) print("[UI BUILD History Image Error] Turn ${turnData.turnNumber}: $error");
                                              return const Text('Error loading image', style: TextStyle(color: Colors.red));
                                            },
                                            gaplessPlayback: true,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                           ),
                        );
                      },
                    );
              },
          )
        ),
        Divider(),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Consumer<BleService>(
             builder: (context, service, child) {
                return ElevatedButton.icon(
                    icon: const Icon(Icons.bluetooth_disabled),
                    label: const Text('Disconnect'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white),
                    onPressed: () => service.disconnect(),
                  );
              },
          )
        ),
      ],
    );
  }

  // --- Helper to build player time display card ---
  Widget _buildPlayerTimeCard(
      BuildContext context, String playerName, int timeSeconds, bool isTurn) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: isTurn ? 6.0 : 2.0,
      color: isTurn ? Colors.lightBlue[100] : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
        child: Column(
          children: [
            Text(playerName, style: textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(
              formatTime(timeSeconds),
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: isTurn ? FontWeight.bold : FontWeight.normal,
                color: isTurn ? Colors.blue[800] : null,
              ),
            ),
            const SizedBox(height: 5),
            if (isTurn) const Text("TURN", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))
          ],
        ),
      ),
    );
  }
}

// --- New Screen to Display Game History Log ---
class GameHistoryScreen extends StatelessWidget {
  const GameHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completed Game History'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<BleService>(
        builder: (context, bleService, child) {
          final log = bleService.gameHistoryLog;

          if (log.isEmpty) {
            return const Center(
              child: Text("No completed games recorded yet."),
            );
          }

          return ListView.builder(
            itemCount: log.length,
            itemBuilder: (context, index) {
              final gameTurns = log[log.length - 1 - index];
              final gameNumber = log.length - index;
              final turnCount = gameTurns.length;

              return ListTile(
                leading: CircleAvatar(child: Text('$gameNumber')),
                title: Text('Game $gameNumber'),
                subtitle: Text('$turnCount turns'),
                trailing: const Icon(Icons.arrow_forward_ios), // Indicate tappable
                onTap: () {
                   // Navigate to detailed game view
                   Navigator.push(
                     context,
                     MaterialPageRoute(
                       builder: (context) => GameDetailScreen(
                         gameNumber: gameNumber,
                         turnHistory: gameTurns,
                       ),
                     ),
                   );
                 },
              );
            },
          );
        },
      ),
    );
  }
}

// --- Screen for Detailed Game Turn Log ---
class GameDetailScreen extends StatelessWidget {
  final int gameNumber;
  final List<TurnData> turnHistory;

  const GameDetailScreen({
    super.key,
    required this.gameNumber,
    required this.turnHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Game $gameNumber Details (${turnHistory.length} turns)'), // Show turn count in title
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: turnHistory.isEmpty
          ? const Center(child: Text("No turns recorded for this game."))
          : ListView.builder(
              itemCount: turnHistory.length,
              itemBuilder: (context, index) {
                final turnData = turnHistory[index];
                return Card( // Wrap each turn in a Card for better visual separation
                  margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Display Turn Info Text
                        Text(
                           turnData.toString(), // Already includes image size if present
                           style: Theme.of(context).textTheme.bodyMedium,
                         ),
                        // Display Image if it exists
                        if (turnData.imageBytes != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Center(
                              child: Image.memory(
                                turnData.imageBytes!,
                                fit: BoxFit.contain,
                                height: 200, // Add temporary fixed height for debugging
                                errorBuilder: (context, error, stackTrace) {
                                   // Log the error
                                   if (kDebugMode) {
                                     print("[UI BUILD Image Error] Failed to load image for Turn ${turnData.turnNumber}: $error");
                                   }
                                   return const Text('Error loading image', style: TextStyle(color: Colors.red));
                                },
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
