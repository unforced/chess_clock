import cv2
import numpy as np

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
    Finds the largest square contour in the image, assumes it's the chessboard,
    and returns a warped, top-down view.

    Args:
        image: Input image (NumPy array).
        output_size: The desired size of the output warped square image.

    Returns:
        A warped square image of the board, or None if no board is found.
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    # Use adaptive thresholding to handle varying lighting conditions
    thresh = cv2.adaptiveThreshold(blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                   cv2.THRESH_BINARY_INV, 11, 2)

    # Find contours
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if not contours:
        print("No contours found")
        return None

    # Find the largest contour which we assume is the board outline
    largest_contour = max(contours, key=cv2.contourArea)

    # Approximate the contour to a polygon
    peri = cv2.arcLength(largest_contour, True)
    approx = cv2.approxPolyDP(largest_contour, 0.02 * peri, True)

    # Check if the approximated contour has 4 points (a quadrilateral)
    if len(approx) == 4:
        corners = approx.reshape(4, 2)

        # Warp the perspective
        warped = four_point_transform(image, corners.astype(np.float32))

        # Resize to a standard size
        resized_warped = cv2.resize(warped, (output_size, output_size))
        return resized_warped
    else:
        print(f"Largest contour found is not a quadrilateral (found {len(approx)} points). Cannot warp.")
        # Optional: Draw the largest contour for debugging
        # cv2.drawContours(image, [largest_contour], -1, (0, 255, 0), 3)
        # cv2.imshow("Largest Contour", image)
        # cv2.waitKey(0)
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