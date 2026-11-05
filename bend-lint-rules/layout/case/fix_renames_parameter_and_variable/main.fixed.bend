import Base

type my_box is Data:
  MyBox{}

def twice(+input_val: U32) -> U32:
  out_val : U32 = (input_val + input_val : U32)
  out_val

def main() -> U32:
  twice(1)
