HOW TO ADD A GAME
=================

Each game needs two things in Assets/psx/PSXPort.PSX/ on the SD card:

  1. <Game>.json     the entry you pick in the Pocket menu (this folder's Example.json is one)
  2. <Game>/         a folder with the game's .bin files (this folder is Example/)

Example.json says: look in "Example/" for "Example (Track 1).bin" (data slot 16) and
"Example (Track 2).bin" (data slot 17). Track N = data slot 15+N.

Easiest way: let the tools write the JSON from the game's .cue
-------------------------------------------------------------
The game must be Redump style: one .bin per track plus a .cue.

  python3 pocket/tools/cue2instance.py "games/MyGame/MyGame.cue" "MyGame.json"

or build a complete card (BIOS + game, for yourself, don't share it):

  tools/release.sh --bios SCPH1001.BIN --game "games/MyGame/MyGame.cue" --copy-bins

By hand
-------
  1. Copy Example.json to "MyGame.json".
  2. Set "data_path" to your folder name with a trailing slash, e.g. "MyGame/".
  3. Make one data_slots entry per track: id 16 for track 1, 17 for track 2, ... (up to 24 tracks),
     "filename" exactly as the .bin is named.
  4. Put the .bin files in Assets/psx/PSXPort.PSX/MyGame/.

Also needed
-----------
  - The BIOS as Assets/psx/common/scph1001.bin (512 KB, not included).
  - Audio CD (BIOS CD player): use id 15 instead of 16 for track 1 and the BIOS shows its CD player.

You can delete Example.json and the Example folder once you have your own games.
