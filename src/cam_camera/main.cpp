#include <Arduino.h>
#include "esp_camera.h"

// --- Pin Definitions (AI-Thinker Model) ---
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1 // NC
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27

#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21 // Note: Often used for I2C SDA
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22 // Note: Often used for I2C SCL

// Serial Communication uses default Serial (UART0):
// TX: GPIO1
// RX: GPIO3

// --- Camera Configuration ---
camera_config_t camera_config;

void configCamera(){
  camera_config.ledc_channel = LEDC_CHANNEL_0;
  camera_config.ledc_timer = LEDC_TIMER_0;
  camera_config.pin_d0 = Y2_GPIO_NUM;
  camera_config.pin_d1 = Y3_GPIO_NUM;
  camera_config.pin_d2 = Y4_GPIO_NUM;
  camera_config.pin_d3 = Y5_GPIO_NUM;
  camera_config.pin_d4 = Y6_GPIO_NUM;
  camera_config.pin_d5 = Y7_GPIO_NUM;
  camera_config.pin_d6 = Y8_GPIO_NUM;
  camera_config.pin_d7 = Y9_GPIO_NUM;
  camera_config.pin_xclk = XCLK_GPIO_NUM;
  camera_config.pin_pclk = PCLK_GPIO_NUM;
  camera_config.pin_vsync = VSYNC_GPIO_NUM;
  camera_config.pin_href = HREF_GPIO_NUM;
  camera_config.pin_sccb_sda = SIOD_GPIO_NUM; // Changed name in lib from SIOD
  camera_config.pin_sccb_scl = SIOC_GPIO_NUM; // Changed name in lib from SIOC
  camera_config.pin_pwdn = PWDN_GPIO_NUM;
  camera_config.pin_reset = RESET_GPIO_NUM;
  camera_config.xclk_freq_hz = 20000000;
  camera_config.pixel_format = PIXFORMAT_JPEG; // Use JPEG for smaller size

  // Frame size - start with a smaller size for serial transfer
  camera_config.frame_size = FRAMESIZE_QVGA; // (320x240)
  camera_config.jpeg_quality = 12; // 0-63 lower means higher quality, lower number = larger file
  camera_config.fb_count = 1; // Use 1 frame buffer when streaming is not needed
  #if CONFIG_IDF_TARGET_ESP32S3
    camera_config.fb_location = CAMERA_FB_IN_PSRAM; // For ESP32-S3 with PSRAM
  #else
    camera_config.grab_mode = CAMERA_GRAB_LATEST; // Ensure we get the latest frame
  #endif
}

void setup() {
  Serial.begin(115200); // Used for communication with DevKit AND debugging
  delay(1000);
  Serial.println("\nESP32-CAM Camera Module Starting..."); // Debug message

  // Configure and Initialize Camera
  configCamera();
  Serial.println("Attempting camera initialization..."); // Debug
  esp_err_t err = esp_camera_init(&camera_config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x\n", err);
    Serial.println("Check pin connections, camera model, and power.");
    // Consider adding code here to indicate failure to the DevKit if desired
    return; // Halt setup if camera fails
  }
  Serial.println("Camera init SUCCESS");

  Serial.println("Camera Setup Complete. Waiting for commands on Serial (GPIO1/3)...");
}

void loop() {
  // Check Serial for commands from DevKit (e.g., "SNAP\n")
  if (Serial.available() > 0) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim(); // Remove potential whitespace/newlines
    Serial.printf("Received command: '%s'\n", cmd.c_str()); // Debug echo
    if (cmd == "SNAP") {
       Serial.println("SNAP command received, taking photo..."); // Debug
       camera_fb_t * fb = esp_camera_fb_get();
       if (fb) {
          // Send size back via Serial
          Serial.printf("SIZE:%zu\n", fb->len); // Send size first, followed by newline
          // Send image bytes back via Serial
          Serial.write(fb->buf, fb->len); // Send raw bytes
          Serial.flush(); // Ensure data is sent before returning buffer
          esp_camera_fb_return(fb);
          Serial.println("FRAME_END"); // Send confirmation/end marker
          Serial.println("Photo sent."); // Debug
       } else {
          Serial.println("ERROR:CaptureFail"); // Send error back via Serial
          Serial.println("Camera capture failed"); // Debug
       }
    } else {
       Serial.printf("Unknown command: %s\n", cmd.c_str()); // Debug
    }
  }

  delay(10); // Small delay
} 