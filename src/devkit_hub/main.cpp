#include <Arduino.h>
#include <Wire.h>             // For I2C communication
#include <LiquidCrystal_I2C.h> // For I2C LCD control
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <HardwareSerial.h> // <<< ADDED for Serial2
// #include "esp_camera.h" // <<< REMOVED Camera Header

// --- Debugging Flags ---
#define USE_LCD 1 // Set to 1 to enable LCD, 0 to disable

// --- Pin Definitions ---
// Define button pins
const int BTN_RESET_PIN = 4;  // Use Pin 4 for Reset
const int BTN_P1_PIN = 18;    // Use Pin 18 for P1
const int BTN_P2_PIN = 19;    // Use Pin 19 for P2
const int BUTTON_COUNT = 3;   // We have 3 buttons

// AI-Thinker ESP32-CAM Pin Map <<< REMOVED
/* #define PWDN_GPIO_NUM     32
... [removed camera pins] ...
#define PCLK_GPIO_NUM     22 // Conflicts with default I2C */

#if USE_LCD
// I2C Pins for LCD
const int I2C_SDA_PIN = 21; // Standard ESP32 SDA pin
const int I2C_SCL_PIN = 22; // Standard ESP32 SCL pin
#endif

// Serial Pins for ESP32-CAM Communication
const int CAM_SERIAL_RX_PIN = 16; // Serial2 RX <- CAM TX (GPIO1)
const int CAM_SERIAL_TX_PIN = 17; // Serial2 TX -> CAM RX (GPIO3)

// --- Camera Configuration --- REMOVED
// camera_config_t camera_config;

// --- Constants ---
#if USE_LCD
const int LCD_ADDR = 0x27;      
const int LCD_COLS = 16;        
const int LCD_ROWS = 2;         
#endif
const unsigned long INITIAL_TIME_MS = 9 * 60 * 1000L; // 9 minutes in milliseconds
const unsigned long DEBOUNCE_DELAY = 50; // Debounce time in milliseconds
// #define BLE_CHUNK_SIZE 20 // <<< REMOVED - Not needed for state updates


// --- Global Variables ---
#if USE_LCD
LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS); 
#endif
HardwareSerial SerialCam(2); // Use UART2 for ESP32-CAM

// Buffer for receiving camera image
uint8_t* imageBuffer = nullptr;
const size_t imageBufferSize = 30 * 1024; // 30KB buffer for QVGA JPEG

enum GameState { IDLE, RUNNING_P1, RUNNING_P2, GAME_OVER };
GameState currentState = IDLE; // Start in IDLE state
const char* stateNames[] = {"IDLE", "RUNNING_P1", "RUNNING_P2", "GAME_OVER"}; // For easy printing

unsigned long player1Time = INITIAL_TIME_MS;
unsigned long player2Time = INITIAL_TIME_MS;
unsigned long lastUpdateTime = 0; // For timekeeping

// Button state variables (Restored for 3 buttons)
int buttonStates[BUTTON_COUNT];
int lastButtonStates[BUTTON_COUNT];
unsigned long lastDebounceTimes[BUTTON_COUNT];
const int buttonPins[BUTTON_COUNT] = {BTN_RESET_PIN, BTN_P1_PIN, BTN_P2_PIN};

// Variables for long press detection (Removed single button logic)
/* bool controlPinHeldDown = false;
unsigned long controlPinPressStartTime = 0;
const unsigned long LONG_PRESS_DURATION = 2000; // 2 seconds */

// --- Static variables for LCD update logic --- Moved from updateDisplay()
static unsigned long lastDisplayUpdate = 0;
static char timeBuffer1[9]; // HH:MM:SS format + null terminator (actually MM:SS.T)
static char timeBuffer2[9];
static GameState lastDisplayedState = (GameState)-1; // Force initial update
static unsigned long lastP1Time = 0;
static unsigned long lastP2Time = 0;
// --- End static variables for LCD ---

// --- BLE Definitions (Keep These) ---
BLEServer* pServer = NULL;
BLECharacteristic* pStateCharacteristic = NULL; // Renamed for clarity
// BLECharacteristic* pImageDataCharacteristic = NULL; // <<< REMOVED Image Characteristic
bool deviceConnected = false;
bool oldDeviceConnected = false;

// See the following for generating UUIDs: https://www.uuidgenerator.net/
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define STATE_CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8" // For game state
// #define IMAGE_DATA_CHARACTERISTIC_UUID "..." // <<< REMOVED Image Characteristic UUID

// BLE Server Callback Class (Keep This)
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("BLE Client Connected");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("BLE Client Disconnected");
    }
};


// --- Function Prototypes ---
void handleButtons(); // Changed back from handleControlButton
void resetGame();
void startGame(int playerWhoPressedButton);
void switchPlayer(int nextPlayerWhoseClockStarts);
void updateDisplay(); // LCD <<< Prototype restored
void forceUpdateDisplay(); // LCD <<< Prototype restored
#if USE_LCD
void writeToLCD(); // LCD <<< Prototype restored
#endif
void formatTime(unsigned long time_ms, char* buffer, size_t bufferSize); // <<< Prototype restored
void sendBleStateUpdate(int playerMoved, unsigned long p1TimeMs, unsigned long p2TimeMs);
size_t requestAndReceiveImage(); 
void sendImageOverBle(const uint8_t* buffer, size_t size); 
// void configCamera(); // <<< REMOVED Camera Config Prototype
// void takePhoto();    // <<< REMOVED Take Photo Prototype


// --- Setup Function (Restored 3-button + LCD) ---
void setup() {
  Serial.begin(115200);
  delay(1500);
  // Use a very simple print statement
  Serial.println("\n\nChess Clock Starting..."); 

  // Initialize Serial2 for ESP32-CAM communication
  SerialCam.begin(115200, SERIAL_8N1, CAM_SERIAL_RX_PIN, CAM_SERIAL_TX_PIN);
  Serial.println("Serial2 for CAM Initialized (RX:16, TX:17).");

#if USE_LCD
  // --- Initialize I2C and LCD ---
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  lcd.init();
  lcd.backlight();
  Serial.println("LCD Initialized.");
#endif

  // Setup Buttons (Restored for 3 buttons)
  for (int i = 0; i < BUTTON_COUNT; i++) {
    pinMode(buttonPins[i], INPUT_PULLUP); // Use internal pull-ups
    buttonStates[i] = HIGH;               // Initial state is not pressed
    lastButtonStates[i] = HIGH;
    lastDebounceTimes[i] = 0;
  }
  Serial.println("Button Init: Reset(4), P1(18), P2(19) enabled.");


  // --- Initialize Camera --- REMOVED
  /* configCamera();
  Serial.println("Attempting to initialize camera...");
  esp_err_t err = esp_camera_init(&camera_config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x\n", err);
    Serial.println("Restarting...");
    delay(1000);
    ESP.restart(); // Restart if camera fails
  }
  Serial.println("Camera init SUCCESS"); */
  // --- End Camera Init --- REMOVED

  // Allocate image buffer
  imageBuffer = (uint8_t*) malloc(imageBufferSize);
  if (imageBuffer == nullptr) {
    Serial.println("!!!!!!!!!!!!!! Failed to allocate image buffer! Reduce size? !!!!!!!!!!!!!!");
    // Handle error - maybe disable camera functionality?
  } else {
    Serial.printf("Image buffer allocated (%zu bytes).\n", imageBufferSize);
  }

  // --- Initialize BLE (Keep State Characteristic Only) ---
  Serial.println("Starting BLE setup...");
  BLEDevice::init("ChessClock"); 
  Serial.println("BLEDevice::init() done.");
  pServer = BLEDevice::createServer();
  Serial.println("BLEDevice::createServer() done.");
  pServer->setCallbacks(new MyServerCallbacks());
  Serial.println("pServer->setCallbacks() done.");
  BLEService *pService = pServer->createService(SERVICE_UUID);
  Serial.println("pServer->createService() done.");

  // Create State Characteristic
  pStateCharacteristic = pService->createCharacteristic(
                      STATE_CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_NOTIFY |
                      BLECharacteristic::PROPERTY_WRITE // Keep write for potential commands?
                    );
  pStateCharacteristic->addDescriptor(new BLE2902());
  Serial.println("pStateCharacteristic created.");

  pStateCharacteristic->setValue("BLE Ready");
  Serial.println("pStateCharacteristic->setValue() done.");
  pService->start();
  Serial.println("pService->start() done.");

  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE Advertising supposedly started. Check nRF Connect.");
  // --- End BLE Init ---

  // Initialize Game State
  lastUpdateTime = millis();
  resetGame(); // Start in reset state initially
#if USE_LCD
  forceUpdateDisplay(); // Update LCD on startup if enabled
#endif

  Serial.println("Setup Complete. Entering loop...");
}

// --- Main Loop (Restored) ---
void loop() {
   handleButtons(); // Call the original button handler

   // Game Timer Logic
   unsigned long currentTime = millis();
   unsigned long elapsedTime = 0;

   if (currentState == RUNNING_P1 || currentState == RUNNING_P2) {
       // Handle potential millis() overflow
       if (currentTime < lastUpdateTime) {
           elapsedTime = (0xFFFFFFFF - lastUpdateTime) + currentTime + 1;
       } else {
           elapsedTime = currentTime - lastUpdateTime;
       }

       if (currentState == RUNNING_P1) {
           if (player1Time <= elapsedTime) {
               player1Time = 0;
               currentState = GAME_OVER;
               Serial.println("P1 Timeout");
               sendBleStateUpdate(1, player1Time, player2Time); // Send BLE on timeout
           } else {
               player1Time -= elapsedTime;
           }
       } else if (currentState == RUNNING_P2) {
           if (player2Time <= elapsedTime) {
               player2Time = 0;
               currentState = GAME_OVER;
               Serial.println("P2 Timeout");
               sendBleStateUpdate(2, player1Time, player2Time); // Send BLE on timeout
           } else {
               player2Time -= elapsedTime;
           }
       }
   }
   lastUpdateTime = currentTime;

#if USE_LCD
   updateDisplay(); // Update LCD in loop if enabled
#endif

  // Handle BLE Disconnection/Reconnection
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); 
      // Ensure pServer is valid before trying to use it
      if (pServer != nullptr) {
          pServer->startAdvertising(); 
          Serial.println("Restarting BLE advertising");
      } else {
          Serial.println("Warning: pServer is null, cannot restart advertising.");
      }
      oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
      Serial.println("Device connected callback received.");
  }
     
  delay(1); 
}

// --- Helper Functions ---

// --- handleButtons (Restored 3-button logic) ---
void handleButtons() {
    unsigned long currentTime = millis();

    for (int i = 0; i < BUTTON_COUNT; i++) {
        int reading = digitalRead(buttonPins[i]);

        if (reading != lastButtonStates[i]) {
            lastDebounceTimes[i] = currentTime; // Reset the debouncing timer
        }

        if ((currentTime - lastDebounceTimes[i]) > DEBOUNCE_DELAY) {
            // If the button state has changed, after the debounce period
            if (reading != buttonStates[i]) {
                buttonStates[i] = reading;

                // Only trigger on button PRESS (transition from HIGH to LOW)
                if (buttonStates[i] == LOW) {
                    Serial.printf("Button %d Pressed (Pin %d)\n", i, buttonPins[i]);

                    if (i == 0) { // Reset Button (Pin 4)
                        resetGame();
                    } else if (i == 1) { // Player 1 Button (Pin 18)
                        if (currentState == IDLE) {
                            startGame(1); // Player 1 starts
                        } else if (currentState == RUNNING_P1) {
                            switchPlayer(2); // Switch to Player 2
                        }
                        // Ignore if P2's clock is running or game over
                    } else if (i == 2) { // Player 2 Button (Pin 19)
                         if (currentState == IDLE) {
                            startGame(2); // Player 2 starts
                        } else if (currentState == RUNNING_P2) {
                            switchPlayer(1); // Switch to Player 1
                        }
                        // Ignore if P1's clock is running or game over
                    }
#if USE_LCD
                    forceUpdateDisplay(); // Update LCD on button press if enabled
#endif
                }
            }
        }
        lastButtonStates[i] = reading; // Update the last reading
    }
}

void resetGame() {
    currentState = IDLE;
    player1Time = INITIAL_TIME_MS;
    player2Time = INITIAL_TIME_MS;
    Serial.println("Game Reset to IDLE");
    // forceUpdateDisplay(); // Already called in handleButtons
    sendBleStateUpdate(0, player1Time, player2Time); // Send BLE update (player 0 = reset)
}

void startGame(int playerWhoPressedButton) {
    if (currentState == IDLE) {
        // If P1 pressed, start P2's clock, and vice-versa
        currentState = (playerWhoPressedButton == 1) ? RUNNING_P2 : RUNNING_P1;
        lastUpdateTime = millis(); // Reset timer start point
        int runningPlayer = (playerWhoPressedButton == 1) ? 2 : 1;
        Serial.printf("Game Started - Running P%d\n", runningPlayer);
        // Send state update according to Spec for startGame:
        // "player_moved indicates the player whose clock *isn't* running."
        int playerNotRunning = (playerWhoPressedButton == 1) ? 1 : 2;
        sendBleStateUpdate(playerNotRunning, player1Time, player2Time);

        // Request image after starting game
        size_t receivedBytes = requestAndReceiveImage(); // <<< Re-enable CAM comms
        if (receivedBytes > 0) {                       // <<< Re-enable CAM comms
           Serial.printf("Successfully received %zu image bytes after game start.\n", receivedBytes);
           sendImageOverBle(imageBuffer, receivedBytes); // <<< Re-enable CAM comms
        } else {                                       // <<< Re-enable CAM comms
           Serial.println("Failed to receive image after game start.");
        }                                              // <<< Re-enable CAM comms
    }
}

void switchPlayer(int nextPlayerWhoseClockStarts) {
    if ((currentState == RUNNING_P1 && nextPlayerWhoseClockStarts == 2) ||
        (currentState == RUNNING_P2 && nextPlayerWhoseClockStarts == 1)) {
        
        int playerWhoseTurnEnded = (nextPlayerWhoseClockStarts == 1) ? 2 : 1; // Calculate who just finished
        
        currentState = (nextPlayerWhoseClockStarts == 1) ? RUNNING_P1 : RUNNING_P2;
        lastUpdateTime = millis(); // Reset timer start point for the new player
        Serial.printf("Switched Player - Running P%d (Player %d finished)\n", nextPlayerWhoseClockStarts, playerWhoseTurnEnded);
        
        // Send BLE update indicating whose turn ENDED, per spec
        sendBleStateUpdate(playerWhoseTurnEnded, player1Time, player2Time); 

        // Request image after switching player
        size_t receivedBytes = requestAndReceiveImage(); // <<< Re-enable CAM comms
        if (receivedBytes > 0) {                       // <<< Re-enable CAM comms
           Serial.printf("Successfully received %zu image bytes after player switch.\n", receivedBytes);
           sendImageOverBle(imageBuffer, receivedBytes); // <<< Re-enable CAM comms
        } else {                                       // <<< Re-enable CAM comms
           Serial.println("Failed to receive image after player switch.");
        }                                              // <<< Re-enable CAM comms
    }
}

// --- updateDisplay (Restored LCD Logic) ---
void updateDisplay() {
    // static unsigned long lastDisplayUpdate = 0; // Moved to file scope
    // static char timeBuffer1[9]; // Moved to file scope
    // static char timeBuffer2[9]; // Moved to file scope
    // static GameState lastDisplayedState = (GameState)-1; // Moved to file scope
    // static unsigned long lastP1Time = 0; // Moved to file scope
    // static unsigned long lastP2Time = 0; // Moved to file scope

    unsigned long currentTime = millis();

    // Only update roughly every 100ms unless state changes or time drastically changes
    bool stateChanged = (currentState != lastDisplayedState);
    bool timeChangedSignificantly = (abs((long)player1Time - (long)lastP1Time) > 100 || abs((long)player2Time - (long)lastP2Time) > 100);

    if (stateChanged || timeChangedSignificantly || (currentTime - lastDisplayUpdate > 100) ) {

        formatTime(player1Time, timeBuffer1, sizeof(timeBuffer1));
        formatTime(player2Time, timeBuffer2, sizeof(timeBuffer2));

#if USE_LCD
        lcd.setCursor(0, 0);
        lcd.print("P1:");
        lcd.print(timeBuffer1);
        lcd.print(" "); 

        lcd.setCursor(0, 1);
        lcd.print("P2:");
        lcd.print(timeBuffer2);
        lcd.print(" "); 

        lcd.setCursor(13, 0); 
        if (currentState == RUNNING_P1) {
            lcd.print("<--"); 
            lcd.setCursor(13, 1);
            lcd.print("   ");
        } else if (currentState == RUNNING_P2) {
            lcd.print("   ");
            lcd.setCursor(13, 1);
            lcd.print("<--"); 
        } else if (currentState == IDLE) {
            lcd.print("IDLE");
            lcd.setCursor(13, 1);
            lcd.print("   ");
        } else if (currentState == GAME_OVER) {
            lcd.print("OVER");
            lcd.setCursor(13, 1);
            lcd.print(player1Time == 0 ? "P2 W" : "P1 W"); 
        }
#endif // USE_LCD specific calls

        lastDisplayUpdate = currentTime;
        lastDisplayedState = currentState;
        lastP1Time = player1Time;
        lastP2Time = player2Time;
    }
}

void forceUpdateDisplay() {
#if USE_LCD
    lastDisplayedState = (GameState)-1; // Force updateDisplay condition
    updateDisplay();
#endif
}

// --- formatTime (Restored) ---
// Formats time in milliseconds to MM:SS.T (Minutes:Seconds.Tenths)
void formatTime(unsigned long time_ms, char* buffer, size_t bufferSize) {
    unsigned long totalSeconds = time_ms / 1000;
    int minutes = totalSeconds / 60;
    int seconds = totalSeconds % 60;
    int tenths = (time_ms % 1000) / 100;
    snprintf(buffer, bufferSize, "%02d:%02d.%d", minutes, seconds, tenths);
}


// --- sendBleStateUpdate (Adjusted Characteristic) ---
void sendBleStateUpdate(int playerMoved, unsigned long p1TimeMs, unsigned long p2TimeMs) {
    if (deviceConnected && pStateCharacteristic != nullptr) {
        // Convert times to seconds for the spec
        unsigned long p1TimeSec = p1TimeMs / 1000;
        unsigned long p2TimeSec = p2TimeMs / 1000;

        // Format according to BLE_SPECs.md
        char bleBuffer[100]; // Increased buffer size for JSON
        snprintf(bleBuffer, sizeof(bleBuffer), 
                 "{\"player_moved\":%d,\"p1_time_sec\":%lu,\"p2_time_sec\":%lu}",
                 playerMoved, p1TimeSec, p2TimeSec);

        Serial.printf("Sending BLE Update (JSON): %s\n", bleBuffer);
        pStateCharacteristic->setValue(bleBuffer);
        pStateCharacteristic->notify();

    } else {
        if (!deviceConnected) {
             Serial.println("Cannot send BLE update, no device connected.");
        } else {
             Serial.println("Cannot send BLE update, characteristic invalid.");
        }
    }
    // Print message even if BLE is off, for debugging button presses - Keep this for logging
    Serial.printf("Log: State Update Intent: playerMoved=%d, p1=%lu ms, p2=%lu ms\n", playerMoved, p1TimeMs, p2TimeMs);
}

// --- takePhoto Function REMOVED ---
/* void takePhoto() {
    ...
} */

// --- configCamera Function REMOVED ---
/* void configCamera() {
    ...
} */

#if USE_LCD
void writeToLCD() {
    // Implementation of writeToLCD function (only relevant if LCD enabled)
}
#endif

// --- Request image from CAM and receive it over Serial2 ---
size_t requestAndReceiveImage() {
  if (imageBuffer == nullptr) {
    Serial.println("ERROR: Image buffer not allocated!");
    return 0;
  }

  Serial.println("Requesting image from CAM...");
  SerialCam.println("SNAP"); // Send command

  unsigned long startTime = millis();
  const unsigned long timeoutDuration = 5000; // 5 second timeout for entire process
  size_t bytesRead = 0;
  size_t expectedSize = 0;
  bool sizeReceived = false;

  // State machine for receiving data
  enum RecvState { WAIT_FOR_SIZE, READ_IMAGE, WAIT_FOR_END };
  RecvState recvState = WAIT_FOR_SIZE;

  while (millis() - startTime < timeoutDuration) {
    // --- Step 1: Wait for and parse SIZE line ---
    if (recvState == WAIT_FOR_SIZE) {
      if (SerialCam.available() > 0) {
        String line = SerialCam.readStringUntil('\n');
        line.trim();
        Serial.printf("CAM Response: %s\n", line.c_str()); // Debug
        if (line.startsWith("SIZE:")) {
          expectedSize = line.substring(5).toInt();
          if (expectedSize > 0 && expectedSize <= imageBufferSize) {
            Serial.printf("Expecting %zu bytes...\n", expectedSize);
            sizeReceived = true;
            recvState = READ_IMAGE; // Move to next state
            bytesRead = 0; // Reset bytes counter for image data
          } else if (expectedSize > imageBufferSize) {
            Serial.printf("ERROR: Advertised size (%zu) > buffer size (%zu)!\n", expectedSize, imageBufferSize);
            // Optional: Could try to read/discard data to clear CAM buffer?
            return 0; // Error
          } else {
            Serial.printf("ERROR: Invalid size received (%s)!\n", line.c_str());
            return 0; // Error
          }
        } else if (line.startsWith("ERROR:")) {
           Serial.printf("CAM reported error: %s\n", line.c_str());
           return 0; // Error reported by CAM
        } else {
            Serial.printf("WARN: Unexpected CAM response: %s\n", line.c_str());
            // Keep waiting for SIZE: line
        }
      } 
    } 
    // --- Step 2: Read image bytes ---
    else if (recvState == READ_IMAGE) {
      if (SerialCam.available() > 0) {
        size_t bytesToRead = SerialCam.available();
        if (bytesRead + bytesToRead > expectedSize) {
          bytesToRead = expectedSize - bytesRead; // Don't read past expected size
        }
        size_t actuallyRead = SerialCam.readBytes(imageBuffer + bytesRead, bytesToRead);
        bytesRead += actuallyRead;

        if (bytesRead == expectedSize) {
          Serial.printf("Read %zu image bytes.\n", bytesRead);
          recvState = WAIT_FOR_END; // Move to next state
        }
      }
    } 
    // --- Step 3: Wait for FRAME_END marker ---
    else if (recvState == WAIT_FOR_END) {
       if (SerialCam.available() > 0) {
          String line = SerialCam.readStringUntil('\n');
          line.trim();
          Serial.printf("CAM End Response: %s\n", line.c_str()); // Debug
          if (line == "FRAME_END") {
            Serial.println("FRAME_END received. Image transfer complete.");
            return bytesRead; // Success!
          } else {
             Serial.printf("WARN: Unexpected data after image: %s\n", line.c_str());
             // Keep waiting for FRAME_END
          }
       }
    }

    delay(1); // Small delay to prevent busy-waiting
  } // End while loop (timeout check)

  // If we reach here, it's a timeout
  Serial.println("ERROR: Timeout waiting for CAM response!");
  Serial.printf(" (State: %d, SizeOK: %d, BytesRead: %zu / %zu)\n", recvState, sizeReceived, bytesRead, expectedSize);
  return 0; // Timeout error
} 

// --- Send Image Data over BLE --- 
void sendImageOverBle(const uint8_t* buffer, size_t size) {
    if (!deviceConnected || pStateCharacteristic == nullptr || buffer == nullptr || size == 0) {
        Serial.println("ERROR: Cannot send image over BLE (disconnected, bad buffer, or zero size).");
        return;
    }

    Serial.printf("Starting BLE image transfer (%zu bytes)...\n", size);

    // 1. Send Start Marker: {"type":"image_start","size":<total_bytes>}
    char startMarker[64];
    snprintf(startMarker, sizeof(startMarker), "{\"type\":\"image_start\",\"size\":%zu}", size);
    pStateCharacteristic->setValue(startMarker);
    pStateCharacteristic->notify();
    Serial.printf("Sent BLE Image Start: %s\n", startMarker);
    delay(20); // Small delay after sending marker

    // 2. Send Image Data Chunks
    const size_t chunkSize = 20; // As per spec example
    size_t bytesSent = 0;
    while (bytesSent < size) {
        size_t currentChunkSize = min(chunkSize, size - bytesSent);
        pStateCharacteristic->setValue((uint8_t*)buffer + bytesSent, currentChunkSize);
        pStateCharacteristic->notify();
        bytesSent += currentChunkSize;
        // Serial.printf("Sent %zu / %zu bytes\n", bytesSent, size); // Optional: Very verbose debug
        delay(5); // Small delay between chunks to allow receiver processing time
    }

    // 3. Send End Marker: {"type":"image_end"}
    char endMarker[] = "{\"type\":\"image_end\"}";
    pStateCharacteristic->setValue(endMarker);
    pStateCharacteristic->notify();
    Serial.printf("Sent BLE Image End: %s\n", endMarker);
    Serial.println("BLE image transfer complete.");
} 