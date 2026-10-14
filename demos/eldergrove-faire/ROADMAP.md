# Eldergrove Faire: Roadmap

Last updated: 2026-09-24 · M1-M10 done; v1.1.0 released for Windows (native .exe) and Linux.

## Decisions

| Question | Decision |
|---|---|
| GPU rendering | **Yes**, tools installed, but Bend's CUDA path cannot run under WSL2 (no concurrent managed memory). The CPU restructure reached the target on its own. |
| Pricing model | **Both at once:** park entry fee *and* per-ride/shop prices, each settable (either can be 0). |
| Queues | **Full RCT-style queue paths:** a queue tool, visible lines of guests, one queue per ride entrance. |
| Terrain slopes | **Not for now.** Flat terraces with cliffs. |
| Game mode | **Both:** sandbox and scenarios with goals. |
| Milestone order | Performance → riders + art → economy + UI → controls + problems + staff → content → structure → custom coasters. |
| Controls | WASD and the arrows move the camera, always; coaster building gets its own construction window (M8) instead of the W/A/D/Q/Z keys. |
| Placing things | Every tool shows a ghost of what it would place, tinted green where it can go and red where it can't, with the cost. |
| Coaster crashes | None. A failed test reports where and why instead. A ride can be edited only while closed, and opened only when valid (circuit complete, tested); the safety laws are about open rides. |
| Frame rate | 60 fps at the default zoom and window size; dynamic resolution keeps the rest smooth. |
| Children | Yes, as individual guests (smaller; they prefer gentle rides). No families or groups for now. |
| Working through M8 | Straight through, without stopping between milestones. Small design calls are made along the way and recorded in "Calls made along the way" below. |
| Ride exits | Any path tile touching the ride is its exit, marked with an exit arch; the queue's front tile gets an entrance arch. Riders step off toward the exit. |
| Complete rides | A ride runs only with both an entrance (queue) and an exit (path); a warning shows until then. Shops need neither. |
| Ride cycles | Each ride has its own cycle (load, run, unload) with minimum and maximum waits. |
| Sound | Yes: our own procedurally generated sounds and old-style music, made in code like the art. |
| Version control | GitHub repo `RedLynx101/eldergrove-faire`, MIT licensed. Commit after every spike and milestone. |

## Calls made along the way
Small design decisions made while working, listed here so they can be revisited.

- **Mess is capped at 600 pieces.** Past that, guests stop dropping litter. It keeps the list, the save file
  and the per-tick sweep check bounded; a park that dirty is already failing.
- **A bin holds 15 pieces.** A guest who finishes something within one tile of a bin with room uses it. A
  full bin shows a heap and flies; Brownies (spike 6) will empty them.
- **Dirt thresholds.** A tile's dirt is its litter plus three times its sick. At 2 or more, guests on it lose
  a point of happiness every 64 ticks (two at 6 or more); at 4 or more they may think "this path is filthy".
  Mess lowers the park rating by half a point per piece (at most 150). Measured on the starter park at month
  2: happiness 51% with mess against 57% without, so it is pressure, not collapse, until staff arrive.
- **Benches seat tired guests** (energy under 50) who reach a bench tile's centre, for up to 400 ticks or
  until rested; they draw sitting on the seat.
- **Furniture placement.** Bins stand by a path tile's right-hand back edge, benches along its left-hand back
  edge, lamps at its back corner, so walkers stay visible. One piece of furniture per tile; demolish removes
  it before the path.
- **Toolbar tabs now, not in spike 8.** Adding three furniture tools made the flat bar too long, so the
  categories came early: inspect and demolish on the left, five tabs (paths and furniture, land, scenery,
  rides, shops), then the open tab's tools. Keys 1-5 open a tab and pressing the same key again steps through
  its tools; I inspects, X demolishes, U picks the queue line. Hovering any button names it on the strip
  above the bar. Spike 8 keeps the rest (window style, options, a staff tab).
- **The starter park has furniture**: three bins, three benches and three lanterns along its paths.
- **The Privy** (shops tab, 150 gold, 5 upkeep a month) serves four at a time, 40 ticks each, free by default;
  guests will pay up to 2 gold. The bladder need rises one point every 16 ticks, 40 more after a potion and
  15 after a meal; above 170 a guest heads for a privy before anything else, above 180 they think "I need
  the privy", above 220 their happiness drains. The starter park gets two privies.
- **needs_bounded does not cover the bladder yet.** The field is clamped to 0..255 like the other needs,
  but the law in LAWS.bend lists hunger, thirst, energy, nausea and happiness; I only added the new field to
  its pattern. Extending the law is the owner's call.
- **Nausea now builds up.** Before, a ride's nausea was added on boarding and wore off during the ride, so
  peak nausea across the park was about 50 and nobody ever felt queasy. Now a rider gains three quarters of
  the ride's nausea rating on getting off, it wears off at 1 point per 16 ticks (was 3), and a guest above 95
  is sick with a 1-in-512 chance each tick: 32 sick puddles in 8000 ticks on the starter park.
- **Breakdowns.** A ride's reliability starts at 100% and, while it runs, drops about one point (of 255) every
  128 ticks; every 64 ticks it may break down with a chance of (255 - reliability)/8 in 1024. A broken ride
  freezes mid-cycle: no one boards, riders stay aboard (coaster riders keep circling), lose happiness and
  think "stuck on the ...". Until Tinkers arrive (spike 6) a breakdown clears itself after 1800 ticks, and a
  repair adds 60 points, capped by age (the cap falls 3 points a month, to no lower than 47%). On the starter
  park, reliability settles between 60% and 80% over the first year. Shops and privies never break.
- **Staff posts instead of drawn patrol zones.** Each hire gets a post, a ride's tile taken in turn, and
  patrols within 6 tiles of it when idle. Brownies go for the litter that is nearest counting both their own
  distance and their post's (within 12 tiles of the post), so two Brownies spread out. Drawing zones by
  hand can come with the interface revamp if posts prove too coarse.
- **What each job does.** Brownies sweep what lies within three quarters of a tile of them, empty bins on
  and beside their tile and mend smashed furniture. Tinkers walk to a broken ride's exit (or entrance) and
  repair it 30 times faster than it would repair itself (about a second). Watch Knights and Bards mark the
  paved tiles around them every 64 ticks; guests read the marks: no vandalism within two tiles of a Knight's
  recent path, and a Bard's music within one tile adds happiness.
- **Vandalism came with the Knights.** A miserable guest (happiness under 40) at a tile centre may smash
  the furniture there (1 in 256 per visit). A smashed bench can't be sat on, a smashed bin takes nothing and
  a smashed lantern goes dark, until a Brownie mends it.
- **Wages:** Brownies 20, Tinkers 35, Watch Knights 30, Bards 25 gold a month, paid as one ledger entry
  (kind 11, "staff wages" in the finances window). At most 40 staff. The starter park comes with two
  Brownies, a Tinker, a Knight and a Bard (130 a month). On the starter park at month 3 they cut litter from
  118 pieces to 36 and raise happiness from 52% to 59%.
- **wages_booked is stated over lists.** Proofs can't normalise arithmetic on symbolic numbers, so the law
  says: the wage entries a step books are exactly one entry of the staff's monthly total when a tick turns
  the month (none with no staff), and none otherwise. With money_conserved, that pins wages to the ledger.
- **People.** Eight folk now, equally common: wizard, knight, elf, dwarf, halfling (barefoot, curly hair),
  gnome (red pointed cap, white beard), orc (green, tusked, broad, topknot) and commoner (hair, sometimes a
  straw hat or a beard). One guest in four is a child: two rows shorter, and they take far less intensity
  (60-187 against 220-731), so they stick to the carousel and gentler rides. An outfit on top: adventurer,
  noble (a purple cape with gold trim and a gold belt; "Lord" or "Lady"), merchant (a pack) or pilgrim (a
  grey hooded cloak and a staff; "Pilgrim"). Names follow the folk: halfling and gnome family names, orc
  epithets, commoners' trades. Riders on rides keep their folk and colours but not outfits or childhood
  (a rider code has 7 bits). `./park --people out.ppm` draws the whole cast for review.
- **Options (O, or the OPTIONS button).** Window size 1024x640, 1280x800 or 1600x1000; pixels stretched to fit
  (every size has the frame's 8:5 shape, so nothing is cropped) or whole pixels (the largest integer scale,
  centred, black around it). The frame stays 512x320 logical pixels; the native blit (win_frame.c) scales it
  and maps the mouse back, and a new effect, Win.config, has the frame thread resize the window between
  frames. Music and effects volume in four steps each (each step halves). Options last for the session.
- **Dynamic resolution** (on by default): when a second of frames runs under 52 a second, the world is
  drawn at half resolution (one sample per 2x2 block) for about ten seconds, then full resolution is tried
  again. Tiles with interface on them (text, panels, icons) always draw at full resolution, so the HUD and
  windows stay sharp. Measured live: 1280x800 at 60 fps, 1600x1000 at 59 fps on the starter park.
- **Windows** share one frame with a drop shadow; the bottom right holds STAFF / PARK / OPTIONS / FINANCES.
  `PARK_OPT=n ./park` starts with options n (a testing aid).
- **Six toolbar tabs for M6**: paths and furniture, land, scenery, gentle rides, thrill rides, shops (keys
  1-6). Tools for M6's rides and shops are numbered 30-40, building ride kinds 7-17.
- **The new shops.** Healer's Tent: queasy guests (nausea over 80) head there first after the privy; a visit
  takes 150 off their nausea. Wisp Seller: a glowing wisp on a string, bought on a whim by happy guests with
  empty hands (+20 happiness); a finished wisp floats away, leaving no litter. Enchanted Ices: bought on a
  whim too, eases hunger and thirst, and its wrapper is litter. Carried items now take three bits.
- **The eight new rides** (excitement, intensity, nausea in hundredths; cost; seats 8; size):
  Griffin Swing 3.20/3.80/2.50, 1400, 2x2; Wheel of Stars 1.90/0.40/0.20, 1100, 2x2; Lich's Crypt
  2.70/1.20/0.60, 1500, 2x2; Golem Bumpers 2.30/1.50/0.50, 1000, 2x2; Hedge Labyrinth 1.60/0.20/0.10, 700,
  2x2; Dragon's Eyrie 1.80/0.30/0.30, 1000, 1x1; Wizard's Whirl 3.90/4.60/3.80, 1600, 1x1; Mermaid Flume
  3.10/2.00/0.90, 1900, 2x2. All run in cycles with loading waits like the carousel and wear like it.
  Gentle ones (wheel, labyrinth, eyrie, bumpers, crypt) sit in their own tab, so children's rides are easy
  to find. The Lich's Crypt hides its riders while they are inside; the flume is drawn as a raised loop on
  the ride's own square rather than a track of its own. `./park --rides out.ppm T` draws all eight at T ticks
  into a run with every seat taken. The starter park gets a Wheel of Stars at the central crossing.
- **Scenery** (scenery tab): statues (knight, dragon, wizard, griffin; R picks), a fountain, flower beds (R
  picks red, blue or gold), castle walls and fences that join their neighbours. They are tree tiles with
  variants 4 and up. Each decoration adds 3 to the park rating (at most 150, counted every 64 ticks), and a
  guest passing a decoration now and then gains a little happiness. The starter park gets statues, flower
  beds and a fountain by the crossing, a short wall and a fence.
- **Stairs** need no tool: path tiles a level apart join, and the higher tile's face toward the lower one is
  drawn as a flight of steps. Only paths climb (queues, the gate and rides stay level), one level per tile.
  Guests' pathfinding follows the height of each step. Guests still pop up or down a level as they cross a
  tile edge rather than walking up the steps.
- **Bridges:** the path tool builds over water, drawn as planks with wooden rails on the open sides; the
  water stays beneath (demolishing gives it back). Bridges sit at water level and join the banks by stairs.
  Bridges over lower paths or coaster track are not done: the map keeps one height per tile, and a raised
  path above another object would need a second layer.
- The starter park gets a bridge across the lake joining the north and middle paths, and a stepped path up
  the hill to a griffin statue.

- **Day and night** run on their own clock: a day is 2048 ticks (about 34 seconds at normal speed), with
  dusk, night and dawn in its last 44%. Night tints the world blue and dark; lanterns, ride lights, wisps,
  the crypt's windows and fireflies glow (colours carry a glow bit that the tint leaves alone), and each
  lantern lights a pool of ground. The interface is never tinted. Night doesn't change the simulation.
- **Rain** falls on one day in four (a hash of the day number): streaks over the world, an overcast tint, a
  hiss in the ambience, and half the usual arrivals.

- **Research** lives in the park's books (so it is saved): thirteen discoveries (the eight M6 rides, the
  three new shops' worth of tools, statues and fountains, walls and fences) unlock in a fixed order. Steady
  funding costs 150 a month and needs about three months a discovery; lavish costs 400 and needs about a
  month and a half. Spending is a ledger entry (kind 12, research), so wages_booked's proof grew a step. In
  sandbox everything starts researched. Locked tools show dim with a padlock; the sim itself doesn't stop a
  locked build, the toolbar does.
- **Buying land:** the Buy Land tool (land tab, 60 gold) turns wild forest at the park's edge into open
  grass, a tile at a time, next to land that isn't wild. Construction rights (building over land you don't
  own) are not done.
- Ride and shop tools had no placement ghost since M6 began (the ghost only knew tools 1-16); fixed.

- **Scenarios and the main menu.** The live game opens on a menu over the running park: Sandbox (the
  Eldergrove Faire, everything researched), three scenarios, Load and Quit. Misty Hollow: an almost empty
  vale with 12000 gold; 400 guests and a rating of 600 by month 8. The Dragon's Debt: the starter park with
  2000 gold and a 15000 loan; repay it with 300 guests by month 12. The Grand Tourney: the starter park,
  20000 gold, nothing researched; rating 850 and 650 guests by month 10. Scenarios start with steady
  research funding. The scenario and its outcome are kept in the books, so saves keep them; the outcome is
  recorded through park ops 50 (won) and 51 (lost), checked every step, and announced in a window. OPTIONS
  has a MAIN MENU button. `./park --scen K MONTHS` plays scenario K and reports each month.
- **Awards**, checked each new month, first earned wins: tidiest park (under 15 pieces of mess with 150+
  guests), most beautiful (20+ decorations), happiest guests (75%+ with 200+ guests), best staffed (8+
  staff), most thrilling (4+ thrill rides). An award is announced in the message bar with a bell. Awards
  don't change the simulation.

- **Crowds past 700 without route maps.** Measured: the simulation costs 4.0 ms a tick at 700 guests and
  7.3 ms at 1200, growing in a straight line, while drawing a frame of 1200 guests costs about twice that.
  Shared route maps would speed up the part that isn't the bottleneck, so the crowd cap simply rises to 1200
  and dynamic resolution absorbs the drawing. Live, 1100 guests ran at about 40 fps on a machine that was
  running slow that day (it gave 60 at 700 earlier). Route maps stay an option if the sim ever dominates.
- **Up to 8 coasters per park.** Each track keeps its own pieces, trains and settings; its tiles carry
  the coaster's number, so clicking any track tile opens the right ride. Riders are keyed by coaster and
  train, so two coasters never show each other's passengers.
- **Opening an unfinished track does nothing.** Before, it placed trains on a track that was not a closed
  circuit while leaving the ride shut; now the track stays empty until the circuit closes.
- **Steep slopes face the camera or run along the view.** In this projection a slope that climbs two
  levels in one tile, heading away from the camera, is seen exactly edge-on, so it draws as a rail over a
  band of timber; heading toward the camera it draws as a full ladder of track. Physics and testing
  treat all four the same.
- **Piece buttons build straight away.** Hovering a button previews that piece as the ghost; a click or
  its key builds it (RCT2 has a separate build button; one click fewer here, and undo is one key).
  Buttons for pieces that won't fit turn brown, so you see what's possible before trying.
- **Piece prices:** straight 30, gentle slopes and flat turns 40, brakes and banked turns 50, steep slopes,
  lift hill and station 60; taking a piece off gives half back. The track keys work while a construction
  window is open (the front-most one), not with the coaster tool.
- **Stations only extend the platform:** a station piece can only follow another station piece.
- **The highest track is level 12**, so nothing is ever left with no piece that fits above it.
- **Coaster types differ in top speed and look.** Wyrm 90, Dwarven Minecart 64, Griffin Flyer 100 (speed
  units per tick); each has its own rail, sleeper and support colours and its own cars. The Flyer's cars
  hang 13 px below the rails on a bar. Type, trains and lift speed can change only while the coaster is
  closed, and changing one takes its trains off (it opens again from the ride window).
- **Trains:** "as many as fit" (one in every third block) by default; the window steps it down to 1 or back
  up. Cars per train stay at three (six seats): changing them would touch boarding and its proven laws.
- **Lift speed** runs 12 to 36 in steps of 4 (20 by default).
- **no_collisions gained a parameter.** Train physics now reads the coaster's settings, so `Blocks.step`
  takes them and the law quantifies over them too (`for +cfg: U32`). A mechanical change to LAWS.bend; the
  proof threads the value through unchanged.
- **Tests are decided by a dry run, shown by a real train.** The in-game physics never lets a train stop
  (it crawls at 10 at worst), so pass or fail comes from a dry run over the pieces: energy is speed squared,
  a level of height is worth 381 (1.5 m at km/h), the station pushes to 10 km/h, the lift to its speed,
  friction takes 1/32 of the energy a piece plus a little (flat turns 1/16, banked about 1/25), brakes cap
  at 20 km/h. A climb the energy can't pay for is the stall piece. The test train then runs for real, and
  the test ends when it comes round to the station (pass) or reaches the stall piece (fail).
- **What a test measures:** top speed (km/h), length (4 m a piece), height and drops (1.5 m a level),
  vertical G at the bottom of drops (12 m radius after gentle, 6 m after steep), lateral G on turns (4 m
  radius; banking takes 60% off), negative G and air time over crests. The ratings follow from these
  (base 2.00 Wyrm, 1.50 Minecart, 2.50 Flyer); a ride with intensity past 10 loses half its excitement.
  The starter Wyrm rates about 4.3 / 3.1 / 1.6.
- **A pre-built coaster comes tested:** track op 25 marks a track tested if its dry run passes, without
  playing ticks at startup. Nothing in the UI sends it.
- **open_only_tested is stated on the track:** `open` implies the test is running or passed. Guests board
  only a passed coaster (the station counts as closed during a test). Wherever code opens a track it
  sets `open` to (a condition and the circuit check) and "the test stands", so both coaster laws follow
  from two small Boolean lemmas.
- **Tracks are capped at 250 pieces**, so a piece index fits the test's bookkeeping.
- **The follow cam lives in the UI, not the park.** Following is a view setting (UI field `fol`: guest,
  staff member or ride, and its id), so it isn't saved and costs the simulation nothing. The camera centres
  the target each step; a coaster's target is its lead car, any other ride its middle, and a guest who
  leaves ends the follow. The staff window's FOLLOW steps through that row's staff.
- **Steep-up pieces get a taller hit box than the rest** (22 px over 12): giving every piece the taller box
  cost about 4% of frame time.
- **Toolbar clicks were read as tab clicks.** Tab buttons carry codes 20-25 and the click handler took any
  code from 20 up as a tab, so every tool coded 30 or more (rides, shops, scenery, buying land) opened a
  bogus tab instead. Only 20-25 are tabs now; the UI test clicks a gentle ride's tool.
- **Speed levels:** pause, 1/4, 1/2 (default), 1x, 2x, 3x; the slow ones tick every fourth or second frame.
  Space remembers the level it paused. Benches run at 1x so their numbers stay comparable.
- **Dynamic resolution** now drops to half size only after two 32-frame samples under 22 fps, and returns
  after ten samples at 45 fps or more; it used to drop below 52 fps and retry every ten seconds.
- **needs_bounded covers the bladder** (LAWS.bend, at the owner's request); the clamp proof gained a step.
- **Picking uses the renderer.** A click walks the drawn world list front to back at the cursor pixel and
  takes the first opaque drawable: a guest (id from its animation phase), a staff member, a ride (ride
  drawables now carry their index), the ground or track (then the tile decides), or scenery (nothing
  opens). It is built only on inspect clicks.
- **The follow cam follows the train with the lowest id.** The block ring turns every tick, so "the first
  train in the list" alternated between trains.
- **Stairs are walked in the drawing only:** within half a tile of an edge toward a path a level up or
  down, a guest or staff member is drawn blended toward that height (continuous across the edge). The
  simulation still moves them tile to tile.
- **No coaster limit.** A track op now carries the coaster in 11 bits (up to 2048), types are drawn from a
  per-coaster list, the draw code keeps only the piece bits of a tile, and rider tables are sized to the
  park (64 trains a coaster). The coaster test builds 16 more stations (17 coasters).
- **Cuts and demolition are track ops** (26: from a piece to the end, never the first station piece; 27:
  the whole coaster, whose ride goes the way a demolished ride does). Both work while a coaster runs.
  Every change (pieces, settings, cuts) ends in `Track.recheck`: a closed circuit whose dry run passes
  starts a test run, anything else stays shut. Edits are allowed during a test run (they end it). Both
  coaster laws kept their proofs with two small lemmas each (a cut closes the track; a re-check is either
  the track or a test run); the wages proof took one more branch for the refund.
- **DEMOLISH asks twice:** the first click arms it for that ride (UI opt bits 19-31), the second removes the
  coaster; any other window click disarms it.
- **Cars:** each car layer is tested in its own along/across coordinates, so details follow the heading:
  the Wyrm's scales, spine ridge and (front car) a head with a gold jaw, horns and glowing eyes; the
  Minecart's plank seams, iron bands, rivets, rim and a lantern that glows at night; the Flyer's stripe,
  wing fins and a wheeled bogie on the rail. Every car except the Flyer's has a dark chassis with wheels.
- **Coaster sound by type** rides on a second sound word (the first is full): the loudest train's type
  picks the rumble (Wyrm timber clatter, Minecart iron rattle and buzz, Flyer deep whoosh). Riders
  scream when a train of an open, tested coaster goes down a drop at speed 45 or more, louder the faster
  it goes (a stand-in for the plan's "scaled by the biggest drop": speed on the drop tracks the drop).
- **Designs are plain acts.** A design is its piece count, settings and piece kinds (the shape follows from
  the kinds, so it turns with the station); building one is a station build, its type and lift speed, then
  each piece, applied through `Park.run`. No new core code, so every law holds as it did. Train count isn't
  kept (a new coaster runs as many as fit). The library is eight 256-value slots; every value fits a byte,
  so `designs.sav` is the list itself. Saving and building go through the loop's IO step (codes 3 and 5),
  which is where the library lives, so the input handlers didn't need it.
- **Bridges without a new layer in the save.** A deck's level sits in bits 24-27 of its tile's `a` (paths use
  bits 0-8, track 0-18), and a guest up on a deck carries bit 16 of `dir` (walking directions are 0-3,
  rider seats under 64 * 8). Stepping onto a tile whose deck is at the walker's height puts them on the deck;
  the layer only changes when a step crosses into the next tile, so the path search (which already carried
  heights along) needed nothing new. Walkways connect only level with other decks or paths (no stairs up to
  a deck); benches, dirt and litter underfoot belong to the ground. Cutting coaster track clears any deck
  over the cut pieces; demolishing a deck over track takes only the deck. No proof touched the walking or
  building code, so all laws held unchanged.
- **Cars per train: 1 to 20**, two seats a car, never more cars than the station has pieces. Settings bits
  8-12 (0 meaning the old three). Blocks now grow to a train's length (cars stand 300 progress apart), so a
  long train's tail never reaches the block behind it.
- **Seats up to 64 a ride.** Each ride has two occupancy words (seats 0-31, 32-63); the seat search is a scan
  (up to the ride's capacity) instead of eight unrolled steps; a rider's seat code is train * 64 + seat.
  A coaster's capacity rides in its station word (open | wait << 1 | seats << 13 | train << 20), which the
  boarding plan and the laws already took, so capacity_respected now reads `Ride.cap(ride, stn)`: a
  mechanical change to the law's helper (board_ok and all_boards_ok gained the station argument). The
  capacity and uniqueness proofs kept their shape: the step lemma, then induction over the scan.
- **Fixed: the train-count setting never took effect.** Since M8 spike 3 a local `left` (pieces left) shadowed
  the `left` parameter (trains left) in `Blocks.make`, so a train went in every third block regardless, and
  test runs could have several trains. Renamed; the coaster test checks a one-train setting.
- **A compiler limit:** nesting strict picks that each build a whole game (the shot's pictured parks) failed
  with "an arity over 255"; a match dispatch builds only the one needed.
- **Measured against M8 (interleaved runs, 200 guests):** at first the simulation was 14% slower and frames
  about 6%. Three strict evaluations were the cause: a second tile lookup in every pathfinding step (the
  deck check), a layer lookup for every walking guest every tick, and every drawn tile looking at its
  neighbours for a deck it didn't have. With those made lazy the simulation is within about 3% of M8, and
  frames within noise.
- **Going public (MIT).** The README was rewritten around fresh screenshots in `docs/images/` (rendered by the
  game's own shot and sheet modes); the three effect files adapted from Bend stay Apache-2.0
  (THIRD_PARTY_NOTICES.md). Headless shots no longer show "0 FPS" (the counter hides until it has a reading).
- **A browser build, measured:** Bend's JavaScript target runs the simulation at about 3 ms a tick, but
  drawing one frame took about 2.3 s under Node, roughly 150 times the native frame. A playable web version
  would compile the C output to WebAssembly (threads need cross-origin isolation headers) with a canvas and
  WebAudio in place of the X11 and PulseAudio effects.
- **v1.0.0 (Linux) packaging:** a clean build of the committed tree, stripped (4.7 MB), in a tarball with
  `play.sh` (starts from its own folder, so saves land beside it), `Play on Windows (WSL).cmd` (runs the same
  binary through WSL until the native build exists), a quick start and the licenses. It needs glibc 2.34+.
  Before upload it was tested unpacked in a fresh folder, and the Windows launcher was run from Windows.
- **M10: GCC, not clang, for Windows.** MSYS2's UCRT64 GCC 15 was already installed; clang wasn't. Two
  calling-convention problems came up. The work loop's segments `musttail` each other while passing the
  16-byte `Env` struct, which the Windows x64 convention passes by reference. So the segments get
  `sysv_abi` (the one edit to the generated C, inserted by `win/build.sh`, which refuses to build if
  Bend's output changes shape). GCC 15 then crashed (`choose_baseaddr`) on Windows-convention functions
  calling System V ones defined in the same file. `-mincoming-stack-boundary=4`, which only states the
  ABI's own 16-byte alignment, avoids that. Speed matches the clang-built Linux binary.
- **M10: waveOut over WASAPI.** It is far less code, and Windows routes it through WASAPI anyway.
  Latency is about 90 ms of blocks, similar to pacat's 80 ms. A process whose waveOut device still
  has queued blocks never finishes exiting, so the device is reset and closed at exit.
- **M10: a GUI program that attaches to a console.** Double-clicking opens no console window.
  Started from a console, it prints there. `win/build.sh --console` makes a console build for the
  developer modes.
- **v1.1.0 packaging:** both platforms from one clean `git archive` build. The Windows zip holds the
  exe, a quick start, the licenses, and the MinGW-w64 runtime licenses (the exe links them statically;
  it needs only DLLs that ship with Windows). The Linux tarball drops the WSL launcher, because the
  native exe replaces it.

## Done: M1, the vertical slice
Isometric fantasy map, paths, terrain editing, 4 enchanted tree kinds, Dragon Carousel, Arcane Spire, Potion
Stall, Troll Tavern, pre-built Wyrm Coaster with block signals and a track editor, guests with needs and
lookahead pathfinding, ledger economy, HUD/toolbar, save/load, custom C frame effect. Six laws proven.

## Done: M2, a steady 60 fps
**Result:** the live window holds 60 fps at 1024×640 with 700 guests (16.7 ms frames, paced), and runs at
77-80 fps uncapped (12.5-13.3 ms, `PARK_NOPACE=1`). All six laws still check; the save round-trip passes.

What it took:
1. **Profiling (`perf`, `tools/prof.sh`):** 38% of frame time was reference counting and freeing, and 26% was
   re-partitioning drawable lists at every quadtree level.
2. **Cell/tile rasterizer:** the frame is cut once per 64-px cell and once per 16-px tile. Lists handed down
   the tree are only matched (borrows, no counts), kept entries are copied from their fields, and tiles render
   with straight-line code instead of forking down to pixels. Frame time 21-27 ms → 8.4 ms.
3. **Pipelined frames:** the window effect fills and shows on a helper thread (`io_work`), while a forked
   computation simulates and draws the next frame on the worker pool. Costs one frame (~17 ms) of input
   latency.
4. **GPU: not possible under WSL.** Bend's CUDA runtime needs concurrent managed memory, which WSL2 does
   not provide (`CU_DEVICE_ATTRIBUTE_CONCURRENT_MANAGED_ACCESS = 0` on the RTX 3070 Ti here), so `!` falls
   back to the CPU. It would need native Linux. clang 19 vs 14 made no measurable difference for CPU builds.

Measure it yourself: `PARK_PROF=1 ./park --live 700 1500` (add `PARK_NOPACE=1` for the uncapped rate).
Still open: zoom levels and a larger window.

## Done: M3, riders you can see, queues, and the art pass
**Result:** guests visibly ride every ride and wait in real queue lines; two more laws are proven (eight in
all); the live window holds 60 fps with 700 guests (8-9 ms frames uncapped, faster than after M2).

- **Seats and boarding:** carousel and spire 8 seats, shops 4, each coaster train 6. Each tick one pass
  (`Boards.plan`) seats whoever is ready, in order. Guest updates, ticket sales and drawing all read that one
  plan; a rider's seat lives in their `dir` field.
- **Riders drawn in their own class, tunic and skin:** carousel dragons (the back half passes behind the
  pole), riders around the spire's ring (behind the tower at the back), coaster trains with ids (guests board
  the train in the station and leave when that train returns), buyers at shop counters.
- **Queue paths** (tool `U`, 12 gold a tile): a queue tile beside a ride is its entrance. Guests heading for a
  ride with a queue steer to its entrance, board only there, and wait for a seat. They join a line only at its
  free end (a lone tile, or the end away from the ride), keep half a tile apart, and riders leave onto a path
  beside the ride. Rope rails close every side except along the line, to the ride, and at the free end.
- **Terrain:** path curbs on open edges, shoreline foam, cliff lips (bright turf, dark overhang, hanging
  roots), grass blades and tufts.
- **Guests:** four-way facing (front and back views), a four-frame walk with a bob and a swinging hand,
  carried potions and tankards, thought bubbles (hungry, thirsty, queasy, tired, cross, delighted).
- **Rides:** twisted brass poles, a scalloped valance and twinkling lamps on the carousel; sparkles around the
  spire's orb; a framed potion sign; a hanging tankard sign at the tavern.
- **Trees and mushrooms:** shaded, clustered oak crowns with sway and shadows, frosted moonpine tiers,
  domed glowcaps with pulsing spots and gills, faceted crystals.
- **Laws 7 and 8:** **capacity_respected** (the boarding plan never seats anyone at or past the ride's seat
  count) and **riders_conserved** (nobody leaves the park from a ride). `Seat.free` became a chain of steps
  that each test `k < cap`, which made the first proof short. Not proven yet: that no two guests are planned
  into the same seat.
- **Speed:** tile lookups in the map's quadtree now walk into just the one child they need, which removed
  most of the reference-count work in the simulation (sim 3 ms → 1.2 ms a frame with 700 guests). The path
  search stops once it arrives, and ride entrances are worked out once a tick.

Known limits: guests who give up while queuing step off the line sideways; queues longer than the path
search's 12 steps are walked by feel (still in order, since a line offers only forward or back).

## Done: M4, ride cycles, economy, UI and sound
**Result:** rides run whole cycles through real entrances and exits; the park has windows for rides, guests,
the park and its finances; guests judge prices and say what they think; the park has its own synthesized
music and sounds; thirteen laws are proven. Commits `424e0d0` .. `44237a5`.

1. **Ride cycles and exits.** The carousel and spire load (from the queue's front), run start to finish,
   unload everyone toward the exit, and load again; loading ends when full, or when the first rider has
   waited the maximum, never before the minimum. The coaster's station unloads a returning train before
   loading it. A ride runs only with an entrance (a queue beside it, green arch) and an exit (a path beside
   it, red arch), else a warning blinks over it; shops need neither. Guests leave a queue only at its free
   end, quitters walk back out, and guests skip lines that are too long.
2. **Windows.** Up to four at once, dragged by the title bar, closed with X or Esc. Inspect tool (the
   default, key I; or right-click with any tool).
   - **Ride window:** open/close, price, riders and queue, minimum and maximum waits, customers, income,
     age, and ratings.
   - **Guest window:** a name from their id and class ("Sir Halvard of Wyvern Hill"), what they are doing,
     thoughts, needs, gold, and what they carry.
   - **Park window** (P): the park rating, guests, entry fee, and a guest graph.
   - **Finances window** (F): this month and last by category, profit, and loans.
3. **Ratings.** Excitement, intensity and nausea: fixed for the carousel and spire, worked out from the
   track for the coaster (turns, drops, height, length). Guests prefer exciting rides, skip ones wilder than
   their own taste, enjoy a ride by its excitement and come off queasy by its nausea.
4. **Economy.** Ledger kinds for tickets, food, drinks, entry fees, upkeep, construction, refunds, loans and
   interest, booked by month. Entry fee 0-40 (fewer guests come when it is steep, more when the park is
   well rated); park rating 0-999 from happiness, open rides and nausea; loans of 1000 at 1/80 a month.
5. **Guests who judge prices.** A ride is worth its excitement to a guest, a potion more the thirstier they
   are, a meal more the hungrier. Too dear: they skip it, think "not paying that for the X", and remember.
   They also think a ride was great, or too intense, and get fed up with long queues; fresh thoughts show in
   their bubble.
6. **Laws.** board_only_when_loading, ride_until_unloading, seats_unique, purchase_is_transfer and
   prices_bounded, all proven, thirteen in all.
7. **Sound.** An original organ waltz (32 bars of 3/4, oom-pah accompaniment) and synthesized effects:
   coins, a ride bell, the spire's wind, lift clacks, the coaster's roar, the crowd's murmur, a month chime,
   and UI clicks, thumps and buzzes. It is all made in `sound.bend`, sample by sample, and played through
   PulseAudio (`pacat`). M toggles the music, N the effects.
8. **Found and fixed on the way:**
   - A queue deadlock seen over a long run: shop-bound guests could enter queues and lock the line. With
     the fix, riders over 20000 ticks rose several times over (coaster 35 to 291).
   - Most of M4's frame cost, which was reference counting on the shared map root from the new queue
     rules. Free-end flags now live in the tiles, sales come from the boarding plan, and queue lengths are
     counted every 16 ticks.
   - The spire's orb now draws behind its riders.

**Performance:** on the same machine at the same moment, a full frame (sim, scene and raster) with 700 guests
costs about what M3's did. The machine was far slower late on 2026-09-23 than earlier that day (M3's own
build went from 8-9 ms to 25-29 ms uncapped), so the absolute frame rate needs re-measuring on a quiet
machine: `PARK_PROF=1 ./park --live 700 1500`.

**Known limits:**
- A crowd can still bunch at a short queue's free end.
- Guests may pick a ride whose queue is on the far side of the park.
- There is no music volume control besides on/off.

## Done: M5, controls, problems, staff and people
Spikes, in order:

1. (Done) **Controls and camera.** WASD (and the arrows) move the camera. Zoom in and out, in three steps (close,
   normal, far) with the mouse wheel or Page Up / Page Down. Every tool shows a **ghost preview** of what it
   would place under the mouse: green where it can go, red where it can't, with the cost beside it. That
   covers paths, queues, terrain, trees, rides at their full footprint, and demolish (which highlights what
   would go).
2. (Done) **Readable thoughts.** Redraw the thought icons at a size that reads. The hunger bubble is the worst: its
   white bone vanishes on the white bubble and leaves a brown cross. Every bubble gets a clear picture with a
   dark outline, and the guest window names each thought in words (it already does).
3. (Done) **Mess.** Guests drop litter; nauseous guests are sick after intense rides. Dirty paths lower
   happiness and the park rating. Path furniture: bins, benches (they restore energy) and lamps. Also done
   here: the toolbar tabs (see the calls above) and the law litter_accounted.
4. (Done) **The Privy.** Toilets, and a bathroom need.
5. (Done) **Breakdowns.** Rides lose reliability with age and break down; riders get stuck and unhappy until a
   repair.
6. (Done) **Staff**, hired from a staff window, with wages (through the ledger) and patrol areas:
   - Brownies (handymen) sweep litter, empty bins and water flowers.
   - Dwarven Tinkers (mechanics) inspect and repair rides.
   - Watch Knights (security) deter vandals, who smash benches and lamps.
   - Bards (entertainers) cheer guests up.
7. (Done) **More people.** More guest variants:
   - new folk: halflings, gnomes, orcs;
   - more outfits: nobles, merchants, pilgrims;
   - hats, hair, beards and cloaks;
   - children (smaller, and they prefer gentle rides).
   Staff wear their own uniforms.
8. (Done) **The interface, revamped:**
   - the toolbar grouped into categories (paths, terrain, scenery, rides, shops, staff) with hover
     tooltips;
   - a consistent window style;
   - an options window: window size (1024×640, 1280×800, 1600×1000), pixel scale, and dynamic resolution
     (the drawn resolution drops when the frame rate falls below 60, and comes back when it recovers);
   - music and effects volume.
9. (Done) Laws: **litter_accounted** (litter appears only when a guest drops it or is sick, and disappears only when
   a Brownie sweeps it or a bin takes it) and **wages_booked** (every wage goes through the ledger).

## Done: M6, more to build
- **Rides:** Griffin Swing (swinging ship), Wheel of Stars (Ferris wheel), Lich's Crypt (haunted dark ride),
  Golem Bumpers (dodgems), Hedge Labyrinth (maze), Dragon's Eyrie (observation tower), Wizard's Whirl
  (top spin), Mermaid Flume (log flume).
- **Shops:** Healer's Tent (first aid), Wisp Seller (balloons), Enchanted Ices.
- **Scenery:** castle walls, statues, fountains, flower beds, fences. Scenery raises the park rating.
- **Stairs and bridges.** The path tool builds stairs between terrace heights by itself, as does the queue
  tool. A bridge tool raises paths over water, lower paths and track, on supports that match the theme. The
  land stays terraced (no slopes).

## Done: M7, structure
- Scenarios with goals and awards, alongside sandbox mode (a main menu to choose).
- Research that unlocks rides over time.
- Weather and a day/night cycle, with lanterns and fireflies at night.
- Buying land and construction rights.
- Crowds past 700: guests share per-ride route maps instead of each searching paths themselves.

## Done: M8, custom coasters
- **A construction window** for each coaster: piece buttons in groups (straight, turns, brakes; gentle and
  steep slopes; banked turns, lift hill, station; undo and TEST RUN), each with its key (never WASD); a live
  ghost of the next piece at the end of the track, green where it fits and red where it doesn't; the
  piece's price and the heights it runs between; buttons that won't fit turn brown; how far the track's end
  is from its station. A new station opens it; the ride window's BUILD button reopens it.
- **New pieces:** brakes, banked turns and steep slopes (two levels a tile), with their own art and
  physics. Each piece has its own price; taking one off gives half back.
- **Coasters anywhere:** up to 8 per park, each with its own track, trains and station. Three types, each
  with its own speed, track colours and cars: the Wyrm (wooden), the Dwarven Minecart (slower, tamer) and
  the Griffin Flyer (fastest, its cars hanging below the rails). Trains (up to one in every third block)
  and lift speed are set in the construction window. Cars per train stay at three.
- **Testing, as in RCT2:** a coaster opens only after a test run. An empty train laps the track while the
  ride stays shut to guests; a pass fills the ride window with top speed, length, height, drops, air time
  and G-forces, and sets the ratings; a failure names the piece the train couldn't climb and puts a red
  sign over it. Any edit or setting change needs a new test. No crashes: a failed test just reports.
- **Follow cam:** FOLLOW in ride, guest and staff windows; any camera key lets go.
- **Laws:** coaster_on_circuit covers every coaster, no_collisions takes the coaster's settings, and the
  new open_only_tested is proven (sixteen laws).
- Frame time and simulation cost measured against M7: within noise (about 1.4 ms a tick at 200 guests;
  16 ms a frame).

## Done: M9, fixes, polish and the deferred items
Decisions from the owner (2026-09-24): bridges are my call (walkways for guests over paths and track);
1 to 20 cars per train, never more than the track allows; steep pieces only in the two headings that face
the camera; a coaster can be demolished, and removing track re-runs the check and closes the ride if it no
longer passes; saved track designs; coaster sounds by type; no coaster limit.

- **Spike 1, quick fixes.** Toolbar clicks (tool codes 30+ were read as tab clicks). The hover line (its box
  was drawn over its text), extended to coasters, shops and staff. Rain falling down, with a slight slant.
  Dynamic resolution drops only below about 22 fps for 2 s and returns when half resolution holds 45+ fps
  for 5 s. Speeds: pause, 1/4, 1/2 (default), 1x (the old normal), 2x, 3x. A KEYS window from Options
  listing every control. needs_bounded extended to the bladder (LAWS.bend, at the owner's request).
- **Spike 2, picking, following, stairs.** Inspect picks what is drawn under the cursor, front-most first
  (guest, staff, ride or track, scenery), computed only on a click. The follow cam follows one train by
  its id instead of "the first train in the rotating block list". Guests on stairs are drawn at a height
  blended across the tile, so they walk up; picking and the follow cam use the same height.
- **Spike 3, coasters without limits, steep headings, demolition.** No cap on coasters: types looked up
  per coaster instead of packed two bits each, draw flags moved above bit 16, rider tables sized per park
  (64 slots a coaster). Steep up only heading toward the camera (-u, -v), steep down only heading away
  from it (+u, +v), so every steep piece faces the camera; the window says why a steep button is brown.
  The demolish tool on a coaster tile removes that piece and every piece after it (a red ghost shows
  which, half the price back); DEMOLISH COASTER in the ride window removes the whole coaster and its
  station. Any track change closes the ride and re-runs the check at once: if the circuit is closed and
  the dry run passes, a test lap starts by itself; if not, the ride stays off and the windows say why.
  open_only_tested and coaster_on_circuit keep holding (a cut closes the track, like an edit).
- **Spike 4, cars and sounds.** More detailed cars: the Wyrm's lead car a carved dragon head, scales and a
  spine ridge, seat backs, wheeled bogies; the Minecart's planks, iron bands, rivets and a lead-car lantern
  that glows at night; the Flyer's bogie on the rail, wing fins and shoulder restraints. Checked on the
  --cars sheet in four headings. Sounds by type, synthesized like the rest: timber clatter for the Wyrm,
  an iron rattle for the Minecart, a rushing whoosh for the Flyer, and screams on drops scaled by the
  test's biggest drop.
- **Spike 5, saved track designs.** SAVE DESIGN in the construction window writes the track and its
  settings to a numbered slot (designs/1..8, shown with their type, length and ratings); the thrill tab's
  design tool places one as a whole ghost, green where every tile fits, then it needs its own test.
- **Spike 6, bridges.** A tile may carry a raised walkway deck (height, path or queue) over the path or
  track below it: at least 2 levels over paths, 3 over track so trains pass under. Guests treat deck and
  ground as separate layers joined only by stairs at a bridge's ends; decks stand on corner posts. The
  save format changes (old saves won't load); the save proof gains the field.
- **Spike 7, 1 to 20 cars per train.** Set in the construction window; two seats a car, so up to 40 a
  train. The limit: the station must hold the whole train, and blocks grow to at least a train's length
  so a train's tail never reaches into the block behind. Boarding: seat numbers become train * 64 + seat
  and a train's seats span two mask words; capacity_respected and seats_unique take each coaster's seat
  count as a parameter (a mechanical law update, stated in LAWS.bend). The riskiest step, so it goes last.
- **Close:** docs, roadmap page, memory, a report.

## Done: M10, a native Windows build (v1.1.0)
v1.0.0 shipped as a Linux binary that Windows 11 could run through WSL2. M10 made a native Windows `.exe`
(details in [win/README.md](win/README.md)).

- **Own window effects.** Base's `Window.open` and `Window.close` have no Windows version, so the game now
  has `Win.open` and `Win.close` beside `Win.frame` and `Win.config`, all in `win_frame.c`. There, the fill,
  pacing and event plumbing are shared, and only open, close, pixels, resize, pump and present differ
  between X11 and Win32.
- **The Win32 window.** It runs on its own thread, which pumps its messages. Frames are blitted with GDI
  (`SetDIBitsToDevice`; the game already scales into the buffer). Keys and mouse events map to the same
  codes as X11: the wheel as buttons 5 and 6, and Alt without opening the window menu. The window is
  DPI-aware, so pixels stay crisp, and it has an icon drawn by `tools/genicon.py`.
- **Sound (`snd.c`).** The same ring, pumped to waveOut in eight blocks of 256 frames.
- **Bend's runtime on Windows (`win/winplat.c`, `win/compat/`).** A force-included header renames the POSIX
  calls to Win32 versions. `mmap` reservations become `VirtualAlloc(MEM_RESERVE)`, with pages committed
  on first touch by a vectored exception handler. The loop's wake pipe and `select` become a CRT pipe plus
  an event. Timers are high-resolution, and files open in binary mode.
- **Checked.** Headless: the Windows console build's `--scen`, `--uitest`, `--coastertest`, `--bridgetest`
  and `--savetest` output, a `--shot` frame and a `--wav` recording are byte-identical to Linux's. `--bench`:
  full frames in about 10 ms on both. Live: 60 fps with 300 extra guests (fill 2.7 ms of each 16.7 ms
  frame). Noah confirmed the sound, and saving, loading and closing work from the unpacked zip.

## Laws
Proven: money_conserved, headcount_conserved, needs_bounded, coaster_on_circuit, no_collisions,
save_load_roundtrip, capacity_respected, riders_conserved.
Proven in M4: board_only_when_loading, ride_until_unloading, seats_unique, purchase_is_transfer,
prices_bounded (thirteen in all).
Proven in M5: litter_accounted, wages_booked (fifteen in all).
Extended in M8: coaster_on_circuit now covers every coaster in the park (no_collisions was already stated
for any track, so it covers them all, and now takes the coaster's settings too). Proven in M8:
open_only_tested (sixteen in all).
Changed in M9: needs_bounded covers the bladder; capacity_respected reads a coaster's seats from its station
word (its helpers take the station).
Proof maintenance rule: keep the code field-wise (each park field updated by its own function) so
existing proofs survive new features.

## GPU setup (run these in the WSL Ubuntu terminal)
```bash
curl -fsSL https://apt.llvm.org/llvm.sh | sudo bash -s 19
wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb && sudo apt-get update
sudo apt-get install -y cuda-toolkit-12-6
sudo apt-get install -y linux-tools-generic   # optional: perf, for profiling
```
Bend finds `clang-19` on the PATH by itself and CUDA at `/usr/local/cuda`.
