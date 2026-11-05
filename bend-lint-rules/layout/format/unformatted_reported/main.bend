import   Base


type N is Data:
    Z{}  
    S{p:N}
def id(x:N)->N:
	x  
def main()->N: id(S{Z{}})
# bend-lint: expect-file layout/format@warning -- spacing, gaps, indentation, CRLF, no final newline