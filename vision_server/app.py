import sys
import os
import chess # Import chess here for FEN validation in app route

# Add project root to path to find the 'vision' module and 'models' directory
project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, project_root)

from flask import Flask, request, jsonify
import cv2
import numpy as np
import io

# Import our vision modules (now relative to project_root)
from vision.board_detector import find_and_warp_board, split_board_into_squares
from vision.piece_recognizer import classify_square, load_model_weights
from vision.fen_generator import generate_fen

app = Flask(__name__)

# Configure upload folder (relative to project root maybe? Or keep inside server? Let's keep it simple for now)
UPLOAD_FOLDER = os.path.join(project_root, 'uploads') # Place uploads in project root
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)
# app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER # Flask doesn't strictly need this config for BytesIO handling

# --- Model Loading ---
# Model path relative to project root
MODEL_PATH = os.path.join(project_root, 'models/model_weights.h5')
if os.path.exists(MODEL_PATH):
    load_model_weights(MODEL_PATH)
else:
    print(f"\n*** WARNING: Model file not found at {MODEL_PATH} ***")
    print("*** Please download 'model_weights.h5' from https://github.com/Rizo-R/chess-cv ***")
    print("*** and place it in the 'models' directory in the project root. ***\n")

# ---------------------

@app.route('/analyze', methods=['POST'])
def analyze_board():
    """Analyzes a chessboard image, optionally using previous FEN, and returns the new FEN string."""
    if 'file' not in request.files:
        return jsonify({"error": "No file part in the request"}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    # Get optional previous FEN from form data
    previous_fen = request.form.get('previous_fen')
    if previous_fen:
        print(f"Received previous FEN: {previous_fen}")
        # Optional: Validate previous_fen format here
        try:
            _ = chess.Board(previous_fen)
        except ValueError:
            return jsonify({"error": "Invalid format for previous_fen"}), 400

    if file:
        try:
            # Read image file into memory
            in_memory_file = io.BytesIO()
            file.save(in_memory_file)
            in_memory_file.seek(0)
            file_bytes = np.frombuffer(in_memory_file.read(), np.uint8)
            img = cv2.imdecode(file_bytes, cv2.IMREAD_COLOR)

            if img is None:
                 return jsonify({"error": "Could not decode image"}), 400

            # --- Steps 1 & 2: Detect, Warp, Split --- 
            warped_board = find_and_warp_board(img)
            if warped_board is None:
                return jsonify({"error": "Could not detect chessboard in the image"}), 400
            squares = split_board_into_squares(warped_board)
            if len(squares) != 64:
                 return jsonify({"error": f"Could not split board into 64 squares (got {len(squares)})"}), 500

            # --- Step 3: Classify Each Square ---
            classifications = []
            for square_img in squares:
                piece_symbol, piece_color = classify_square(square_img)
                classifications.append((piece_symbol, piece_color))
            if len(classifications) != 64:
                return jsonify({"error": f"Classification resulted in {len(classifications)} squares, expected 64"}), 500

            # --- Step 4: Generate FEN (now potentially using previous_fen) ---
            # Pass previous_fen (which might be None) to the generator
            fen_string = generate_fen(classifications, previous_fen)

            return jsonify({"fen": fen_string}), 200

        except Exception as e:
            # Log the exception for debugging
            app.logger.error(f"Error processing image: {e}", exc_info=True)
            return jsonify({"error": f"An internal error occurred: {str(e)}"}), 500
    
    return jsonify({"error": "File processing failed"}), 500

if __name__ == '__main__':
    # Run the Flask app
    # Use host='0.0.0.0' to make it accessible on your network
    app.run(debug=True, host='0.0.0.0', port=5001) # Use a port other than default 5000 if needed 