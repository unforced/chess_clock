import cv2
import numpy as np
import os # Added for path operations
import time # Added for unique filenames

# Debug directory
DEBUG_IMAGE_DIR = os.path.join(os.path.dirname(__file__), 'debug_images')
if not os.path.exists(DEBUG_IMAGE_DIR):
    os.makedirs(DEBUG_IMAGE_DIR)

def order_points(pts):
    # initialzie a list of coordinates that will be ordered
    # such that the first entry in the list is the top-left,
    # the second entry is the top-right, the third is the
    # bottom-right, and the fourth is the bottom-left
    rect = np.zeros((4, 2), dtype = "float32")
    # the top-left point will have the smallest sum, whereas
    # the bottom-right point will have the largest sum
    s = pts.sum(axis = 1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    # now, compute the difference between the points, the
    # top-right point will have the smallest difference,
    # whereas the bottom-left will have the largest difference
    diff = np.diff(pts, axis = 1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    # return the ordered coordinates
    return rect

def four_point_transform(image, pts):
    # obtain a consistent order of the points and unpack them
    # individually
    rect = order_points(pts)
    (tl, tr, br, bl) = rect
    # compute the width of the new image, which will be the
    # maximum distance between bottom-right and bottom-left
    # x-coordiates or the top-right and top-left x-coordinates
    widthA = np.sqrt(((br[0] - bl[0]) ** 2) + ((br[1] - bl[1]) ** 2))
    widthB = np.sqrt(((tr[0] - tl[0]) ** 2) + ((tr[1] - tl[1]) ** 2))
    maxWidth = max(int(widthA), int(widthB))
    # compute the height of the new image, which will be the
    # maximum distance between the top-right and bottom-right
    # y-coordinates or the top-left and bottom-left y-coordinates
    heightA = np.sqrt(((tr[0] - br[0]) ** 2) + ((tr[1] - br[1]) ** 2))
    heightB = np.sqrt(((tl[0] - bl[0]) ** 2) + ((tl[1] - bl[1]) ** 2))
    maxHeight = max(int(heightA), int(heightB))
    # now that we have the dimensions of the new image, construct
    # the set of destination points to obtain a "birds eye view",
    # (i.e. top-down view) of the image, again specifying points
    # in the top-left, top-right, bottom-right, and bottom-left
    # order
    dst = np.array([
        [0, 0],
        [maxWidth - 1, 0],
        [maxWidth - 1, maxHeight - 1],
        [0, maxHeight - 1]], dtype = "float32")
    # compute the perspective transform matrix and then apply it
    M = cv2.getPerspectiveTransform(rect, dst)
    warped = cv2.warpPerspective(image, M, (maxWidth, maxHeight))
    # return the warped image
    return warped

def find_and_warp_board(image: np.ndarray, output_size: int = 400) -> np.ndarray | None:
    """
    Finds the largest contour in the image, attempts to find a 4-point approximation
    (preferring the convex hull), and returns a warped, top-down view.

    Args:
        image: Input image (NumPy array).
        output_size: The desired size of the output warped square image.

    Returns:
        A warped square image of the board, or None if no board is found.
    """
    timestamp = time.strftime("%Y%m%d-%H%M%S") # For unique filenames

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    thresh = cv2.adaptiveThreshold(blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                   cv2.THRESH_BINARY_INV, 11, 2)

    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if not contours:
        print("No contours found")
        return None

    largest_contour = max(contours, key=cv2.contourArea)

    # --- Parameters for approximation ---
    epsilon_factor = 0.03 # Tolerance for approxPolyDP

    corners = None
    approx_hull = None
    approx_orig = None

    # --- 1. Try approximating the Convex Hull ---
    hull = cv2.convexHull(largest_contour)
    peri_hull = cv2.arcLength(hull, True)
    if peri_hull > 0: # Avoid division by zero if hull is degenerate
        approx_hull = cv2.approxPolyDP(hull, epsilon_factor * peri_hull, True)
        if len(approx_hull) == 4:
            print("Using 4 points found from convex hull approximation.")
            corners = approx_hull.reshape(4, 2)
        else:
            print(f"Convex hull approximation yielded {len(approx_hull)} points. Trying original contour.")
    else:
         print("Convex hull has zero perimeter. Trying original contour.")


    # --- 2. Fallback: Approximate the Original Contour (if hull didn't work) ---
    if corners is None:
        peri_orig = cv2.arcLength(largest_contour, True)
        if peri_orig > 0: # Avoid division by zero
            approx_orig = cv2.approxPolyDP(largest_contour, epsilon_factor * peri_orig, True)
            if len(approx_orig) == 4:
                print("Using 4 points found from original contour approximation.")
                corners = approx_orig.reshape(4, 2)
            else:
                 print(f"Original contour approximation yielded {len(approx_orig)} points.")
        else:
            print("Original contour has zero perimeter.")


    # --- Process the result ---
    if corners is not None:
        # Warp the perspective using the found corners
        warped = four_point_transform(image, corners.astype(np.float32))
        resized_warped = cv2.resize(warped, (output_size, output_size))

        # --- Optional: Save successful debug image ---
        # img_success = image.copy()
        # cv2.drawContours(img_success, [corners.reshape(-1, 1, 2)], -1, (0, 255, 0), 2) # Draw successful corners in green
        # cv2.imwrite(os.path.join(DEBUG_IMAGE_DIR, f'{timestamp}_04_success_corners.png'), img_success)
        # -------------------------------------------
        return resized_warped
    else:
        # --- FAILURE: Save comprehensive debug images ---
        print(f"Could not find a 4-point approximation. Saving debug images to {DEBUG_IMAGE_DIR}")
        cv2.imwrite(os.path.join(DEBUG_IMAGE_DIR, f'{timestamp}_00_original.png'), image)
        cv2.imwrite(os.path.join(DEBUG_IMAGE_DIR, f'{timestamp}_01_thresh.png'), thresh)

        img_with_contours = image.copy()
        cv2.drawContours(img_with_contours, contours, -1, (0, 255, 0), 1) # All contours green
        cv2.imwrite(os.path.join(DEBUG_IMAGE_DIR, f'{timestamp}_02_all_contours.png'), img_with_contours)

        img_with_attempts = image.copy()
        # Draw largest contour (red)
        cv2.drawContours(img_with_attempts, [largest_contour], -1, (0, 0, 255), 2)
        # Draw convex hull (cyan)
        if hull is not None:
             cv2.drawContours(img_with_attempts, [hull], -1, (255, 255, 0), 1)
        # Draw hull approximation (yellow, if exists and != 4 points)
        if approx_hull is not None and len(approx_hull) != 4:
             cv2.drawContours(img_with_attempts, [approx_hull], -1, (0, 255, 255), 2)
             hull_pts = len(approx_hull)
        else:
             hull_pts = 'N/A' if approx_hull is None else 4
        # Draw original approximation (blue, if exists and != 4 points)
        if approx_orig is not None and len(approx_orig) != 4:
            cv2.drawContours(img_with_attempts, [approx_orig], -1, (255, 0, 0), 2)
            orig_pts = len(approx_orig)
        else:
             orig_pts = 'N/A' if approx_orig is None else 4

        # Add text overlay with point counts
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(img_with_attempts, f'LargestContour (Red)', (10, 30), font, 0.6, (0,0,255), 2)
        cv2.putText(img_with_attempts, f'Hull (Cyan)', (10, 50), font, 0.6, (255,255,0), 2)
        cv2.putText(img_with_attempts, f'ApproxHull Pts: {hull_pts} (Yellow if !=4)', (10, 70), font, 0.6, (0,255,255), 2)
        cv2.putText(img_with_attempts, f'ApproxOrig Pts: {orig_pts} (Blue if !=4)', (10, 90), font, 0.6, (255,0,0), 2)

        cv2.imwrite(os.path.join(DEBUG_IMAGE_DIR, f'{timestamp}_03_attempts_hull{hull_pts}_orig{orig_pts}.png'), img_with_attempts)
        # ------------------------------------
        return None

def split_board_into_squares(board_image: np.ndarray, board_size: int = 8) -> list[np.ndarray]:
    """
    Splits the warped board image into 64 individual square images.

    Args:
        board_image: The (square) warped image of the board.
        board_size: The number of squares along one edge (usually 8).

    Returns:
        A list of 64 NumPy arrays, each representing a square.
        Squares are ordered from top-left (a8) to bottom-right (h1).
    """
    squares = []
    h, w = board_image.shape[:2]
    sq_h, sq_w = h // board_size, w // board_size

    if h % board_size != 0 or w % board_size != 0:
        print(f"Warning: Board image dimensions ({h}x{w}) not perfectly divisible by board size ({board_size}).")

    for i in range(board_size):
        for j in range(board_size):
            y_start, y_end = i * sq_h, (i + 1) * sq_h
            x_start, x_end = j * sq_w, (j + 1) * sq_w
            square = board_image[y_start:y_end, x_start:x_end]
            squares.append(square)
    return squares

# Example Usage (for testing)
if __name__ == '__main__':
    # Load a sample image (replace 'sample_board.jpg' with your image)
    img_path = '../sample_images/board1.jpg' # Adjust path if needed
    img = cv2.imread(img_path)

    if img is None:
        print(f"Error loading image: {img_path}")
    else:
        print("Image loaded successfully.")
        warped_board = find_and_warp_board(img)

        if warped_board is not None:
            print("Board found and warped.")
            # cv2.imshow("Warped Board", warped_board)
            # cv2.waitKey(0)

            squares_list = split_board_into_squares(warped_board)
            print(f"Board split into {len(squares_list)} squares.")

            # Example: Display the first square (a8)
            # if squares_list:
            #     cv2.imshow("First Square (a8)", squares_list[0])
            #     cv2.waitKey(0)

            cv2.destroyAllWindows()
        else:
            print("Could not find or warp the chessboard.") 