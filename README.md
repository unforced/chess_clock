# Chess Clock Companion

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) <!-- Optional: Add a license badge if you have one -->

This project combines hardware (ESP32 Devkit + ESP32 CAM) and software (Flutter App, Python Server) to create a smart chess clock that automatically recognizes and logs the board state after each move.

## Overview

When a player presses their button on the physical clock:

1.  The **ESP32 Devkit** updates the game timer and (optionally) an LCD display.
2.  It commands the attached **ESP32 CAM** to take a picture of the chessboard.
3.  The Devkit sends the timer update and the captured JPEG image to a connected **Flutter Mobile App** via Bluetooth Low Energy (BLE).
4.  The Flutter app displays the timers and the received image.
5.  The Flutter app sends the image (along with the FEN string from the previous turn, if available) to a **Python Flask Server**.
6.  The Python server uses OpenCV and a TensorFlow/Keras model to analyze the image, determine piece positions, and generate the current board state in Forsyth–Edwards Notation (FEN).
7.  The Python server returns the FEN string to the Flutter app.
8.  The Flutter app updates its display, showing the captured image alongside a rendered chessboard based on the received FEN.
9.  A history of turns (images + FENs) is maintained in the app.

## Features

*   Physical chess clock interface with buttons for two players and reset.
*   Optional LCD display for current times.
*   Automatic chessboard image capture after each turn.
*   Bluetooth Low Energy (BLE) communication between clock hardware and mobile app.
*   Mobile app (Flutter) for displaying game state, image history, and recognized board positions (FEN).
*   Python backend server for robust chessboard and piece recognition using computer vision and ML.
*   FEN generation incorporating context from the previous move (for side-to-move, castling, etc., with some limitations).
*   Turn-by-turn history display in the mobile app, showing the image and the resulting FEN board.

## Components

*   **Hardware (`src/`)**
    *   `src/devkit_hub/`: ESP32 Devkit firmware (C++/Arduino)
    *   `src/cam_camera/`: ESP32 CAM firmware (C++/Arduino)
    *   (Requires ESP32 Devkit board, ESP32 CAM, optional 16x2 I2C LCD, 3 push buttons, wiring)
*   **Mobile App (`chess_companion/`)**
    *   Flutter application (Dart)
    *   Connects via BLE, displays game info, interacts with Python server.
*   **Vision Backend (`vision/`, `vision_server/`)**
    *   `vision_server/`: Flask web server (Python)
    *   `vision/`: Computer vision library (Python - OpenCV, TensorFlow/Keras)
    *   (Requires Python environment, dependencies in `requirements.txt`, and a pre-trained model `models/model_weights.h5`)
*   **BLE Specification (`BLE_SPECS.md`)**
    *   Defines the communication protocol between the hardware and the mobile app.
*   **Project Specifications (`PROJECT_SPECIFICATIONS.md`)**
    *   Detailed technical documentation of the entire system.

## Setup

Refer to the detailed setup instructions for each component in the `PROJECT_SPECIFICATIONS.md` file (Section 8).

1.  **Hardware:** Compile and upload the firmware from `src/devkit_hub/` and `src/cam_camera/` to the respective ESP32 boards using Arduino IDE or PlatformIO. Ensure correct libraries are installed and wiring matches the specification.
2.  **Python Backend:**
    *   Create a Python virtual environment.
    *   Install dependencies: `pip install -r vision_server/requirements.txt`
    *   Download the required `model_weights.h5` file (e.g., from [Rizo-R/chess-cv](https://github.com/Rizo-R/chess-cv) or provide your own) and place it in a `models/` directory at the project root (`./models/model_weights.h5`).
    *   Run the server: `python vision_server/app.py`
    *   Note the local URL (e.g., `http://<your-ip>:5001`). If running the app on a separate device, you might need a tool like `ngrok` to expose the server: `ngrok http 5001`. Update the `visionServerUrl` in the Flutter app accordingly.
3.  **Flutter App:**
    *   Ensure you have the Flutter SDK installed.
    *   Navigate to the `chess_companion/` directory.
    *   Install dependencies: `flutter pub get`
    *   **IMPORTANT:** Update the `visionServerUrl` constant in `chess_companion/lib/ble_service.dart` to point to your running Python backend (use the ngrok URL if applicable).
    *   Run the app on a connected device or emulator: `flutter run`

## Usage

1.  Power on the assembled ESP32 hardware clock.
2.  Start the Python backend server.
3.  Launch the Flutter app on your mobile device.
4.  In the app, tap "Scan for ChessClock" and connect to the device when found.
5.  Place the ESP32 CAM overlooking the chessboard.
6.  Start a game using the physical buttons on the clock.
7.  As players press their buttons, the app will update with the times, show the captured image, and display the recognized board state (FEN).
8.  View the turn history by scrolling down in the app.

## Circuit Schematic

(Refer to `PROJECT_SPECIFICATIONS.md`, Section 3.2 for detailed pin connections)

*   Buttons -> ESP32 Devkit (GPIO 4, 18, 19)
*   I2C LCD -> ESP32 Devkit (GPIO 21 SDA, 22 SCL)
*   ESP32 Devkit Serial2 (GPIO 16 RX, 17 TX) <-> ESP32 CAM Serial (GPIO 1 TX, 3 RX)

## Known Issues / TODO

*   See `PROJECT_SPECIFICATIONS.md`, Section 9.
*   Serial command mismatch between Devkit (`T`) and CAM (`SNAP`).
*   FEN generation context (castling, halfmove, en passant) relies on potentially inaccurate inference from board state alone.
*   Requires manual setup of the Python server URL in the Flutter app.

## Contributing

(Optional: Add contribution guidelines if desired)

## License

(Optional: Specify your license, e.g., MIT License) 