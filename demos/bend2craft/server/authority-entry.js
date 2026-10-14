// Bundle entry for the multiplayer authority: the compiled Bend room contract
// and the server's world simulation (which runs Bend's entity, fluid, fire,
// crop and villager rules), built to dist/multiplayer-authority.js so the Node
// server and the Cloudflare Worker can load them without the Bend toolchain.
import { Multiplayer } from "../web/bend-modules.js";

export { createServerWorld } from "./server-world.js";
export default Multiplayer;
