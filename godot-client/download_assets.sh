#!/bin/bash
# ============================================================================
# Abyssal Descent - Free Asset Downloader
# Downloads CC0/CC-BY assets from Kenney, KayKit, Quaternius, OpenGameArt
# ============================================================================

set -e

ASSETS_DIR="$(cd "$(dirname "$0")" && pwd)/assets"

echo "============================================"
echo " Abyssal Descent - Asset Downloader"
echo " Target: $ASSETS_DIR"
echo "============================================"
echo ""

mkdir -p "$ASSETS_DIR"/{models/{dungeon,characters/{player,npcs,monsters},items/{weapons,armor,consumables},props},textures/{dungeon,ui},icons/{items,emotions,ui},audio/{bgm,sfx},particles}

# ── Kenney Assets (CC0) ────────────────────────────────────────────────────

echo "[1/8] Downloading Kenney Modular Dungeon Kit..."
curl -sL "https://kenney.nl/media/pages/assets/modular-dungeon-kit/ff06f7dc4e-1718895498/kenney_modular-dungeon-kit.zip" -o /tmp/kenney_dungeon.zip 2>/dev/null && \
  unzip -qo /tmp/kenney_dungeon.zip -d "$ASSETS_DIR/models/dungeon/_kenney_dungeon" 2>/dev/null && \
  echo "  OK" || echo "  SKIP (download manually from https://kenney.nl/assets/modular-dungeon-kit)"

echo "[2/8] Downloading Kenney Impact Sounds..."
curl -sL "https://kenney.nl/media/pages/assets/impact-sounds/b4a7ba7d36-1697036063/kenney_impact-sounds.zip" -o /tmp/kenney_impact.zip 2>/dev/null && \
  unzip -qo /tmp/kenney_impact.zip -d "$ASSETS_DIR/audio/sfx/_kenney_impact" 2>/dev/null && \
  echo "  OK" || echo "  SKIP (download manually from https://kenney.nl/assets/impact-sounds)"

echo "[3/8] Downloading Kenney RPG Audio..."
curl -sL "https://kenney.nl/media/pages/assets/rpg-audio/86e28a3d07-1697036070/kenney_rpg-audio.zip" -o /tmp/kenney_rpg_audio.zip 2>/dev/null && \
  unzip -qo /tmp/kenney_rpg_audio.zip -d "$ASSETS_DIR/audio/sfx/_kenney_rpg" 2>/dev/null && \
  echo "  OK" || echo "  SKIP (download manually from https://kenney.nl/assets/rpg-audio)"

echo "[4/8] Downloading Kenney Particle Pack..."
curl -sL "https://kenney.nl/media/pages/assets/particle-pack/2736133be1-1697036067/kenney_particle-pack.zip" -o /tmp/kenney_particles.zip 2>/dev/null && \
  unzip -qo /tmp/kenney_particles.zip -d "$ASSETS_DIR/particles/_kenney" 2>/dev/null && \
  echo "  OK" || echo "  SKIP (download manually from https://kenney.nl/assets/particle-pack)"

echo "[5/8] Downloading Kenney UI Pack RPG..."
curl -sL "https://kenney.nl/media/pages/assets/ui-pack-rpg-expansion/04ff23ba93-1718895534/kenney_ui-pack-rpg-expansion.zip" -o /tmp/kenney_ui.zip 2>/dev/null && \
  unzip -qo /tmp/kenney_ui.zip -d "$ASSETS_DIR/textures/ui/_kenney" 2>/dev/null && \
  echo "  OK" || echo "  SKIP (download manually from https://kenney.nl/assets/ui-pack-rpg-expansion)"

# ── Manual Download Required ───────────────────────────────────────────────

echo ""
echo "[6/8] Manual downloads required (itch.io / Quaternius):"
echo ""
echo "  KayKit Dungeon Remastered (CC0, 200+ dungeon models):"
echo "    https://kaylousberg.itch.io/kaykit-dungeon-remastered"
echo "    -> Extract to: $ASSETS_DIR/models/dungeon/_kaykit/"
echo ""
echo "  KayKit Adventurers (CC0, 5 characters + animations):"
echo "    https://kaylousberg.itch.io/kaykit-adventurers"
echo "    -> Extract to: $ASSETS_DIR/models/characters/player/"
echo ""
echo "  KayKit Skeletons (CC0, 4 skeleton models):"
echo "    https://kaylousberg.itch.io/kaykit-skeletons"
echo "    -> Extract to: $ASSETS_DIR/models/characters/monsters/"
echo ""
echo "  KayKit Fantasy Weapons (CC0, 25+ weapons):"
echo "    https://kaylousberg.itch.io/fantasy-weapons-bits"
echo "    -> Extract to: $ASSETS_DIR/models/items/weapons/"
echo ""
echo "  Quaternius Ultimate Monsters (CC0, 50 animated monsters):"
echo "    https://quaternius.com/packs/ultimatemonsters.html"
echo "    -> Extract to: $ASSETS_DIR/models/characters/monsters/_quaternius/"
echo ""
echo "  Quaternius Ultimate RPG Pack (CC0, 100+ items):"
echo "    https://quaternius.com/packs/ultimaterpg.html"
echo "    -> Extract to: $ASSETS_DIR/models/items/"

# ── OpenGameArt Downloads ──────────────────────────────────────────────────

echo ""
echo "[7/8] OpenGameArt assets (download from browser):"
echo ""
echo "  RPG Sound Pack (CC0, 95 sounds):"
echo "    https://opengameart.org/content/rpg-sound-pack"
echo "    -> Extract to: $ASSETS_DIR/audio/sfx/_rpg_pack/"
echo ""
echo "  Dungeon Ambience BGM (CC0):"
echo "    https://opengameart.org/content/dungeon-ambience"
echo "    -> Save to: $ASSETS_DIR/audio/bgm/dungeon.ogg"
echo ""
echo "  RPG Battle Theme BGM (CC-BY 4.0):"
echo "    https://opengameart.org/content/rpg-battle-theme-0"
echo "    -> Save to: $ASSETS_DIR/audio/bgm/combat.ogg"
echo ""
echo "  Final Boss Lair BGM (CC-BY 3.0):"
echo "    https://opengameart.org/content/finalbosslair"
echo "    -> Save to: $ASSETS_DIR/audio/bgm/boss.ogg"
echo ""
echo "  4 Ghostly Loops BGM (CC0):"
echo "    https://opengameart.org/content/4-atmospheric-ghostly-loops"
echo "    -> Save to: $ASSETS_DIR/audio/bgm/menu.ogg"
echo ""
echo "  Fantasy Icon Pack by Ravenmore (CC-BY 3.0):"
echo "    https://opengameart.org/content/fantasy-icon-pack-by-ravenmore"
echo "    -> Extract to: $ASSETS_DIR/icons/items/"
echo ""
echo "  Dark Fantasy UI Pack (CC-BY 4.0):"
echo "    https://opengameart.org/content/dark-fantasy-ui-pack-health-bars-inventory-containers-buttons"
echo "    -> Extract to: $ASSETS_DIR/textures/ui/_dark_fantasy/"
echo ""
echo "  Animated Particle Effects (CC0):"
echo "    https://opengameart.org/content/animated-particle-effects-1"
echo "    -> Extract to: $ASSETS_DIR/particles/_animated/"

echo ""
echo "[8/8] Creating CREDITS.txt..."

cat > "$ASSETS_DIR/CREDITS.txt" << 'CREDITS'
# Abyssal Descent - Asset Credits
# ================================

## CC0 (No attribution required, but credit given)
- Kenney (kenney.nl) - Modular Dungeon Kit, Impact Sounds, RPG Audio, Particle Pack, UI Pack RPG
- KayKit / Kay Lousberg (kaylousberg.itch.io) - Dungeon Remastered, Adventurers, Skeletons, Fantasy Weapons, Halloween Bits
- Quaternius (quaternius.com) - Ultimate Monsters, Ultimate RPG Pack, Modular Characters
- OpenGameArt contributors - Dungeon Ambience, RPG Sound Pack, 4 Ghostly Loops

## CC-BY 3.0 (Attribution required)
- Ravenmore (OpenGameArt) - Fantasy Icon Pack
- Marllon Silva (OpenGameArt) - Final Boss Lair BGM

## CC-BY 4.0 (Attribution required)
- OpenGameArt contributors - Dark Fantasy UI Pack, RPG Battle Theme

## CC-BY-SA 3.0 (Attribution + ShareAlike)
- Bart K. (OpenGameArt) - Spell Sounds Starter Pack
CREDITS

echo "  CREDITS.txt created."
echo ""
echo "============================================"
echo " Done! Check the output above for any"
echo " assets that need manual download."
echo "============================================"
