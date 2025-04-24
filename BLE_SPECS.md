# ChessClock ESP32 BLE Specifications

This document outlines the Bluetooth Low Energy (BLE) service and characteristics exposed by the ESP32 Chess Clock firmware (`src/chessclock.cpp`). This information is intended for the development of the companion Flutter application.

**Last Updated:** [Current Date - Please fill in]

## 1. Device Advertising

*   **Device Name:** `ChessClock`

## 2. BLE Service

*   **Service UUID:** `4fafc201-1fb5-459e-8fcc-c5c9c331914b`

## 3. BLE Characteristic (Primary)

Within the service defined above, there is one primary characteristic used for **both** game state updates **and** image data transfer.

*   **Characteristic UUID:** `beb5483e-36e1-4688-b7f5-ea07361b26a8`
*   **Properties:** `READ`, `WRITE`, `NOTIFY`.
*   **Descriptor (CCCD):** `0x2902` (Client writes `0x0001` to enable notifications).

### 3.1 Game State Notifications

*   **Trigger:** Sent when the game state changes via `resetGame`, `startGame`, or `switchPlayer`.
*   **Format:** JSON String
*   **Structure:** `{"player_moved": <player>, "p1_time_sec": <time1>, "p2_time_sec": <time2>}`
    *   `player_moved` (Integer): Player (1 or 2) whose turn just *ended*. `0` for reset. For `startGame`, indicates the player whose clock *isn't* running.
    *   `p1_time_sec` (Integer): Player 1's remaining seconds.
    *   `p2_time_sec` (Integer): Player 2's remaining seconds.

### 3.2 Image Transfer Notifications

*   **Trigger:** Sent immediately after a game state change notification, initiated by the call to `takePhoto()`.
*   **Protocol:** The image is sent as a sequence of notifications:
    1.  **Start Marker:** A JSON string indicating the start of an image transfer and the total size.
        *   **Format:** `{"type":"image_start","size":<total_bytes>}`
        *   **Example:** `{"type":"image_start","size":8754}`
    2.  **Image Data Chunks:** The raw bytes of the JPEG image data, sent sequentially in multiple notifications. The size of each chunk may vary but will not exceed a predefined limit (currently 20 bytes in the firmware).
    3.  **End Marker:** A JSON string indicating the end of the image transfer.
        *   **Format:** `{"type":"image_end"}`

*   **Data Flow:** The receiving application must listen for the `image_start` message, note the `size`, then append all subsequent raw byte notifications into a buffer until `size` bytes have been received. The `image_end` message confirms the transfer is complete (though checking the received byte count against the expected `size` is recommended).

## 4. Connection Handling

*   The ESP32 restarts advertising automatically if the connected client disconnects.

## 5. Flutter App Requirements (Updated)

The Flutter app should be able to:

1.  Scan for BLE devices advertising the name "ChessClock".
2.  Connect to the selected device.
3.  Discover the service and characteristic UUIDs mentioned above.
4.  Enable notifications for the characteristic.
5.  Receive notifications and parse them:
    *   If the notification is a valid JSON string:
        *   Check for `"player_moved"`: Update game state display (times, turn indicator).
        *   Check for `"type":"image_start"`: Prepare to receive image data, store the expected `size`.
        *   Check for `"type":"image_end"`: Finalize image reception, potentially display the assembled image.
    *   If the notification is **not** valid JSON (and an image reception is in progress): Append the raw bytes to the current image buffer.
6.  Assemble the received raw image data chunks into a complete JPEG image based on the size provided in the `image_start` message.
7.  Display the received game state information and the assembled images (e.g., in a list).

*(Note: BLE transfer speed might be slow for larger images. Reliability depends on factors like distance, interference, and processing speed on both devices. The delays between chunks in the firmware might need tuning.)* 