import numpy as np
import cv2
import tensorflow as tf 
from tensorflow import keras
from tensorflow.keras import layers

# Global variable to hold the loaded model
piece_classifier_model = None

# Define the expected input size for the model (adjust if necessary based on model details)
# The Rizo-R repo mentions training with 150x300, which seems odd for squares.
# Let's assume a square input for now, e.g., 150x150. Needs verification.
# MODEL_INPUT_SIZE = (150, 150)
# Update Input Size based on the original train.py
MODEL_INPUT_SIZE = (300, 150)
MODEL_INPUT_SHAPE = (MODEL_INPUT_SIZE[0], MODEL_INPUT_SIZE[1], 3) # Assuming color images (3 channels)
NUM_CLASSES = 13 # 12 pieces + empty

# Define the mapping from model output index to piece symbol
# This needs to match the order used during training in Rizo-R/chess-cv
# Assuming standard order: B, K, N, P, Q, R (black lowercase), b, k, n, p, q, r (white uppercase), empty (-)
# CHECK THIS ORDER CAREFULLY based on the Rizo-R/chess-cv training/labeling code if possible.
CLASS_MAP = {
    0: 'b', 1: 'k', 2: 'n', 3: 'p', 4: 'q', 5: 'r', # Black pieces
    6: 'B', 7: 'K', 8: 'N', 9: 'P', 10: 'Q', 11: 'R', # White pieces
    12: None # Empty square
}

def build_model():
    """Builds the Keras model architecture based on Rizo-R/chess-cv description."""
    model = keras.Sequential(
        [
            keras.Input(shape=MODEL_INPUT_SHAPE),
            # Layer 1
            layers.Conv2D(16, kernel_size=(3, 3), activation="relu"),
            layers.MaxPooling2D(pool_size=(2, 2)),
            # Layer 2
            layers.Conv2D(32, kernel_size=(3, 3), activation="relu"),
            layers.MaxPooling2D(pool_size=(2, 2)),
            # Layer 3
            layers.Conv2D(64, kernel_size=(3, 3), activation="relu"),
            layers.MaxPooling2D(pool_size=(2, 2)),
            # Layer 4
            layers.Conv2D(64, kernel_size=(3, 3), activation="relu"),
            layers.MaxPooling2D(pool_size=(2, 2)),
            # Layer 5 - Reverting to 64 filters as per original train.py
            layers.Conv2D(64, kernel_size=(3, 3), activation="relu"),
            layers.MaxPooling2D(pool_size=(2, 2)),
            # Flatten the results to feed into a dense layer
            layers.Flatten(),
            # layers.Dropout(0.5), # REMOVE Dropout layer (not in original train.py)
            # Dense layer - Input shape should now match weights due to correct input size
            layers.Dense(128, activation="relu"),
            layers.Dense(NUM_CLASSES, activation="softmax"),
        ]
    )
    model.summary()
    return model

def load_model_weights(weights_path: str):
    """Builds the model and loads weights from the specified path."""
    global piece_classifier_model
    try:
        print("Building model architecture...")
        piece_classifier_model = build_model()
        print(f"Loading weights from: {weights_path}")
        piece_classifier_model.load_weights(weights_path)
        print("Model weights loaded successfully.")
        # Perform a dummy prediction to finalize model build if needed
        dummy_input = np.zeros((1,) + MODEL_INPUT_SHAPE)
        _ = piece_classifier_model.predict(dummy_input)
        print("Model ready.")

    except Exception as e:
        print(f"Error building model or loading weights: {e}")
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