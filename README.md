# 심연의 강림 (Abyssal Descent)

> AI 던전 마스터가 이끄는 3D 로그라이크 던전 크롤러
>
> *A 3D roguelike dungeon crawler powered by an AI Dungeon Master*

![Godot](https://img.shields.io/badge/Godot-4.6.1-478CBF?logo=godotengine&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115-009688?logo=fastapi&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 게임 소개

심연의 깊은 곳에서 고대의 악이 깨어나고 있습니다. 용감한 모험자여, 8개 층의 던전을 탐험하고 각 층의 보스를 처치하여 심연의 비밀을 밝혀내세요.

### 주요 특징

- **8개 고유 테마 던전** — 지하묘지, 심연 회랑, 타락한 성소, 저주받은 광산, 영혼의 감옥, 용암의 심장, 얼어붙은 심연, 심연의 도서관
- **턴제 전투** — 6속성 상성 시스템 (불/얼음/물/번개/성/암흑), 단일 타격 & AoE 스킬
- **로그라이크 루프** — 사망 시 골드를 영구 업그레이드로 전환, 더 강해져서 재도전
- **AI 서버 연동 (선택)** — Claude API로 실시간 던전 생성, NPC 대화, 동적 퀘스트
- **오프라인 플레이 가능** — AI 서버 없이도 풀백 시스템으로 완전한 게임 플레이

### 조작법

| 키 | 동작 |
|---|---|
| `WASD` | 이동 |
| `마우스` | 시점 회전 |
| `E` | 상호작용 / 전투 시작 |
| `I` | 인벤토리 |
| `Tab` | 퀘스트 로그 |
| `Esc` | 일시정지 |

### 전투 시스템

- **속성 상성**: 약점 1.5배 / 저항 0.5배 데미지
- **스킬**: 레벨업으로 해금되는 속성 스킬 (단일 타격 + AoE)
- **장비**: 무기/갑옷/악세서리 자동 장착, 등급별 드롭률
- **영구 강화**: 사망 시 획득 골드로 공격/방어/체력 영구 업그레이드

---

## 실행 방법

### 게임 클라이언트 (Godot)

1. [Godot 4.6.1](https://godotengine.org/download) 설치
2. `godot-client/project.godot`을 Godot 에디터로 열기
3. F5로 실행

### AI 서버 (선택사항)

AI 서버 없이도 게임은 완전히 플레이 가능합니다. AI 서버를 연결하면 동적 던전 생성과 NPC 대화가 활성화됩니다.

```bash
cd abyssal-ai-server
pip install -r requirements.txt
# .env 파일에 ANTHROPIC_API_KEY 설정
uvicorn main:app --reload
```

---

## 아키텍처

```
┌─────────────────────────────┐         ┌──────────────────────────────────┐
│      Godot 4.6 Client       │         │      FastAPI AI Server           │
│                             │         │        (선택사항)                  │
│  ┌───────────────┐          │  HTTP   │  ┌────────────────────────────┐  │
│  │ DungeonBuilder│──────────┼────────►│  │  던전 생성 / NPC 대화       │  │
│  │ CombatSystem  │          │  WS     │  │  퀘스트 트리거 / 난이도     │  │
│  │ QuestManager  │◄─────────┼────────►│  │  프롬프트 보안              │  │
│  └───────────────┘          │         │  └────────────────────────────┘  │
│  ┌──────────────┐           │         │                                  │
│  │ AIFallback   │           │         │  오프라인 시 AIFallback.gd가     │
│  │ (오프라인용)  │           │         │  8개 던전 템플릿 제공            │
│  └──────────────┘           │         │                                  │
└─────────────────────────────┘         └──────────────────────────────────┘
```

---

## 프로젝트 구조

```
AbyssalDescent/
├── godot-client/                    # Godot 4.6 게임 클라이언트
│   ├── scripts/
│   │   ├── ai/                      #   AI 서버 통신 + 오프라인 폴백
│   │   ├── combat/                  #   턴제 전투 시스템
│   │   ├── dungeon/                 #   던전 빌더, 방/몬스터/아이템 스포너
│   │   ├── npc/                     #   NPC 대화 시스템
│   │   ├── systems/                 #   게임매니저, 인벤토리, 난이도, 사운드
│   │   ├── player/                  #   플레이어 컨트롤러
│   │   └── ui/                      #   HUD, 전투UI, 상점, 미니맵 등
│   └── assets/                      #   3D 모델, 오디오, 텍스처
│
├── abyssal-ai-server/               # FastAPI AI 백엔드 (선택)
│   ├── routers/                     #   API 엔드포인트
│   ├── services/                    #   던전/NPC/퀘스트 서비스
│   ├── models/                      #   Pydantic 데이터 모델
│   └── tests/                       #   pytest 테스트
│
└── godot-dev-loop.sh                # 멀티 에이전트 개발 루프 (CI)
```

---

## 사용 에셋

| 에셋 | 제작자 | 라이선스 |
|------|--------|----------|
| Ultimate Monsters | Quaternius | CC0 |
| Mini Dungeon | Kenney | CC0 |
| KayKit Dungeon Pack | Kay Lousberg | CC0 |
| KayKit Fantasy Weapons | Kay Lousberg | CC0 |
| KayKit Skeletons | Kay Lousberg | CC0 |
| KayKit Adventurers | Kay Lousberg | CC0 |
| RPG Audio | Kenney | CC0 |
| Impact Sounds | Kenney | CC0 |

---

## 기술 스택

| 카테고리 | 기술 |
|----------|------|
| **게임 엔진** | Godot 4.6.1 (GDScript, Forward+ Renderer) |
| **백엔드** | Python 3.12, FastAPI 0.115, Pydantic 2.10 |
| **실시간 통신** | WebSocket (NPC 대화 스트리밍) |
| **인프라** | Docker Compose (Redis + PostgreSQL + ChromaDB) |
| **테스트** | pytest (서버), godot-dev-loop.sh (클라이언트) |

---

## 라이선스

MIT
