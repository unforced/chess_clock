import 'package:flutter/material.dart' as material;
import 'package:provider/provider.dart';
import 'ble_service.dart'; // Import the BleService
import 'package:tuple/tuple.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_chess_board/flutter_chess_board.dart'; // <-- Import chess board

void main() {
  material.runApp(const MyApp());
}

class MyApp extends material.StatelessWidget {
  const MyApp({material.Key? key}) : super(key: key);

  @override
  material.Widget build(material.BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BleService(),
      child: material.MaterialApp(
        title: 'Chess Companion',
        theme: material.ThemeData(
           colorScheme: material.ColorScheme.fromSeed(seedColor: material.Colors.blueGrey),
           useMaterial3: true,
        ),
        home: const ChessClockScreen(), // Use ChessClockScreen as home
      ),
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

// --- Main Screen showing connection or game state --- 
class ChessClockScreen extends material.StatelessWidget {
  const ChessClockScreen({material.Key? key}) : super(key: key);

  @override
  material.Widget build(material.BuildContext context) {
    return material.Scaffold(
      appBar: material.AppBar(
        title: const material.Text('Chess Clock Companion'),
        backgroundColor: material.Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Game History Button (navigates to GameHistoryScreen)
          material.IconButton(
            icon: const material.Icon(material.Icons.history),
            tooltip: 'View Completed Games',
            onPressed: () {
              material.Navigator.push(
                context,
                material.MaterialPageRoute(builder: (context) => const GameHistoryScreen()),
              );
            },
          ),
          // Connection Status Icon
          Consumer<BleService>(
            builder: (context, bleService, child) {
              material.IconData icon;
              material.Color color;
              switch (bleService.connectionStatus) {
                case BleConnectionStatus.connected:
                  icon = material.Icons.bluetooth_connected;
                  color = material.Colors.green;
                  break;
                case BleConnectionStatus.connecting:
                case BleConnectionStatus.scanning:
                  icon = material.Icons.bluetooth_searching;
                  color = material.Colors.yellow.shade700;
                  break;
                case BleConnectionStatus.disconnected:
                default:
                  icon = material.Icons.bluetooth_disabled;
                  color = material.Colors.red;
                  break;
              }
              return material.Padding(
                padding: const material.EdgeInsets.only(right: 15.0),
                child: material.Icon(icon, color: color),
              );
            },
          )
        ],
      ),
      body: Consumer<BleService>(
        builder: (context, bleService, child) {
          if (bleService.connectionStatus != BleConnectionStatus.connected) {
            return _buildConnectionView(context, bleService);
          }
          return _buildGameStateView(context, bleService);
        },
      ),
    );
  }

  // Builds the view shown when not connected
  material.Widget _buildConnectionView(material.BuildContext context, BleService bleService) {
    return material.Center(
      child: material.Column(
        mainAxisAlignment: material.MainAxisAlignment.center,
        children: <material.Widget>[
          material.Text(
            'Status: ${bleService.connectionStatus.toString().split('.').last}',
            style: material.Theme.of(context).textTheme.headlineSmall,
          ),
          const material.SizedBox(height: 30),
          if (bleService.connectionStatus == BleConnectionStatus.disconnected)
            material.ElevatedButton.icon(
              icon: const material.Icon(material.Icons.bluetooth_searching),
              label: const material.Text('Scan for ChessClock'),
              onPressed: () {
                try {
                  bleService.startScan();
                } catch (e) {
                  material.ScaffoldMessenger.of(context).showSnackBar(
                    material.SnackBar(content: material.Text('Error starting scan: $e')),
                  );
                }
              },
            ),
          if (bleService.connectionStatus == BleConnectionStatus.scanning ||
              bleService.connectionStatus == BleConnectionStatus.connecting)
            const material.Padding(
              padding: material.EdgeInsets.all(16.0),
              child: material.Column(
                children: [
                  material.CircularProgressIndicator(),
                  material.SizedBox(height: 10),
                  material.Text("Searching..."),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Builds the main game state view when connected
  material.Widget _buildGameStateView(material.BuildContext context, BleService bleService) {
    final textTheme = material.Theme.of(context).textTheme;

    return material.Column(
      children: [
        material.Padding(
          padding: const material.EdgeInsets.all(16.0),
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
                  print("[UI BUILD Time Selector] P1: $p1Time, P2: $p2Time, LastMoved: $lastMoved, CurrentTurn: $currentTurnPlayer");
              }
              return material.Row(
                mainAxisAlignment: material.MainAxisAlignment.spaceAround,
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
                   return material.Padding(
                      padding: const material.EdgeInsets.symmetric(vertical: 8.0),
                      child: material.Text("Game Ready", style: textTheme.titleMedium?.copyWith(color: material.Colors.green)),
                    );
                } else {
                  return const material.SizedBox.shrink();
                }
            },
        ),
        material.Divider(),
        material.Padding(
          padding: const material.EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: material.Text("Current Game Log", style: textTheme.titleLarge), // Title for current game log
        ),
        material.Expanded(
          child: Consumer<BleService>( // Listen to changes for the history list
            builder: (context, service, child) {
              final history = service.turnHistory;
               if (kDebugMode) {
                  print("[UI BUILD History Consumer] History has ${history.length} items.");
               }
              return history.isEmpty
                  ? const material.Center(child: material.Text("No moves recorded yet."))
                  : material.ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final turnData = history[history.length - 1 - index]; // Show latest first
                        if (kDebugMode) {
                           print("[UI BUILD History ItemBuilder] Building item for Turn ${turnData.turnNumber}");
                        }
                        // Use the TurnHistoryCard for each item
                        return TurnHistoryCard(turnData: turnData);
                      },
                    );
              },
          )
        ),
        material.Divider(),
        material.Padding(
          padding: const material.EdgeInsets.all(16.0),
          child: Consumer<BleService>(
             builder: (context, service, child) {
                return material.ElevatedButton.icon(
                    icon: const material.Icon(material.Icons.bluetooth_disabled),
                    label: const material.Text('Disconnect'),
                    style: material.ElevatedButton.styleFrom(
                        backgroundColor: material.Colors.redAccent,
                        foregroundColor: material.Colors.white),
                    onPressed: () => service.disconnect(),
                  );
              },
          )
        ),
      ],
    );
  }

  // Helper to build player time display card
  material.Widget _buildPlayerTimeCard(
      material.BuildContext context, String playerName, int timeSeconds, bool isTurn) {
    final textTheme = material.Theme.of(context).textTheme;
    return material.Card(
      elevation: isTurn ? 6.0 : 2.0,
      color: isTurn ? material.Colors.lightBlue[100] : null,
      child: material.Padding(
        padding: const material.EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
        child: material.Column(
          children: [
            material.Text(playerName, style: textTheme.titleMedium),
            const material.SizedBox(height: 5),
            material.Text(
              formatTime(timeSeconds),
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: isTurn ? material.FontWeight.bold : material.FontWeight.normal,
                color: isTurn ? material.Colors.blue[800] : null,
              ),
            ),
            const material.SizedBox(height: 5),
            if (isTurn) const material.Text("TURN", style: material.TextStyle(color: material.Colors.blue, fontWeight: material.FontWeight.bold))
          ],
        ),
      ),
    );
  }
}

// --- New Screen to Display Completed Game History Log --- 
class GameHistoryScreen extends material.StatelessWidget {
  const GameHistoryScreen({material.Key? key}) : super(key: key);

  @override
  material.Widget build(material.BuildContext context) {
    return material.Scaffold(
      appBar: material.AppBar(
        title: const material.Text('Completed Game History'),
        backgroundColor: material.Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<BleService>(
        builder: (context, bleService, child) {
          final log = bleService.gameHistoryLog;

          if (log.isEmpty) {
            return const material.Center(
              child: material.Text("No completed games recorded yet."),
            );
          }

          return material.ListView.builder(
            itemCount: log.length,
            itemBuilder: (context, index) {
              final gameTurns = log[log.length - 1 - index];
              final gameNumber = log.length - index;
              final turnCount = gameTurns.length;

              return material.ListTile(
                leading: material.CircleAvatar(child: material.Text('$gameNumber')),
                title: material.Text('Game $gameNumber'),
                subtitle: material.Text('$turnCount turns'),
                trailing: const material.Icon(material.Icons.arrow_forward_ios),
                onTap: () {
                   material.Navigator.push(
                     context,
                     material.MaterialPageRoute(
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

// --- Screen for Detailed Turn Log of a Completed Game --- 
class GameDetailScreen extends material.StatelessWidget {
  final int gameNumber;
  final List<TurnData> turnHistory; // Use the list passed from GameHistoryScreen

  const GameDetailScreen({
    material.Key? key,
    required this.gameNumber,
    required this.turnHistory,
  }) : super(key: key);

  @override
  material.Widget build(material.BuildContext context) {
    return material.Scaffold(
      appBar: material.AppBar(
        title: material.Text('Game $gameNumber Details (${turnHistory.length} turns)'),
        backgroundColor: material.Theme.of(context).colorScheme.inversePrimary,
      ),
      body: turnHistory.isEmpty
          ? const material.Center(child: material.Text("No turns recorded for this game."))
          // Use ListView here, not PageView, to show all turns of the *completed* game
          : material.ListView.builder(
              itemCount: turnHistory.length,
              itemBuilder: (context, index) {
                // Show turns in chronological order for completed games
                final turnData = turnHistory[index]; 
                // Use the same TurnHistoryCard for display consistency
                return TurnHistoryCard(turnData: turnData);
              },
            ),
    );
  }
}

// --- StatefulWidget for the Card content displaying Image/Board --- 
class TurnHistoryCard extends material.StatefulWidget {
  final TurnData turnData;

  const TurnHistoryCard({material.Key? key, required this.turnData}) : super(key: key);

  @override
  _TurnHistoryCardState createState() => _TurnHistoryCardState();
}

class _TurnHistoryCardState extends material.State<TurnHistoryCard> {
  bool _showBoard = true; 

  @override
  void initState() {
    super.initState();
    final turnData = widget.turnData;
    final hasFen = turnData.fen != null && turnData.analysisError == null;
    final hasImage = turnData.imageBytes != null;
    if (!hasFen) _showBoard = false;
    if (hasFen && !hasImage) _showBoard = true;
  }
  
  // Add didUpdateWidget to handle cases where FEN arrives after initial build
  @override
  void didUpdateWidget(covariant TurnHistoryCard oldWidget) {
      super.didUpdateWidget(oldWidget);
      // If the turn data object itself changed (e.g. FEN was added)
      if (widget.turnData != oldWidget.turnData) {
          final hasFen = widget.turnData.fen != null && widget.turnData.analysisError == null;
          final hasImage = widget.turnData.imageBytes != null;
          bool shouldShowBoard = true;
          if (!hasFen) shouldShowBoard = false;
          if (hasFen && !hasImage) shouldShowBoard = true;
          // Update state only if the calculated preference changed
          if (_showBoard != shouldShowBoard) {
              // No need for addPostFrameCallback here as it's a reaction to prop change
              setState(() {
                _showBoard = shouldShowBoard;
              });
          }
      }
  }


  @override
  material.Widget build(material.BuildContext context) {
    final textTheme = material.Theme.of(context).textTheme;
    final turnData = widget.turnData; 
    final hasFen = turnData.fen != null && turnData.analysisError == null;
    final hasImage = turnData.imageBytes != null;

    // This recalculation in build might be redundant if initState/didUpdateWidget work correctly
    // bool shouldShowBoard = true;
    // if (!hasFen) shouldShowBoard = false;
    // if (hasFen && !hasImage) shouldShowBoard = true;
    // if (_showBoard != shouldShowBoard && mounted) {
    //     WidgetsBinding.instance.addPostFrameCallback((_) {
    //        if (mounted) { 
    //            setState(() { _showBoard = shouldShowBoard; });
    //        }
    //     });
    // }

    return material.Card(
      margin: const material.EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: material.Padding(
        padding: const material.EdgeInsets.all(8.0),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            material.Row(
              mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
              children: [
                material.Expanded(
                    child: material.Text(turnData.toString(), style: textTheme.bodyMedium)
                ),
                // Condition 1: Show toggle button
                if (hasFen && hasImage)
                  material.IconButton(
                    icon: material.Icon(_showBoard ? material.Icons.image : material.Icons.grid_on),
                    tooltip: _showBoard ? 'Show Image' : 'Show Board',
                    onPressed: () {
                      setState(() {
                        _showBoard = !_showBoard;
                      });
                    },
                  ),
                // Condition 2: Show retry button (only if Condition 1 is false)
                if (!hasFen && turnData.analysisError != null && hasImage)
                    material.IconButton(
                      icon: material.Icon(material.Icons.refresh, color: material.Colors.orange), // Direct Color usage okay here
                      tooltip: 'Retry Analysis',
                      onPressed: () {
                        // Ensure context is available if called from here
                        Provider.of<BleService>(context, listen: false).analyzeImageAndStoreFen(turnData);
                      },
                    ),
              ],
            ),
            const material.SizedBox(height: 8),
            material.Center(
              child: material.ConstrainedBox(
                constraints: material.BoxConstraints(
                  maxHeight: material.MediaQuery.of(context).size.height * 0.4,
                  maxWidth: material.MediaQuery.of(context).size.width * 0.9,
                ),
                child: _buildContent(hasFen, hasImage), 
              ),
            ),
            // Display error message slightly differently
            if (turnData.analysisError != null)
              material.Padding(
                padding: const material.EdgeInsets.only(top: 4.0),
                child: material.Text(
                  "Analysis Error: ${turnData.analysisError}",
                  style: const material.TextStyle(color: material.Colors.orange, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  material.Widget _buildContent(bool hasFen, bool hasImage) {
    double boardSize = material.MediaQuery.of(context).size.width * 0.85;
    boardSize = boardSize.clamp(0, material.MediaQuery.of(context).size.height * 0.4);

    if (_showBoard && hasFen) {
      try {
        return ChessBoard(
            key: material.ValueKey(widget.turnData.fen), 
            controller: ChessBoardController.fromFEN(widget.turnData.fen!),
            size: boardSize,
            enableUserMoves: false,
            boardOrientation: PlayerColor.white, // Default orientation
         );
      } catch (e) {
         if (hasImage) {
             return _buildImageWidget(); // Fallback to image if board fails
         } else {
             return material.Text('Error displaying FEN: ${e.toString()}', style: const material.TextStyle(color: material.Colors.red));
         }
      }
    } else if (hasImage) {
      return _buildImageWidget();
    } else {
      // If no image and no valid FEN (or FEN failed)
      return const material.Center(child: material.Text('No image or board available.', style: material.TextStyle(fontStyle: material.FontStyle.italic)));
    }
  }
  
  material.Widget _buildImageWidget() {
     return material.Image.memory(
        widget.turnData.imageBytes!, // Assumes hasImage is true if called
        fit: material.BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fix: Use turnNumber
          if (kDebugMode) print("[UI BUILD History Image Error] Turn ${widget.turnData.turnNumber}: $error"); 
          return const material.Text('Error loading image', style: material.TextStyle(color: material.Colors.red));
        },
        gaplessPlayback: true, 
      );
  }
}
