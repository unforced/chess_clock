# 3D Model Specifications: Chess Clock Companion Enclosure

**Version:** 1.0
**Last Updated:** [Date - Placeholder]

## 1. Overall Concept & Form Factor

*   **Goal:** A 3D printable enclosure for the ESP32 Devkit, ESP32 CAM, LCD, and buttons, functioning as a chess clock with an integrated overhead camera mount.
*   **Form:** Desktop chess clock style. Wider than deep, relatively low profile except for the camera arm.
*   **Top Surface:** Features two distinct, raised, angled sections sloping downwards towards the left and right edges, intended for Player 1 (Left) and Player 2 (Right) button mounting. A flatter section sits between/behind these, housing the Reset button (off-center) and the camera arm base (centered).
*   **Front Face:** Houses the LCD display. Consider a slight backward tilt (e.g., 10-15 degrees from vertical) for improved viewing angle from above.
*   **Rear Face:** Primarily for enclosure integrity. May include a cutout for the Devkit's USB port and optional ventilation slots.
*   **Base:** Flat bottom surface for stability.

## 2. Approximate Dimensions & Material

*   **Dimensions:** Primarily driven by the internal components (Devkit, LCD, buttons) plus necessary clearances for wiring and structure. Target a compact but functional size (e.g., roughly 180mm W x 100mm D x 60mm H excluding arm - *adjust based on actual component measurements*).
*   **Wall Thickness:** Recommend 2.5mm to 3mm for general structural integrity using standard FDM printing.
*   **Material:** PLA or PETG recommended.

## 3. Enclosure Construction & Assembly

*   **Method:** Two-part shell design (e.g., Base Plate + Top Cover) is recommended for printability and component access.
*   **Assembly:** Use countersunk M3 screws (e.g., 4-6 screws) inserted from the base plate into threaded inserts or directly into bosses molded into the top cover. Define screw hole positions logically around the perimeter.
*   **Tolerances:** Standard FDM tolerances (e.g., 0.2-0.3mm clearance for fitted parts, adjust based on printer calibration).

## 4. Component Cutouts & Mounts (Requires Exact Dimensions)

*   **ESP32 Devkit:**
    *   **Mounting:** Internal standoffs/bosses on the Base Plate matching the Devkit PCB's mounting holes. Design for M2 or M2.5 screws. *Requires exact Devkit dimensions (LxWxH) and mounting hole X/Y positions/diameters.*
    *   **Cutout:** Access opening on the Rear Face for the Devkit's USB-C/Micro-USB port. *Requires exact port location and size.*
*   **LCD Display (16x2 I2C):**
    *   **Mounting:** An internal frame or set of brackets/bosses designed to hold the LCD module securely behind the front face cutout. Can use screws matching LCD PCB holes or a secure clip/friction fit. *Requires exact LCD module dimensions (PCB LxW, screen area LxW, PCB thickness) and mounting hole positions/diameters.*
    *   **Cutout:** Rectangular opening on the tilted Front Face precisely matching the visible LCD screen area, plus a small tolerance (e.g., 0.5mm on each side).
*   **Player Buttons (P1 & P2 - Qty: 2):**
    *   **Mounting:** Positioned on the left and right angled top surfaces. Design circular holes. Include an internal lip or structure below the hole to prevent the button body from being pushed fully inside. *Requires exact button dimensions: Plunger diameter, body/thread diameter, required mounting hole diameter, required mounting depth/panel thickness.*
    *   **Cutout:** Circular holes sized for the button body/thread diameter.
*   **Reset Button (Qty: 1):**
    *   **Mounting:** Same requirements as Player Buttons, but located on the flatter top surface, slightly off-center (e.g., towards the back). *Requires exact button dimensions.*
    *   **Cutout:** Circular hole sized for the button body/thread diameter.
*   **ESP32 CAM Module:**
    *   **Mounting:** A dedicated holder/bracket at the distal end of the Camera Arm. Should securely grip the CAM PCB, ideally using its mounting holes if available. Must orient the lens downwards. Ensure clearance for any cables connected to the CAM. *Requires exact CAM PCB dimensions (LxW), mounting hole positions/diameters (if any), lens position relative to PCB edge, and overall thickness.*

## 5. Camera Arm ("Gooseneck")

*   **Concept:** An arm extending upwards and forwards from the central top surface to position the CAM above the chessboard.
*   **Structure Options:**
    *   **A) Fully Printed:** Segmented arm design (printed-in-place or assembled). Less flexible, potentially harder to print reliably.
    *   **B) Hybrid (Recommended):** Design a robust base mount integrated into the Top Cover and a separate CAM Holder piece. These two printed parts should be designed to securely attach to a standard flexible metal gooseneck tube of a specific diameter (e.g., 8mm or 10mm - *specify diameter needed*). This provides better adjustability.
*   **Base Mount:** Must be securely integrated into the Top Cover, potentially with reinforcing ribs, to handle the lever arm forces without breaking or excessive wobble.
*   **Wire Channel:** MUST incorporate a continuous hollow internal channel (minimum 4-5mm diameter recommended, *confirm based on actual CAM wire bundle thickness*) through the entire arm structure (base mount -> gooseneck tube -> CAM holder) for routing wires.
*   **Length/Height:** Target a height allowing the CAM lens to be ~30-40cm directly above the center of a standard chessboard when placed behind the clock. For the Hybrid option, the gooseneck tube length determines this primarily.
*   **Wire Exit/Entry:** Smooth, potentially chamfered openings for the wire channel at the base (inside the main enclosure) and at the CAM holder.

## 6. Internal Features

*   **Wire Management:** Include several small internal clips, channels, or posts with slots for zip ties on the Base Plate and inner walls of the Top Cover to aid in routing wires cleanly between the Devkit, LCD, buttons, and camera arm base.
*   **Component Clearance:** Ensure adequate space around all components for wiring and airflow (if needed).

## 7. Printability Considerations

*   **Orientation:** Design parts (Base, Top Cover, CAM Holder) considering optimal print orientation to minimize supports and maximize strength.
*   **Supports:** Expect supports needed for the angled button surfaces, USB/LCD cutouts, screw bosses, and potentially the camera arm base mount and CAM holder depending on design.
*   **Bridging:** Minimize long unsupported horizontal spans (bridges).
*   **Splitting:** Ensure the split between Base and Top Cover is logical and printable.

## 8. Aesthetics (Optional)

*   **Edges:** Apply fillets (rounded) or chamfers (angled) to external edges for a more finished appearance and feel.
*   **Surface Finish:** Consider adding a slight texture to external surfaces if desired.

## 9. Essential Information Required Before Modeling

*   **Datasheets or Precise Measurements (mm) for:**
    *   Specific ESP32 Devkit board model (LxWxH, mounting holes X/Y/Dia).
    *   Specific ESP32 CAM module model (LxWxH, mounting holes X/Y/Dia, lens position).
    *   16x2 I2C LCD module (PCB LxW, Screen LxW, mounting holes X/Y/Dia).
    *   All 3 Push Buttons (Mounting hole diameter needed, body diameter, plunger diameter, mounting depth).
    *   Estimated diameter of the ESP32 CAM wire bundle.
*   **Decision on Camera Arm Structure:** Fully Printed vs. Hybrid. If Hybrid, specify the outer diameter of the metal gooseneck tube to be used.
*   **Confirmation of Assembly Method:** Screws (specify type, e.g., M3x8mm countersunk) or Snap-fit. 