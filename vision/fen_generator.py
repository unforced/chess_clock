import chess
from typing import List, Tuple, Optional

def generate_fen(square_classifications: List[Tuple[Optional[str], Optional[str]]], 
                 previous_fen: Optional[str] = None) -> str:
    """
    Generates a FEN string from square classifications, using previous FEN for context.

    Args:
        square_classifications: List of 64 (piece_symbol, piece_color) tuples.
        previous_fen: Optional FEN string of the board state before this one.

    Returns:
        A FEN string representing the current board state.
    """
    if len(square_classifications) != 64:
        raise ValueError("Input must contain classifications for exactly 64 squares.")

    # --- 1. Generate Piece Placement String --- 
    fen_rows = []
    empty_count = 0
    current_pieces = {}
    for i in range(64):
        square_index = chess.SQUARES[chess.square(i % 8, 7 - (i // 8))] # Map linear index (0-63) to chess square index (0-63, a8-h1)
        piece_symbol, _ = square_classifications[i]

        if piece_symbol is None:
            empty_count += 1
        else:
            if empty_count > 0:
                fen_rows.append(str(empty_count))
                empty_count = 0
            fen_rows.append(piece_symbol)
            # Store piece for board creation later
            current_pieces[square_index] = chess.Piece.from_symbol(piece_symbol)

        # End of a rank
        if (i + 1) % 8 == 0:
            if empty_count > 0:
                fen_rows.append(str(empty_count))
                empty_count = 0
            if i < 63:
                fen_rows.append('/')

    piece_placement_fen = "".join(fen_rows)

    # --- 2. Determine Other FEN Fields using previous_fen --- 
    side_to_move = 'w'
    castling_fen = '-'
    ep_square_fen = '-'
    halfmove_clock = 0
    fullmove_number = 1

    if previous_fen:
        try:
            prev_board = chess.Board(previous_fen)
            # Create a board object for the *current* detected state
            # Note: This might raise ValueError if piece placement is illegal
            current_board = chess.Board(fen=None) # Start empty
            current_board.set_piece_map(current_pieces)

            # Basic logic: Flip side to move
            side_to_move = 'b' if prev_board.turn == chess.WHITE else 'w'

            # Increment fullmove number if it was Black's turn previously
            fullmove_number = prev_board.fullmove_number + (1 if prev_board.turn == chess.BLACK else 0)

            # --- More Complex Logic (Placeholders/Simplifications) --- 
            # Halfmove clock: Reset on pawn move or capture. Requires comparing boards.
            # This is tricky without move detection. Let's just increment naively for now, 
            # assuming no capture/pawn move unless proven otherwise (which we aren't doing).
            halfmove_clock = prev_board.halfmove_clock + 1 
            # A better approach needs move detection.

            # Castling rights: Need to detect if King/Rooks moved or were captured.
            # This is complex. We will *try* to preserve previous rights unless King/Rook is missing.
            # This is NOT fully robust.
            current_castling = prev_board.castling_rights
            # Remove white rights if K or Rooks moved/missing
            if not current_board.king(chess.WHITE) == chess.E1 or not current_board.piece_at(chess.A1) == chess.Piece.from_symbol('R') or not current_board.piece_at(chess.H1) == chess.Piece.from_symbol('R'):
                 current_castling &= ~chess.BB_RANK_1 # Clear white side
            # Remove black rights if k or rooks moved/missing
            if not current_board.king(chess.BLACK) == chess.E8 or not current_board.piece_at(chess.A8) == chess.Piece.from_symbol('r') or not current_board.piece_at(chess.H8) == chess.Piece.from_symbol('r'):
                 current_castling &= ~chess.BB_RANK_8 # Clear black side
            castling_fen = prev_board.shredder_fen(castling_rights=current_castling).split()[-4] # Get only castling part
            if not castling_fen or castling_fen in ['-','w','b']:
                 castling_fen = '-'
            
            # En passant: Requires detecting a 2-square pawn push on the *previous* move.
            # Very hard without move detection. Defaulting to '-'.
            ep_square_fen = '-'
            # --- End Complex Logic --- 

        except ValueError as e:
            print(f"Error processing previous FEN '{previous_fen}' or current board state: {e}. Using defaults.")
            # Fall back to defaults if previous FEN is invalid or current state is illegal
            side_to_move = 'w'
            castling_fen = '-'
            ep_square_fen = '-'
            halfmove_clock = 0
            fullmove_number = 1
        except Exception as e: # Catch other potential errors
             print(f"Unexpected error processing FEN context: {e}. Using defaults.")
             side_to_move = 'w'
             castling_fen = '-'
             ep_square_fen = '-'
             halfmove_clock = 0
             fullmove_number = 1

    # --- 3. Assemble Full FEN --- 
    full_fen = f"{piece_placement_fen} {side_to_move} {castling_fen} {ep_square_fen} {halfmove_clock} {fullmove_number}"

    # --- 4. Final Validation (Optional but Recommended) ---
    try:
        validated_board = chess.Board(full_fen)
        # Return the FEN generated by python-chess for consistency
        print(f"Generated FEN validated: {validated_board.fen()}")
        return validated_board.fen()
    except ValueError as e:
        print(f"Warning: Final generated FEN '{full_fen}' is invalid according to python-chess: {e}")
        # Return the potentially invalid FEN anyway, or handle error
        return full_fen

# Example Usage (for testing)
if __name__ == '__main__':
    # Example classifications (replace with actual classifications)
    start_pos_symbols = [
        'r', 'n', 'b', 'q', 'k', 'b', 'n', 'r',
        'p', 'p', 'p', 'p', 'p', 'p', 'p', 'p',
        None,None,None,None,None,None,None,None,
        None,None,None,None,None,None,None,None,
        None,None,None,None,None,None,None,None,
        None,None,None,None,None,None,None,None,
        'P', 'P', 'P', 'P', 'P', 'P', 'P', 'P',
        'R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R'
    ]
    start_pos_classifications = [(s, ('w' if s and s.isupper() else 'b' if s else None)) for s in start_pos_symbols]

    # Test without previous FEN
    fen1 = generate_fen(start_pos_classifications)
    print(f"\nGenerated FEN (no prev): {fen1}")

    # Simulate a move (e.g., e2e4)
    e4_pos_symbols = list(start_pos_symbols)
    e4_pos_symbols[52] = None # Clear e2 (index for P at e2)
    e4_pos_symbols[36] = 'P'  # Place P at e4 (index for e4)
    e4_pos_classifications = [(s, ('w' if s and s.isupper() else 'b' if s else None)) for s in e4_pos_symbols]

    # Test with previous FEN
    previous_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    fen2 = generate_fen(e4_pos_classifications, previous_fen)
    print(f"\nGenerated FEN (prev={previous_fen}): {fen2}") # Should ideally be ... b - - 0 1

    # Simulate another move (e.g., e7e5)
    e5_pos_symbols = list(e4_pos_symbols)
    e5_pos_symbols[12] = None # Clear e7
    e5_pos_symbols[28] = 'p'  # Place p at e5
    e5_pos_classifications = [(s, ('w' if s and s.isupper() else 'b' if s else None)) for s in e5_pos_symbols]
    previous_fen_e4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1" # Approx FEN after e4
    fen3 = generate_fen(e5_pos_classifications, previous_fen_e4)
    print(f"\nGenerated FEN (prev={previous_fen_e4}): {fen3}") # Should ideally be ... w KQkq - 0 2

    # Example with some empty squares
    empty_board_classifications = [(None, None)] * 64
    empty_fen = generate_fen(empty_board_classifications)
    print(f"Empty Board FEN: {empty_fen}")

    # Example based on the placeholder recognizer (random)
    random_classifications = [('P','w'), ('k','b'), None, None, None, None, None, None] * 8
    random_fen = generate_fen(random_classifications)
    print(f"Random Board FEN: {random_fen}") 