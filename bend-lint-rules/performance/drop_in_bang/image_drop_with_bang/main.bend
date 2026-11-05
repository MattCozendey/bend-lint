import Base

def main(img: Image) -> Unit:
  # bend-lint: expect-next performance/drop_in_bang@warning -- Image.drop! only frees
  Image.drop!(img)
