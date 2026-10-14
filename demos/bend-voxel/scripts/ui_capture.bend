import Base

def Capture.pixel(read: Array<U32> & U32) -> Array<U32> & Image:
	(pixels, color) = read
	(pixels, Pix{color})

def Capture.next(converted: Array<U32> & Image, next: Array<U32> -> Image -> Array<U32> & Image) -> Array<U32> & Image:
	(pixels, image) = converted
	next(pixels, image)

def Capture.tile(+depth: Nat, +stride: U32, +x: U32, +y: U32, +side: U32, pixels: Array<U32>) -> Array<U32> & Image:
	match depth:
		case 0n:
			Capture.pixel(Array.get(U32, pixels, (y * stride + x : U32)))
		case 1n+rest:
			+half = (side / 2 : U32)
			Capture.next(Capture.tile(rest, stride, x, y, half, pixels), pixels => tl =>
				Capture.next(Capture.tile(rest, stride, (x + half : U32), y, half, pixels), pixels => tr =>
					Capture.next(Capture.tile(rest, stride, x, (y + half : U32), half, pixels), pixels => bl =>
						Capture.next(Capture.tile(rest, stride, (x + half : U32), (y + half : U32), half, pixels), pixels => br =>
							(pixels, Qua{tl, tr, bl, br})))))

def Capture.finished(converted: Array<U32> & Image) -> Result<&2, &2, String, Image>:
	(pixels, image) = converted
	Done{image}

def Capture.sized(valid: Bool, pixels: Array<U32>) -> Result<&2, &2, String, Image>:
	match valid:
		case False{}:
			Fail{"UI capture: expected exactly 262144 RGB pixels"}
		case True{}:
			Capture.finished(Capture.tile(9n, 512, 0, 0, 512, pixels))

def Capture.capacity(sized: Array<U32> & U32) -> Result<&2, &2, String, Image>:
	(pixels, count) = sized
	Capture.sized(U32.is_eq(count, 262144), pixels)

def Capture.dimensions(valid: Bool, pixels: Array<U32>) -> Result<&2, &2, String, Image>:
	match valid:
		case False{}:
			Fail{"UI capture: expected a 512x512 client"}
		case True{}:
			Capture.capacity(Array.size(U32, pixels))

def Capture.image(capture: Capture) -> Result<&2, &2, String, Image>:
	Capture{width, height, pixels} = capture
	Capture.dimensions(U32.is_eq(width, 512) && U32.is_eq(height, 512), pixels)
