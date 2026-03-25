# Asset Guide - Abyssal Descent

## 다운로드 링크 (모두 무료)

### 3D 환경 (던전)
| 에셋 | URL | 라이선스 | 용도 |
|------|-----|---------|------|
| KayKit Dungeon Remastered | https://kaylousberg.itch.io/kaykit-dungeon-remastered | CC0 | 벽, 바닥, 문, 계단, 함정, 소품 |
| Kenney Modular Dungeon | https://kenney.nl/assets/modular-dungeon-kit | CC0 | 추가 던전 모듈 |
| Kenney Graveyard Kit | https://kenney.nl/assets/graveyard-kit | CC0 | 묘지/지하묘지 테마 |
| KayKit Halloween Bits | https://kaylousberg.itch.io/halloween-bits | CC0 | 어둠 장식 (해골, 묘비) |

### 3D 캐릭터
| 에셋 | URL | 라이선스 | 용도 |
|------|-----|---------|------|
| KayKit Adventurers | https://kaylousberg.itch.io/kaykit-adventurers | CC0 | 플레이어, 기사 NPC, 모험자 NPC |
| KayKit Skeletons | https://kaylousberg.itch.io/kaykit-skeletons | CC0 | 해골 전사 몬스터 |
| Quaternius Ultimate Monsters | https://quaternius.com/packs/ultimatemonsters.html | CC0 | 슬라임, 골렘, 유령, 악마 등 50종 |
| Quaternius Modular Characters | https://quaternius.com/packs/ultimatemodularcharacters.html | CC0 | NPC (상인, 현자) |

### 3D 아이템/무기
| 에셋 | URL | 라이선스 | 용도 |
|------|-----|---------|------|
| KayKit Fantasy Weapons | https://kaylousberg.itch.io/fantasy-weapons-bits | CC0 | 검, 도끼, 방패, 지팡이 |
| Quaternius Ultimate RPG | https://quaternius.com/packs/ultimaterpg.html | CC0 | 포션, 보석, 갑옷 등 100종 |

### 2D UI/아이콘
| 에셋 | URL | 라이선스 | 용도 |
|------|-----|---------|------|
| Ravenmore Fantasy Icons | https://opengameart.org/content/fantasy-icon-pack-by-ravenmore | CC-BY 3.0 | 아이템 아이콘 |
| Dark Fantasy UI Pack | https://opengameart.org/content/dark-fantasy-ui-pack-health-bars-inventory-containers-buttons | CC-BY 4.0 | HP바, 인벤토리, 버튼 |
| Kenney UI Pack RPG | https://kenney.nl/assets/ui-pack-rpg-expansion | CC0 | UI 프레임, 패널 |

### 오디오 BGM
| 에셋 | URL | 라이선스 | 용도 |
|------|-----|---------|------|
| Dungeon Ambience | https://opengameart.org/content/dungeon-ambience | CC0 | 던전 탐험 BGM |
| RPG Battle Theme | https://opengameart.org/content/rpg-battle-theme-0 | CC-BY 4.0 | 전투 BGM |
| Final Boss Lair | https://opengameart.org/content/finalbosslair | CC-BY 3.0 | 보스전 BGM |
| 4 Ghostly Loops | https://opengameart.org/content/4-atmospheric-ghostly-loops | CC0 | 메뉴/어둠 구역 |

### 오디오 SFX
| 에셋 | URL | 라이선스 | 용도 |
|------|-----|---------|------|
| RPG Sound Pack | https://opengameart.org/content/rpg-sound-pack | CC0 | 전투/몬스터/UI/아이템 (95종) |
| Sword Sound Effects | https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes | CC0 | 검 타격/방어 |
| Spell Sounds | https://opengameart.org/content/spell-sounds-starter-pack | CC-BY-SA 3.0 | 마법 효과 (70종) |
| Kenney Impact Sounds | https://kenney.nl/assets/impact-sounds | CC0 | 타격/충돌 (130종) |
| Kenney RPG Audio | https://kenney.nl/assets/rpg-audio | CC0 | 발걸음/무기 (50종) |

### 파티클/VFX
| 에셋 | URL | 라이선스 | 용도 |
|------|-----|---------|------|
| Animated Particle Effects | https://opengameart.org/content/animated-particle-effects-1 | CC0 | 불/마법/연기 |
| Kenney Particle Pack | https://kenney.nl/assets/particle-pack | CC0 | 불/얼음/독 파티클 |

## 폴더 구조

```
assets/
├── models/
│   ├── dungeon/          ← 벽, 바닥, 문, 계단
│   ├── characters/
│   │   ├── player/       ← 플레이어 모델
│   │   ├── npcs/         ← NPC 모델
│   │   └── monsters/     ← 몬스터 모델
│   ├── items/
│   │   ├── weapons/      ← 무기 모델
│   │   ├── armor/        ← 갑옷 모델
│   │   └── consumables/  ← 포션/스크롤
│   └── props/            ← 상자, 통, 횃불 등
├── textures/
│   ├── dungeon/          ← 환경 텍스처
│   └── ui/               ← UI 텍스처/프레임
├── icons/
│   ├── items/            ← 아이템 아이콘
│   ├── emotions/         ← NPC 감정 아이콘
│   └── ui/               ← UI 아이콘
├── audio/
│   ├── bgm/              ← 배경음악
│   └── sfx/              ← 효과음
├── particles/            ← 파티클 텍스처
└── ASSETS.md             ← 이 파일
```
