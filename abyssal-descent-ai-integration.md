# 🎮 Abyssal Descent — AI 던전 마스터 통합 기획서

> 기존 3D 로그라이크 던전 크롤러 + NPC Dialogue Engine + Content Pipeline 통합
> Godot 4 (클라이언트) + FastAPI (AI 서버) · 바이브코딩 프로젝트

---

## 프로젝트 개요

| 항목 | 내용 |
|------|------|
| 목표 | 기존 Abyssal Descent에 AI 시스템을 실제 통합 |
| 핵심 가치 | "AI를 만들 줄 안다" → "AI를 게임에 넣을 줄 안다" |
| 통합 대상 | NPC Dialogue Engine + Game Content Pipeline |
| 아키텍처 | Godot 4 클라이언트 ↔ FastAPI AI 서버 (HTTP/WebSocket) |
| 예상 기간 | 4~6주 (기존 프로젝트 위에 빌드) |
| 포트폴리오 임팩트 | ★★★★★ (3개 프로젝트를 1개로 통합 → 시스템 설계 능력 증명) |

---

## 아키텍처: 서버-클라이언트 분리 구조

```
┌────────────────────────────────────┐
│  Godot 4 Client (Abyssal Descent)  │
│                                    │
│  ┌──────────┐  ┌────────────────┐  │
│  │ 플레이어  │  │  AI Client     │  │
│  │ 컨트롤러 │  │  (GDScript)    │  │
│  └──────────┘  │                │  │
│                │ - HTTP 요청    │  │
│  ┌──────────┐  │ - WebSocket    │  │
│  │ 던전     │  │ - JSON 파싱   │  │
│  │ 렌더러   │  │ - 응답 캐싱   │  │
│  └──────────┘  └───────┬────────┘  │
└────────────────────────┼───────────┘
                         │ HTTP / WebSocket
                         ▼
┌────────────────────────────────────┐
│  FastAPI AI Server                 │
│                                    │
│  ┌──────────────┐ ┌─────────────┐  │
│  │ Content      │ │ NPC         │  │
│  │ Pipeline     │ │ Dialogue    │  │
│  │              │ │ Engine      │  │
│  │ - 던전 생성  │ │ - RAG 대화  │  │
│  │ - 몬스터     │ │ - 감정 상태 │  │
│  │ - 아이템     │ │ - 힌트 시스템│ │
│  │ - 퀘스트     │ │ - 호감도    │  │
│  └──────────────┘ └─────────────┘  │
│                                    │
│  ┌──────────────────────────────┐  │
│  │ 공유 인프라                   │  │
│  │ Redis (캐시) + PostgreSQL    │  │
│  │ + ChromaDB (RAG)             │  │
│  └──────────────────────────────┘  │
└────────────────────────────────────┘
```

### 핵심 포인트: 왜 폴더에 합치지 않는가

1. **언어가 다름**: Godot = GDScript, AI 서버 = Python
2. **독립 배포 가능**: 서버만 교체하거나 다른 게임에 붙일 수 있음
3. **바이브코딩 효율**: 각 프로젝트를 별도 창에서 병렬 작업 가능
4. **포트폴리오**: "마이크로서비스 설계 경험" 으로 어필 가능

### 로컬 개발 환경

```
~/Projects/
├── abyssal-descent/          ← Godot 클라이언트 (기존)
│   └── scripts/ai/           ← 새로 추가: AI 서버 통신 모듈
├── NpcDialogueEngine/        ← 기존 레포 그대로
├── game-content-pipeline/    ← 기존 레포 그대로
└── abyssal-ai-server/        ← 새로 만들 통합 서버
    ├── main.py               ← FastAPI 진입점
    ├── routers/
    │   ├── dungeon.py        ← 던전 생성 API
    │   ├── npc.py            ← NPC 대화 API
    │   └── content.py        ← 콘텐츠 생성 API
    ├── services/              ← 기존 레포에서 import
    └── docker-compose.yml
```

---

## Phase 1: AI 서버 통합 + Godot HTTP 클라이언트 (1~2주)

### 목표
기존 NPC Dialogue Engine과 Content Pipeline을 하나의 FastAPI 서버로 통합하고, Godot에서 호출할 수 있는 기반 구축

### 구현 항목

**AI 통합 서버 (abyssal-ai-server)**
- FastAPI 앱: 기존 두 레포를 서비스 레이어로 import
- 엔드포인트 설계:
  - `POST /api/dungeon/generate` — 던전 층 생성
  - `POST /api/npc/chat` — NPC 대화
  - `GET /api/npc/{npc_id}/state` — NPC 감정/호감도 상태
  - `POST /api/content/item` — 아이템 생성
  - `POST /api/content/quest` — 퀘스트 생성
- Docker Compose: FastAPI + Redis + PostgreSQL + ChromaDB

**Godot AI 클라이언트 모듈**
- `scripts/ai/ai_client.gd` — HTTPRequest 래퍼 (싱글톤 오토로드)
- `scripts/ai/ai_config.gd` — 서버 URL, 타임아웃 설정
- `scripts/ai/ai_cache.gd` — 로컬 캐싱 (서버 응답을 JSON 파일로 저장)

### ai_client.gd 핵심 설계
```
오토로드 싱글톤

func generate_dungeon(floor_num: int, difficulty: float) -> Dictionary:
    # POST /api/dungeon/generate
    # 반환: {rooms: [...], monsters: [...], items: [...], boss: {...}}

func chat_with_npc(npc_id: String, player_message: String) -> Dictionary:
    # POST /api/npc/chat
    # 반환: {response: "...", emotion: "happy", affinity_change: +5}

func generate_quest(context: Dictionary) -> Dictionary:
    # POST /api/content/quest
    # 반환: {title: "...", objectives: [...], rewards: [...]}

시그널:
- dungeon_generated(data: Dictionary)
- npc_response_received(data: Dictionary)
- quest_generated(data: Dictionary)
- ai_error(endpoint: String, error: String)
```

### API 요청/응답 예시

```json
// POST /api/dungeon/generate
// Request
{
  "floor_number": 3,
  "difficulty": 0.6,
  "player_level": 5,
  "player_inventory": ["iron_sword", "health_potion_x3"],
  "visited_room_types": ["combat", "combat", "treasure"],
  "seed": 12345
}

// Response
{
  "floor_name": "잊혀진 성소",
  "floor_description": "고대 사제들이 봉인한 어둠의 신전...",
  "rooms": [
    {
      "id": "room_01",
      "type": "combat",
      "shape": "rectangular",
      "size": [8, 6],
      "connections": ["room_02", "room_03"],
      "monsters": [
        {"type": "shadow_acolyte", "level": 4, "count": 3, "positions": [[2,1],[5,3],[6,5]]}
      ],
      "items": [
        {"type": "dark_crystal", "position": [4, 3], "rarity": "uncommon"}
      ],
      "environmental": "dim_light"
    },
    {
      "id": "room_02",
      "type": "npc_encounter",
      "npc_id": "wandering_merchant",
      "dialogue_context": "merchant_floor3_first_meet"
    }
  ],
  "boss": {
    "name": "타락한 사제장",
    "type": "corrupted_priest",
    "level": 7,
    "phases": 2,
    "special_mechanics": ["summon_adds", "area_denial"]
  }
}
```

### 마일스톤
> Godot에서 버튼 하나 누르면 AI 서버가 던전 데이터를 생성하고, 콘솔에 JSON으로 출력

---

## Phase 2: AI 던전 생성 + 실시간 NPC 대화 (2~3주)

### 목표
AI가 생성한 던전을 실제 3D로 렌더링하고, NPC와 실시간 대화 가능

### 구현 항목

**AI 던전 렌더러**
- `scripts/dungeon/ai_dungeon_builder.gd`
  - AI 서버 응답(JSON) → Godot 씬 노드로 변환
  - 방 타입별 프리팹 매핑: combat → 전투방.tscn, treasure → 보물방.tscn
  - 방 연결: 복도 자동 생성 (A* 또는 단순 직선)
  - 몬스터/아이템 스폰 위치 적용
- 폴백 시스템: AI 서버 다운 시 사전 정의된 JSON 사용

**NPC 대화 UI + 연동**
- `scenes/ui/npc_dialogue.tscn` — 대화 UI
  - 텍스트 입력 (LineEdit) + 응답 표시 (RichTextLabel)
  - NPC 감정 상태 아이콘 (7종: 기쁨, 슬픔, 분노, 두려움, 놀람, 혐오, 중립)
  - 호감도 게이지 바
  - 스트리밍 텍스트 효과 (글자 하나씩 출력)
- `scripts/npc/ai_npc.gd` — NPC 행동 + AI 연동
  - 플레이어 접근 시 대화 UI 활성화
  - 대화 내용은 WebSocket으로 실시간 스트리밍
  - NPC 종류: 방랑 상인, 포로가 된 모험가, 수수께끼의 현자, 타락한 기사

**NPC 세계관 데이터 (RAG용)**
```json
{
  "wandering_merchant": {
    "name": "리라",
    "persona": "심연에서 장사하는 대담한 상인. 쾌활하지만 과거에 어두운 비밀이 있다.",
    "knowledge": ["아이템 가격", "던전 각 층의 소문", "보스 약점 힌트"],
    "personality_traits": ["유머러스", "탐욕적", "의외로 다정"],
    "speech_style": "반말, 은어 섞어 사용, '~지' 어미 자주 사용",
    "hint_level_by_affinity": {
      "0-20": "모호한 암시만",
      "21-50": "방향성 있는 힌트",
      "51-80": "구체적 정보",
      "81-100": "보스 약점까지 공유"
    }
  }
}
```

### 대화 흐름

```
플레이어 → "이 층에 보스가 있어?"
    │
    ▼ WebSocket → AI 서버
    │
    ├─ 1. 보안 필터 (프롬프트 인젝션 차단)
    ├─ 2. 의도 분류 (hint_request)
    ├─ 3. RAG 검색 (던전 3층 보스 관련 문서)
    ├─ 4. 호감도 확인 (35 → "방향성 힌트" 레벨)
    ├─ 5. 감정 엔진 (현재: 중립 → 약간 긴장)
    ├─ 6. 응답 생성
    └─ 7. 검증 (스포일러 레벨 체크)
    │
    ▼ WebSocket ← AI 서버
    │
NPC 리라 → "보스? 흠... 이 층 깊숙한 곳에서
            뭔가 으스스한 기운이 느껴지긴 하지.
            빛을 싫어하는 놈이라는 소문은 들었어.
            근데 더 알고 싶으면... 좋은 물건 좀 가져와봐~"
            [감정: 약간 긴장] [호감도: 35 → 37 (+2)]
```

### 마일스톤
> AI가 생성한 던전에서 돌아다니며, NPC와 실시간 대화로 보스 약점 힌트를 얻음

---

## Phase 3: 적응형 난이도 + 동적 퀘스트 (1~2주)

### 목표
플레이어 행동 패턴을 분석해서 난이도를 조절하고, 상황에 맞는 퀘스트를 AI가 생성

### 구현 항목

**플레이어 행동 추적 시스템**
- `scripts/systems/player_tracker.gd`
  - 추적 데이터: 전투 승률, 평균 클리어 시간, 회피 패턴, 사용 무기, 사망 원인
  - 매 층 클리어 시 AI 서버에 데이터 전송
  - 로컬 캐싱 (오프라인 시에도 데이터 축적)

**적응형 난이도 엔진 (AI 서버)**
- `POST /api/dungeon/adapt`
- 입력: 플레이어 행동 히스토리
- 출력: 다음 층 난이도 파라미터

```json
// 난이도 조절 파라미터
{
  "monster_count_modifier": 1.2,    // 몬스터 수 20% 증가 (잘하는 플레이어)
  "monster_level_offset": +1,       // 레벨 +1
  "item_drop_rate_modifier": 0.8,   // 아이템 드롭 약간 감소
  "room_count": 7,                  // 기본 5 → 7개
  "special_event_chance": 0.3,      // 특수 이벤트 확률 증가
  "boss_phase_count": 3,            // 보스 페이즈 추가
  "reasoning": "플레이어가 최근 3층을 무피해로 클리어. 도전 강화 추천."
}
```

**동적 퀘스트 시스템**
- AI가 현재 상황을 분석하여 퀘스트 제안
- 트리거 조건:
  - NPC 호감도가 특정 수치 도달
  - 특정 아이템 수집 시
  - 사망 횟수가 많을 때 (구제 퀘스트)
  - 탐험률이 높을 때 (보상 퀘스트)

```json
// POST /api/content/quest
// 상황 기반 퀘스트 생성 요청
{
  "trigger": "npc_affinity_50",
  "npc_id": "wandering_merchant",
  "player_state": {
    "level": 8,
    "current_floor": 5,
    "deaths": 3,
    "inventory_highlights": ["legendary_shield", "dark_crystal_x5"]
  }
}

// 응답
{
  "quest_id": "merchant_secret_01",
  "title": "리라의 잃어버린 화물",
  "description": "리라가 3층 어딘가에 떨어뜨린 특별한 상자를 찾아달라고 한다.",
  "type": "fetch",
  "objectives": [
    {"type": "find_item", "target": "merchant_lost_cargo", "floor": 3, "hint": "동쪽 복도 근처"}
  ],
  "rewards": {
    "gold": 500,
    "items": ["rare_health_elixir"],
    "npc_affinity_bonus": 20,
    "unlock": "merchant_discount_15percent"
  },
  "dialogue_on_accept": "사실 말하기 좀 그런데... 3층에서 중요한 짐을 잃어버렸어. 찾아주면 크게 한턱 쏠게!",
  "dialogue_on_complete": "이거야! 고마워, 진짜! 앞으로 내 물건 15% 할인해줄게. 친구니까~"
}
```

### 마일스톤
> 플레이 실력에 따라 난이도가 자동 조절되고, NPC와의 관계에서 퀘스트가 자연스럽게 발생

---

## Phase 4: 폴리싱 + 포트폴리오 패키징 (1주)

### 구현 항목
- AI 응답 대기 중 로딩 연출 (마법진 회전 등)
- AI 서버 오프라인 시 폴백 데이터로 게임 진행 가능
- README.md: 아키텍처 다이어그램, GIF, 기술 스택 설명
- 게임플레이 영상 (3~5분): AI 던전 생성 + NPC 대화 하이라이트
- Docker Compose one-command 실행: `docker-compose up` 으로 서버+DB 전부 기동
- GitHub: 클라이언트/서버 각각 레포 + 통합 문서

### 포트폴리오 어필 포인트

| 항목 | 기존 분리 상태 | 통합 후 |
|------|---------------|---------|
| 보여줄 수 있는 것 | "AI 서버를 만들었습니다" | "AI가 실제 게임에서 이렇게 동작합니다" (플레이 가능) |
| 면접 시연 | API 문서, Streamlit 대시보드 | 실제 게임 플레이 + 실시간 AI 반응 |
| 기술 깊이 | 개별 시스템 | 클라이언트-서버 아키텍처, 실시간 통신, 폴백 설계 |
| 차별화 | AI 엔지니어 중 다수 보유 | AI + 게임 통합 경험자는 매우 희소 |

---

## 바이브코딩 프롬프트 가이드

### Phase 1 시작 시
```
"abyssal-ai-server 라는 새 FastAPI 프로젝트를 만들어줘.
기존 NPC Dialogue Engine과 Game Content Pipeline의 핵심 로직을
서비스 레이어로 가져와서, /api/dungeon/generate 와 /api/npc/chat
엔드포인트를 만들어. Docker Compose로 Redis, PostgreSQL, ChromaDB도 같이 올려줘."
```

### Phase 1 Godot 클라이언트
```
"Godot 4 GDScript로 AI 서버 통신 모듈을 만들어줘.
HTTPRequest 노드를 래핑하는 싱글톤 오토로드로,
generate_dungeon(floor_num, difficulty) 함수가 POST /api/dungeon/generate를 호출하고
JSON 응답을 파싱해서 시그널로 돌려주는 구조로."
```

### Phase 2 던전 빌더
```
"AI 서버가 반환한 JSON (rooms 배열, 각 room에 type/size/connections/monsters/items)을
Godot 3D 씬으로 변환하는 ai_dungeon_builder.gd를 만들어줘.
방 타입별로 다른 프리팹(tscn)을 인스턴스하고, 복도로 연결해줘."
```

---

*Abyssal Descent AI Integration · Godot 4 + FastAPI + 기존 AI 프로젝트 통합*
