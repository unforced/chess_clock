import numpy as np
import cv2
import tensorflow as tf # Use tensorflow directly

# Global variable to hold the loaded model
piece_classifier_model = None

# Define the expected input size for the model (adjust if necessary based on model details)
# The Rizo-R repo mentions training with 150x300, which seems odd for squares.
# Let's assume a square input for now, e.g., 150x150. Needs verification.
MODEL_INPUT_SIZE = (150, 150)

# Define the mapping from model output index to piece symbol
# This needs to match the order used during training in Rizo-R/chess-cv
# Assuming standard order: B, K, N, P, Q, R (black lowercase), b, k, n, p, q, r (white uppercase), empty (-)
# CHECK THIS ORDER CAREFULLY based on the Rizo-R/chess-cv training/labeling code if possible.
CLASS_MAP = {
    0: 'b', 1: 'k', 2: 'n', 3: 'p', 4: 'q', 5: 'r', # Black pieces
    6: 'B', 7: 'K', 8: 'N', 9: 'P', 10: 'Q', 11: 'R', # White pieces
    12: None # Empty square
}

def load_model(model_path: str):
    """Loads the piece classification Keras model."""
    global piece_classifier_model
    try:
        print(f"Loading Keras model from: {model_path}")
        piece_classifier_model = tf.keras.models.load_model(model_path)
        print("Model loaded successfully.")
        # Optional: Print model summary
        # piece_classifier_model.summary()
    except Exception as e:
        print(f"Error loading Keras model: {e}")
        piece_classifier_model = None

def classify_square(square_image: np.ndarray) -> tuple[str | None, str | None]:
    """
    Classifies the piece type and color on a given square image using the loaded model.

    Args:
        square_image: A NumPy array representing the image of a single square.

    Returns:
        A tuple (piece_symbol, piece_color).
        piece_symbol: The symbol of the piece (e.g., 'P', 'N', 'B', 'R', 'Q', 'K') or None if empty.
                      Uses uppercase for white, lowercase for black as per FEN.
        piece_color: 'w' for white, 'b' for black, or None if empty.
    """
    if piece_classifier_model is None:
        print("Error: Piece classifier model not loaded. Returning placeholder.")
        # Placeholder logic from before (can be removed if model loading is required)
        is_empty = np.random.choice([True, False], p=[0.6, 0.4])
        if is_empty:
            return None, None
        else:
            piece = np.random.choice(['P', 'N', 'B', 'R', 'Q', 'K'])
            color_choice = np.random.choice(['w', 'b'])
            piece_symbol = piece.upper() if color_choice == 'w' else piece.lower()
            return piece_symbol, color_choice

    try:
        # 1. Preprocess square_image
        #    - Resize to model's expected input size
        #    - Convert to float32
        #    - Normalize pixel values (common practice: / 255.0)
        #    - Add batch dimension
        img_resized = cv2.resize(square_image, MODEL_INPUT_SIZE)
        img_normalized = img_resized.astype('float32') / 255.0
        input_data = np.expand_dims(img_normalized, axis=0) # Add batch dimension

        # 2. Predict using the loaded model
        prediction = piece_classifier_model.predict(input_data)
        
        # 3. Decode the prediction
        #    - Find the index with the highest probability
        predicted_class_index = np.argmax(prediction[0])
        piece_symbol = CLASS_MAP.get(predicted_class_index, None) # Get symbol from map

        # 4. Determine piece color from symbol
        if piece_symbol is None:
            piece_color = None
        elif piece_symbol.islower(): # Black pieces are lowercase in FEN
            piece_color = 'b'
        else: # White pieces are uppercase
            piece_color = 'w'

        # print(f"Prediction: {prediction}, Index: {predicted_class_index}, Symbol: {piece_symbol}, Color: {piece_color}")
        return piece_symbol, piece_color

    except Exception as e:
        print(f"Error during square classification: {e}")
        return None, None # Return None on error

# The simple color detection function is likely not needed if the model predicts piece+color
# def detect_piece_color_simple(square_image: np.ndarray, square_is_light: bool) -> str | None:
#     ... 