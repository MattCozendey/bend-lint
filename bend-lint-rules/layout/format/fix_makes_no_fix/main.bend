import   Base


type N is Data:
    Z{}  
    S{p:N}
def id(x:N)->N:
	x  
def main()->N: id(S{Z{}})