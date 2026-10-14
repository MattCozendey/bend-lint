# Selection, locked-correct crossover, and mutation, following the p5 project.
import Base
import ../probability/math.bend as R

type Genome is Data:
  Genome{genes: List<&2, U32>, fitness: U32}

def score(target: List<&2, U32>, genes: List<&2, U32>) -> U32:
  match target:
    case []: 0
    case t <> ts:
      match genes:
        case []: 0
        case g <> gs: (Bool.to_u32(U32.is_eq(t,g)) + score(ts,gs) : U32)

def dna(n: Nat, +alphabet: U32, +seed: U32) -> List<&2, U32>:
  match n:
    case 0n: []
    case 1n+p: (R.hash(seed) % alphabet : U32) <> dna(p,alphabet,R.hash((seed + 1013904223 : U32)))

def evaluated(+genes: List<&2, U32>, target: List<&2, U32>) -> Genome:
  Genome{genes,score(target,genes)}

def initial(n: Nat, +length: Nat, +alphabet: U32, +seed: U32, +target: List<&2, U32>) -> List<&2, Genome>:
  match n:
    case 0n: []
    case 1n+p: evaluated(dna(length,alphabet,seed),target) <> initial(p,length,alphabet,R.hash((seed + 2654435769 : U32)),target)

def genes(g: Genome) -> List<&2, U32>:
  Genome{dna,fitness} = g
  dna

def fitness(g: Genome) -> U32:
  Genome{dna,f} = g
  f

def total(population: List<&2, Genome>) -> U32:
  match population:
    case []: 0
    case g <> rest: (fitness(g) + total(rest) : U32)

def weights(population: List<&2, Genome>) -> U32:
  match population:
    case []: 0
    case g <> rest: (fitness(g) + 1 + weights(rest) : U32)

def better(+a: Genome, +b: Genome) -> Genome:
  Bool.pick(Genome,(fitness(a) >= fitness(b) : U32),a,b)

def best(population: List<&2, Genome>) -> Genome:
  match population:
    case []: Genome{[],0}
    case g <> rest: better(g,best(rest))

def select(population: List<&2, Genome>, +ticket: U32) -> Genome:
  match population:
    case []: Genome{[],0}
    case +g <> rest:
      +w = (fitness(g) + 1 : U32)
      Bool.pick(Genome,(ticket < w : U32),g,select(rest,(ticket - U32.min(ticket,w) : U32)))

def gene(+target: U32, +a: U32, +b: U32, alphabet: U32, rate: U32, +seed: U32) -> U32:
  Bool.pick(U32,U32.is_eq(a,target) || U32.is_eq(b,target),target,Bool.pick(U32,(R.hash(seed) % 10000 < rate : U32),(R.hash((seed + 17 : U32)) % alphabet : U32),Bool.pick(U32,(R.hash((seed + 29 : U32)) % 2 < 1 : U32),a,b)))

def cross(target: List<&2, U32>, mom: List<&2, U32>, dad: List<&2, U32>, +alphabet: U32, +rate: U32, +seed: U32) -> List<&2, U32>:
  match target:
    case []: []
    case +t <> ts:
      match mom:
        case []: []
        case a <> aa:
          match dad:
            case []: []
            case b <> bb: gene(t,a,b,alphabet,rate,seed) <> cross(ts,aa,bb,alphabet,rate,R.hash((seed + 1013904223 : U32)))

def offspring(n: Nat, +population: List<&2, Genome>, +target: List<&2, U32>, +weight: U32, +alphabet: U32, +rate: U32, +seed: U32) -> List<&2, Genome>:
  match n:
    case 0n: []
    case 1n+p:
      mother = genes(select(population,(R.hash(seed) % weight : U32)))
      father = genes(select(population,(R.hash((seed + 12345 : U32)) % weight : U32)))
      evaluated(cross(target,mother,father,alphabet,rate,R.hash((seed + 777 : U32))),target) <> offspring(p,population,target,weight,alphabet,rate,R.hash((seed + 2654435769 : U32)))

def generation(n: Nat, +population: List<&2, Genome>, target: List<&2, U32>, alphabet: U32, rate: U32, seed: U32) -> List<&2, Genome>:
  match n:
    case 0n: []
    case 1n+p: best(population) <> offspring(p,population,target,weights(population),alphabet,rate,seed)

# A different stream from offspring seeds avoids reusing all but one child
# mutation stream in successive generations.
def next_seed(seed: U32) -> U32:
  R.hash((seed + 374761393 : U32))
