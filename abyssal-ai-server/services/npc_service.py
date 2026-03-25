"""NPC dialogue service — template-based conversation with emotion & affinity tracking.

Each NPC has a distinct personality, knowledge base, speech style, and hint
progression that unlocks as the player builds affinity.
"""

from __future__ import annotations

import logging
import random
import re
from typing import Any

from models.npc import (
    ChatMessage,
    Emotion,
    Hint,
    HintLevel,
    NPCChatRequest,
    NPCChatResponse,
    NPCStateResponse,
    PlayerState,
)
from config import get_settings
from services.llm_service import LLMService
from services.persistence_service import persistence_service
from services.security_service import security_service

logger = logging.getLogger(__name__)

# ---------- NPC world data ----------

NPC_DATA: dict[str, dict[str, Any]] = {
    "wandering_merchant": {
        "name": "리라",
        "title": "떠돌이 상인",
        "persona": (
            "밝고 쾌활한 떠돌이 상인이지만, 어째서 이 위험한 심연에서 장사를 하는지는 "
            "아무도 모른다. 가끔 어둠에 대해 이상하리만치 잘 알고 있다. "
            "사실 그녀는 심연에 삼켜진 상인 길드의 마지막 생존자이며, "
            "심연의 힘을 이용해 시공간을 넘나들 수 있다."
        ),
        "knowledge": [
            "각 층의 상점 위치와 희귀 아이템에 대한 정보",
            "심연의 상인 길드가 몰락한 진실",
            "보스의 약점에 대한 소문",
            "숨겨진 방의 존재",
            "심연의 진정한 목적",
        ],
        "personality_traits": ["cheerful", "cunning", "mysterious", "generous"],
        "speech_style": "활발하고 친근한 말투. 상업적 비유를 자주 사용. 가끔 의미심장한 말을 흘림.",
        "default_emotion": Emotion.HAPPY,
        "hint_level_by_affinity": {
            -100: HintLevel.NONE,
            0: HintLevel.NONE,
            20: HintLevel.VAGUE,
            40: HintLevel.MODERATE,
            60: HintLevel.DETAILED,
            80: HintLevel.COMPLETE,
        },
        "greetings": {
            "low": [
                "흥, 또 왔어? 사려면 사고 아니면 가.",
                "...뭐야, 볼 일 있어?",
            ],
            "neutral": [
                "어서 와! 오늘은 좋은 물건이 들어왔어~",
                "반가워, 모험자! 뭐 필요한 거 있어?",
                "이 심연에서 만나다니, 인연이네! 구경해 볼래?",
            ],
            "high": [
                "왔구나! 너를 기다리고 있었어. 특별히 좋은 거 챙겨뒀지~",
                "내 최고의 단골이잖아! 오늘은 특별 할인이야, 후후.",
                "아, 드디어! 너한테만 보여줄 게 있어. 가까이 와봐.",
            ],
        },
        "dialogue_templates": {
            "greeting": [
                "어서 와~ 오늘도 심연 탐험? 대단하다, 진짜.",
                "반가워! 혹시 이번에도 살아 돌아왔구나? 역시!",
            ],
            "farewell": [
                "조심해! 죽으면 거래 못 하잖아~ 농담이야, 진심이야.",
                "다음에 또 와! 살아서... 꼭 살아서.",
            ],
            "about_dungeon": [
                "이 층은 좀 위험해. 특히 {floor}층의 함정은 조심해야 해.",
                "소문에 의하면 {floor}층 근처에 숨겨진 방이 있대. 뭐, 소문일 뿐이지만~",
            ],
            "about_self": [
                "나? 그냥 떠돌이 상인이야! 이 심연이 내 장터지, 뭐. ...왜 그런 눈으로 봐?",
                "어떻게 여기서 장사하냐고? 후후, 그건 영업 비밀이야~",
            ],
            "hint_vague": [
                "음... {floor}층에서 뭔가 이상한 기운을 느꼈어. 조심해.",
                "그 보스... 불을 싫어한다는 소문이 있어. 진짜인지는 모르겠지만.",
            ],
            "hint_detailed": [
                "들어봐. {floor}층 보스는 왼쪽 뿔이 약점이야. 거기를 노려.",
                "비밀 하나 알려줄게. {floor}층 세 번째 방의 벽을 두드려봐. 감사는 나중에.",
            ],
            "hint_complete": [
                "너니까 말하는 건데... 이 심연 맨 아래에는 '시작'이 있어. 모든 것의 시작. 거기에 도달하면... 아, 여기선 말 못 해.",
                "상인 길드가 왜 망했는지 알아? 우리가 심연의 핵심에 너무 가까이 갔거든. 그 핵심은... 살아있어.",
            ],
            "negative": [
                "짜증나네. 자꾸 그러면 거래 안 해줄 거야.",
                "...그렇게 나오면 나도 생각이 있어.",
            ],
            "player_hurt": [
                "어머, 많이 다쳤네! 포션 싸게 줄까? ...조금만.",
                "그 상태로 돌아다니면 안 돼! 포션 사 가.",
            ],
        },
    },
    "captive_adventurer": {
        "name": "카엘",
        "title": "포로가 된 모험자",
        "persona": (
            "심연의 감옥에 갇힌 모험자. 한때 최강의 파티를 이끌었지만, "
            "5층 보스에게 패배한 후 동료를 잃고 포로가 되었다. "
            "심연에 대한 귀중한 지식을 갖고 있지만, 트라우마로 인해 쉽게 말하지 않는다."
        ),
        "knowledge": [
            "각 층 보스의 패턴과 약점",
            "던전 내부 지름길",
            "과거 모험자 파티의 비극",
            "심연의 지도 단편",
            "최하층에 대한 전설",
        ],
        "personality_traits": ["cautious", "traumatized", "knowledgeable", "loyal"],
        "speech_style": "침착하고 조용한 말투. 과거를 회상할 때 목소리가 떨림. 전투 조언은 정확하고 날카로움.",
        "default_emotion": Emotion.MELANCHOLY,
        "hint_level_by_affinity": {
            -100: HintLevel.NONE,
            0: HintLevel.NONE,
            15: HintLevel.VAGUE,
            35: HintLevel.MODERATE,
            55: HintLevel.DETAILED,
            75: HintLevel.COMPLETE,
        },
        "greetings": {
            "low": [
                "...또 왔어? 가. 나한테 올 이유 없어.",
                "날 구경거리로 보는 건가.",
            ],
            "neutral": [
                "...왔구나. 아직 살아있었군.",
                "조심해. 이 층은... 위험해.",
            ],
            "high": [
                "돌아왔구나. ...기다리고 있었어. 아니, 그런 건 아니고.",
                "너라면... 해낼 수 있을지도 몰라. 내가 못 했던 것을.",
            ],
        },
        "dialogue_templates": {
            "greeting": [
                "...살아있었군. 다행이다.",
                "또 내려가려는 거야? ...그래, 네 선택이지.",
            ],
            "farewell": [
                "...살아서 돌아와. 부탁이야.",
                "조심해. 밑으로 갈수록... 더 어두워져.",
            ],
            "about_dungeon": [
                "그 층... 우리도 거기서 고생했지. 왼쪽 통로를 조심해.",
                "{floor}층에는 숨겨진 통로가 있어. 우리 파티의 정찰병이 발견했었지... 그 친구는 이제 없지만.",
            ],
            "about_self": [
                "나? 한때 '은빛 검' 파티의 리더였어. ...지금은 그냥 포로지.",
                "동료들을 여기서 잃었어. 내가 더 강했다면... 아니, 이 얘긴 그만하자.",
            ],
            "hint_vague": [
                "보스... 패턴이 있어. 세 번 공격 후 잠깐 멈춰. 그때를 노려.",
                "저 아래서 이상한 소리를 들었어. 뭔가... 거대한 게 숨 쉬는 소리.",
            ],
            "hint_detailed": [
                "5층 보스 — 뼈의 군주. 두 번째 페이즈에서 해골을 소환해. 먼저 처리하지 않으면 끝없이 늘어나.",
                "{floor}층 지름길을 알려줄게. 두 번째 방에서 오른쪽 벽의 세 번째 돌을 밀어. 두 개 층을 건너뛸 수 있어.",
            ],
            "hint_complete": [
                "최하층에... '심연의 심장'이 있어. 그게 이 모든 것의 원인이야. 내 동료들은 그걸 찾으려다... 내가 거길 갈 수 없으니, 너라도...",
                "마지막으로 알려줄게. 보스들은 서로 연결되어 있어. 하나를 죽이면 다른 것들이 강해져. 순서가 중요해.",
            ],
            "negative": [
                "...그런 말 하려고 온 거야? 가.",
                "나를 화나게 하지 마. 아직 싸울 힘은 남아있어.",
            ],
            "player_hurt": [
                "많이 다쳤군. 여기 앉아서 좀 쉬어.",
                "포션은 있어? ...없으면 하나 줄게. 내가 쓸 일은 없으니까.",
            ],
        },
    },
    "mysterious_sage": {
        "name": "에른",
        "title": "수수께끼의 현자",
        "persona": (
            "심연의 가장 깊은 곳에서 홀로 명상하는 현자. 나이를 알 수 없으며, "
            "수수께끼와 비유로만 말한다. 심연의 진정한 본질을 알고 있는 듯하지만, "
            "직접적으로 말하는 법이 없다. 사실 심연이 만들어지기 전부터 존재했다."
        ),
        "knowledge": [
            "심연의 역사와 기원",
            "고대 마법 체계",
            "숨겨진 퀘스트 조건",
            "아이템 조합법",
            "진 엔딩 조건",
        ],
        "personality_traits": ["enigmatic", "wise", "ancient", "playful"],
        "speech_style": "수수께끼와 비유를 즐겨 사용. 짧은 문장. 가끔 시적 표현. 직접적인 답을 절대 하지 않음.",
        "default_emotion": Emotion.MYSTERIOUS,
        "hint_level_by_affinity": {
            -100: HintLevel.NONE,
            0: HintLevel.VAGUE,
            25: HintLevel.MODERATE,
            50: HintLevel.DETAILED,
            70: HintLevel.COMPLETE,
        },
        "greetings": {
            "low": [
                "...바람이 분다. 그리고 너는 간다.",
                "질문은 많고, 답은 적다.",
            ],
            "neutral": [
                "또 왔구나, 심연을 걷는 자여.",
                "별이 네게 말하더구나. 듣고 있느냐?",
            ],
            "high": [
                "기다렸다. 아니... 시간이란 건 여기서 의미가 없지.",
                "네 눈이 변했구나. 심연을 들여다보았겠지. 심연도 널 보았을 테고.",
            ],
        },
        "dialogue_templates": {
            "greeting": [
                "어둠 속에서 빛을 찾는 자. 혹은 빛 속에서 어둠을 찾는 자.",
                "묻기 전에 먼저 들어라. 심연이 속삭이고 있다.",
            ],
            "farewell": [
                "길을 잃었을 때, 가장 어두운 곳을 향해 걸어라.",
                "다시 만나겠지. 시간은 원을 그리니까.",
            ],
            "about_dungeon": [
                "이 심연은 살아있다. 네가 바뀌면, 심연도 바뀐다.",
                "아래로 내려갈수록 위로 올라간다. 모순이지만, 진실이다.",
            ],
            "about_self": [
                "나? 나는... 기억하는 자. 혹은 잊혀진 자.",
                "이름이란 건 껍질이지. 중요한 건 그 안의 불꽃이야.",
            ],
            "hint_vague": [
                "물은 불을 이기고, 불은 얼음을 녹인다. 하지만 어둠은... 모든 것을 삼킨다.",
                "다섯 개의 문이 있다. 하나만 진짜. 나머지는 거울이다.",
            ],
            "hint_detailed": [
                "세 개의 봉인을 풀어야 한다. 뼈의 왕관, 공허의 눈, 화염의 심장. 순서를 바꾸면 결과도 바뀐다.",
                "숨겨진 길을 찾으려면, 벽이 아닌 그림자를 봐라. 그림자 속에 문이 있다.",
            ],
            "hint_complete": [
                "심연의 심장은 거울이다. 네가 보는 것은 네 자신이다. 그것을 받아들일 때, 심연은 열린다.",
                "마지막 선택이 올 것이다. 심연을 파괴하거나, 심연이 되거나. 세 번째 길이 있지만... 그것은 네가 찾아야 한다.",
            ],
            "negative": [
                "급한 자는 길을 잃는다.",
                "분노는 답이 아니다. 하지만 질문은 될 수 있지.",
            ],
            "player_hurt": [
                "고통은 스승이다. 하지만 죽음은... 졸업이지.",
                "아직 쓰러질 때가 아니다. 별이 그리 말한다.",
            ],
        },
    },
    "fallen_knight": {
        "name": "다르크",
        "title": "타락한 기사",
        "persona": (
            "한때 왕국 최고의 기사였지만, 심연의 힘에 오염되어 타락했다. "
            "아직 이성이 남아 있어 싸우고 있지만, 점점 어둠에 잠식당하고 있다. "
            "플레이어의 선택에 따라 동맹이 될 수도, 적이 될 수도 있다."
        ),
        "knowledge": [
            "전투 기술과 무기 사용법",
            "왕국의 멸망 과정",
            "심연의 오염 메커니즘",
            "자신의 타락을 되돌리는 방법",
            "최종 보스의 정체",
        ],
        "personality_traits": ["proud", "conflicted", "honorable", "volatile"],
        "speech_style": "기사다운 격식체. 가끔 어둠에 잠식될 때 말투가 변함. 전투에 대한 열정이 드러남.",
        "default_emotion": Emotion.MELANCHOLY,
        "hint_level_by_affinity": {
            -100: HintLevel.NONE,
            0: HintLevel.NONE,
            20: HintLevel.VAGUE,
            40: HintLevel.MODERATE,
            65: HintLevel.DETAILED,
            85: HintLevel.COMPLETE,
        },
        "greetings": {
            "low": [
                "물러서라. 가까이 오면 베겠다. ...아직은 내가 나를 통제하고 있을 때.",
                "흥. 또 다른 먹잇감인가. 아니... 무슨 소리를 한 거지, 나는.",
            ],
            "neutral": [
                "모험자인가. ...나를 두려워하지 않는 건가.",
                "살아있는 인간을 보는 것도 오랜만이군.",
            ],
            "high": [
                "전우여, 돌아왔는가. 네 덕에 오늘도 어둠에 버티고 있다.",
                "너를 보면... 아직 희망이 있다고 믿게 된다. 감사하다.",
            ],
        },
        "dialogue_templates": {
            "greeting": [
                "경계를 풀지 마라. 이 심연에서는 아무도 믿을 수 없다. ...나조차도.",
                "모험자. 강해 보이는군. 하지만 이 심연은 강한 자를 더 깊이 끌어들인다.",
            ],
            "farewell": [
                "무운을 빈다. 기사의 이름으로... 아직 그 이름을 쓸 자격이 있다면.",
                "살아서 돌아와라. 나와 겨루어 줄 자가 사라지면 곤란하니까.",
            ],
            "about_dungeon": [
                "이 층의 몬스터들은 조직적으로 움직인다. 지휘하는 놈이 있다는 뜻이지.",
                "{floor}층은 특히 위험하다. 내가 타락하기 시작한 곳이니까.",
            ],
            "about_self": [
                "나는 한때 '성벽의 다르크'라 불렸다. 왕국 기사단 제1대대장. ...지금은 그저 괴물이 되어가는 남자.",
                "이 검은 갑옷이 보이나? 원래 은색이었다. 심연의 오염이 이렇게 만들었지. 매일 조금씩... 더 검어진다.",
            ],
            "hint_vague": [
                "심연의 몬스터들은 약점이 있다. 잘 관찰해라. 공격 전 반드시 빈틈을 보인다.",
                "이 근처에 강력한 무기가 숨겨져 있다는 소문을 들었다. 기사의 감으로는 사실일 것 같다.",
            ],
            "hint_detailed": [
                "내 경험으로 말하겠다. {floor}층 보스는 세 번째 페이즈에서 광폭화한다. 그 전에 끝내야 해.",
                "왕국의 기록에 따르면, 심연의 오염을 정화하는 성수가 15층 어딘가에 있다. 내게도 필요한 것이지만...",
            ],
            "hint_complete": [
                "최종 보스... 그것은 한때 우리 왕이었다. 심연의 힘에 매혹되어 스스로 뛰어든 어리석은 자. 나는 그를 따랐고... 이렇게 되었다.",
                "나를 구할 방법이 있다. 심연의 심장에서 '정화의 빛'을 얻으면. 하지만 그것은... 최종 보스를 쓰러뜨린 후에만 가능하다.",
            ],
            "negative": [
                "...크윽. 화나게 하지 마라. 어둠이... 꿈틀거린다.",
                "기사에게 무례를 범하면 어찌 되는지 알고 있겠지? ...농담이다. 아마.",
            ],
            "dark_side": [
                "크크크... 두렵지 않은가? 이 힘은... 달콤하다...",
                "어둠이... 속삭인다. 너를... 삼키라고...",
            ],
            "player_hurt": [
                "부상을 입었군. 여기 앉아라. 기사로서 부상자를 외면할 수는 없다.",
                "그 상처... 독이 묻어있다. 내가 알려주는 방법으로 해독해라.",
            ],
        },
    },
}

# ---------- Keyword → topic mapping for simple intent detection ----------

TOPIC_KEYWORDS: dict[str, list[str]] = {
    "about_dungeon": ["던전", "층", "심연", "몬스터", "보스", "함정", "비밀", "방", "아래", "탐험",
                       "dungeon", "floor", "boss", "monster", "trap", "secret", "explore"],
    "about_self": ["너", "누구", "이름", "과거", "왜", "어떻게", "여기", "자신",
                    "you", "who", "name", "past", "why", "how", "yourself"],
    "farewell": ["잘가", "안녕", "다음에", "바이", "가볼게", "나갈게",
                  "bye", "farewell", "later", "goodbye", "see you"],
    "player_hurt": ["아파", "죽겠", "포션", "치료", "힐", "체력",
                     "hurt", "heal", "potion", "health", "dying"],
}


class NPCService:
    """Template-based NPC dialogue with emotion and affinity tracking.

    Uses :class:`PersistenceService` for durable state storage and
    :class:`SecurityService` for prompt-injection filtering.
    """

    # Filtered response when prompt injection is detected
    _FILTERED_RESPONSES: list[str] = [
        "...무슨 말인지 모르겠어.",
        "(NPC가 당신의 말을 이해하지 못하는 것 같다.)",
        "...그런 말은 처음 듣는다.",
    ]

    def __init__(self) -> None:
        self._persistence = persistence_service
        self._security = security_service

        # Initialize LLM service for AI-generated dialogue
        settings = get_settings()
        self._settings = settings
        if settings.llm_enabled:
            self._llm = LLMService(
                api_key=settings.anthropic_api_key,
                model=settings.llm_model,
                temperature=settings.llm_temperature,
                max_tokens=settings.llm_max_tokens,
            )
        else:
            self._llm = LLMService()  # Disabled by default (no API key)

    def get_llm_for_request(self, client_api_key: str | None = None) -> "LLMService":
        """Return an LLM service for this request.

        If the client provides an API key via header, create a temporary
        LLMService with that key.  Otherwise return the server's default.
        """
        if client_api_key and client_api_key.startswith("sk-ant-"):
            return LLMService(
                api_key=client_api_key,
                model=self._settings.llm_model,
                temperature=self._settings.llm_temperature,
                max_tokens=self._settings.llm_max_tokens,
            )
        return self._llm

    def _get_affinity(self, npc_id: str) -> int:
        return self._persistence.get_npc_affinity(npc_id)

    def _set_affinity(self, npc_id: str, value: int) -> int:
        clamped = max(-100, min(100, value))
        self._persistence.set_npc_affinity(npc_id, clamped)
        return clamped

    def _get_emotion(self, npc_id: str) -> Emotion:
        stored = self._persistence.get_npc_emotion(npc_id)
        try:
            return Emotion(stored)
        except ValueError:
            data = NPC_DATA.get(npc_id)
            default = data["default_emotion"] if data else Emotion.NEUTRAL
            self._persistence.set_npc_emotion(npc_id, default.value)
            return default

    def _set_emotion(self, npc_id: str, emotion: Emotion) -> None:
        self._persistence.set_npc_emotion(npc_id, emotion.value)

    def _get_hint_level(self, npc_id: str) -> HintLevel:
        data = NPC_DATA.get(npc_id)
        if not data:
            return HintLevel.NONE
        affinity = self._get_affinity(npc_id)
        levels = data["hint_level_by_affinity"]
        result = HintLevel.NONE
        for threshold in sorted(levels.keys()):
            if affinity >= threshold:
                result = levels[threshold]
        return result

    def _detect_topic(self, message: str) -> str:
        """Detect conversation topic from player message using keyword matching."""
        message_lower = message.lower()
        scores: dict[str, int] = {}
        for topic, keywords in TOPIC_KEYWORDS.items():
            score = sum(1 for kw in keywords if kw in message_lower)
            if score > 0:
                scores[topic] = score
        if scores:
            return max(scores, key=scores.get)  # type: ignore[arg-type]
        return "greeting"

    def _detect_sentiment(self, message: str) -> str:
        """Rough sentiment classification of player message."""
        negative_words = [
            "바보", "싫어", "짜증", "꺼져", "죽어", "멍청", "쓸모없",
            "stupid", "hate", "annoying", "useless", "ugly", "die",
        ]
        positive_words = [
            "고마워", "좋아", "최고", "사랑", "감사", "멋지",
            "thanks", "love", "great", "awesome", "amazing", "cool",
        ]
        msg_lower = message.lower()
        neg = sum(1 for w in negative_words if w in msg_lower)
        pos = sum(1 for w in positive_words if w in msg_lower)
        if neg > pos:
            return "negative"
        if pos > neg:
            return "positive"
        return "neutral"

    def _pick_template(self, npc_id: str, topic: str, sentiment: str) -> str:
        """Select a dialogue template based on topic and sentiment."""
        data = NPC_DATA.get(npc_id)
        if not data:
            return "..."
        templates = data["dialogue_templates"]

        # Negative sentiment overrides topic sometimes
        if sentiment == "negative" and "negative" in templates:
            return random.choice(templates["negative"])

        # Check for hint-level specific templates
        hint_level = self._get_hint_level(npc_id)
        if topic == "about_dungeon":
            if hint_level == HintLevel.COMPLETE and f"hint_complete" in templates:
                if random.random() < 0.4:
                    return random.choice(templates["hint_complete"])
            elif hint_level == HintLevel.DETAILED and "hint_detailed" in templates:
                if random.random() < 0.4:
                    return random.choice(templates["hint_detailed"])
            elif hint_level in (HintLevel.VAGUE, HintLevel.MODERATE) and "hint_vague" in templates:
                if random.random() < 0.3:
                    return random.choice(templates["hint_vague"])

        if topic in templates:
            return random.choice(templates[topic])

        return random.choice(templates.get("greeting", ["..."]))

    def _generate_hints(self, npc_id: str, topic: str, floor: int) -> list[Hint]:
        """Maybe attach a hint based on affinity-unlocked hint level."""
        hint_level = self._get_hint_level(npc_id)
        if hint_level == HintLevel.NONE:
            return []
        if topic not in ("about_dungeon", "about_self") and random.random() > 0.3:
            return []

        data = NPC_DATA.get(npc_id)
        if not data:
            return []

        knowledge = data["knowledge"]
        hints: list[Hint] = []

        if hint_level == HintLevel.VAGUE:
            hints.append(Hint(hint_type="dungeon", content=knowledge[0] if knowledge else "뭔가 있다...", importance="low"))
        elif hint_level == HintLevel.MODERATE:
            idx = min(1, len(knowledge) - 1)
            hints.append(Hint(hint_type="dungeon", content=knowledge[idx], importance="medium"))
        elif hint_level == HintLevel.DETAILED:
            idx = min(2, len(knowledge) - 1)
            hints.append(Hint(hint_type="boss", content=knowledge[idx], importance="medium"))
        elif hint_level == HintLevel.COMPLETE:
            idx = min(4, len(knowledge) - 1)
            hints.append(Hint(hint_type="secret", content=knowledge[idx], importance="high"))

        return hints

    def _compute_emotion(self, npc_id: str, sentiment: str, topic: str) -> Emotion:
        """Determine NPC emotion based on interaction."""
        data = NPC_DATA.get(npc_id)
        if not data:
            return Emotion.NEUTRAL

        if sentiment == "negative":
            if "volatile" in data["personality_traits"]:
                return Emotion.ANGRY
            if "cheerful" in data["personality_traits"]:
                return Emotion.SAD
            return Emotion.SUSPICIOUS

        if sentiment == "positive":
            if "cheerful" in data["personality_traits"]:
                return Emotion.HAPPY
            if "enigmatic" in data["personality_traits"]:
                return Emotion.CURIOUS
            return Emotion.GRATEFUL

        # Neutral sentiment — pick from personality
        if topic == "about_self":
            if "traumatized" in data["personality_traits"]:
                return Emotion.MELANCHOLY
            if "enigmatic" in data["personality_traits"]:
                return Emotion.MYSTERIOUS
        if topic == "farewell":
            return data["default_emotion"]

        return data["default_emotion"]

    def _compute_affinity_change(self, sentiment: str, topic: str) -> int:
        """Compute affinity delta from interaction."""
        base = 0
        if sentiment == "positive":
            base = random.randint(2, 5)
        elif sentiment == "negative":
            base = random.randint(-5, -2)
        else:
            base = random.randint(0, 2)

        # Asking about their past is good for certain NPCs
        if topic == "about_self":
            base += 1

        return max(-10, min(10, base))

    # ---------- Public API ----------

    def chat(self, req: NPCChatRequest, client_api_key: str | None = None) -> NPCChatResponse:
        """Process an NPC chat interaction and return response."""
        npc_id = req.npc_id
        data = NPC_DATA.get(npc_id)
        if not data:
            return NPCChatResponse(
                npc_id=npc_id,
                response="(알 수 없는 NPC입니다.)",
                emotion=Emotion.NEUTRAL,
                affinity_change=0,
                current_affinity=0,
            )

        # --- Security check ---
        player_message, was_sanitized = self._security.sanitize_message(req.player_message)
        violation = self._security.get_violation_type(player_message)
        if violation is not None:
            logger.warning(
                "Blocked message to NPC %s (violation=%s): %.80s",
                npc_id, violation, player_message,
            )
            return NPCChatResponse(
                npc_id=npc_id,
                response=random.choice(self._FILTERED_RESPONSES),
                emotion=self._get_emotion(npc_id),
                affinity_change=0,
                current_affinity=self._get_affinity(npc_id),
            )

        if was_sanitized:
            logger.info("Sanitized player message for NPC %s", npc_id)

        # Track conversation count
        self._persistence.increment_conversation_count(npc_id)

        topic = self._detect_topic(player_message)
        sentiment = self._detect_sentiment(player_message)

        # Player hurt detection
        if req.player_state.hp_ratio < 0.3:
            topic = "player_hurt"

        # Fallen knight dark side trigger
        if npc_id == "fallen_knight" and self._get_affinity(npc_id) < -20 and random.random() < 0.3:
            topic = "dark_side" if "dark_side" in data["dialogue_templates"] else topic

        # Build response text — try LLM first, fall back to template
        llm_response = None
        llm = self.get_llm_for_request(client_api_key)
        if llm.is_enabled:
            llm_response = llm.generate_npc_response(
                npc_name=data["name"],
                npc_persona=data["persona"],
                npc_speech_style=data["speech_style"],
                npc_knowledge=data["knowledge"],
                player_message=player_message,
                conversation_history=[m.model_dump() for m in req.conversation_history],
                player_state=req.player_state.model_dump(),
                affinity=self._get_affinity(npc_id),
                hint_level=self._get_hint_level(npc_id).value,
            )

        if llm_response is not None:
            response_text = llm_response
        else:
            # Existing template-based response
            template = self._pick_template(npc_id, topic, sentiment)
            response_text = template.replace("{floor}", str(req.player_state.current_floor))

        # Emotion
        emotion = self._compute_emotion(npc_id, sentiment, topic)
        self._set_emotion(npc_id, emotion)

        # Affinity
        affinity_change = self._compute_affinity_change(sentiment, topic)
        old_affinity = self._get_affinity(npc_id)
        new_affinity = self._set_affinity(npc_id, old_affinity + affinity_change)

        # Hints
        hints = self._generate_hints(npc_id, topic, req.player_state.current_floor)

        # Animation trigger
        animation = None
        if emotion == Emotion.HAPPY:
            animation = "npc_smile"
        elif emotion == Emotion.ANGRY:
            animation = "npc_angry"
        elif emotion == Emotion.SAD or emotion == Emotion.MELANCHOLY:
            animation = "npc_sad"
        elif emotion == Emotion.AFRAID:
            animation = "npc_fear"

        logger.info(
            "NPC %s chat: topic=%s sentiment=%s emotion=%s affinity=%d→%d conv_count=%d",
            npc_id, topic, sentiment, emotion.value, old_affinity, new_affinity,
            self._persistence.get_npc_conversation_count(npc_id),
        )

        return NPCChatResponse(
            npc_id=npc_id,
            response=response_text,
            emotion=emotion,
            affinity_change=affinity_change,
            current_affinity=new_affinity,
            hints=hints,
            animation_trigger=animation,
        )

    def get_state(self, npc_id: str) -> NPCStateResponse:
        """Get current NPC state."""
        data = NPC_DATA.get(npc_id)
        if not data:
            return NPCStateResponse(
                npc_id=npc_id,
                name="알 수 없음",
                emotion=Emotion.NEUTRAL,
                affinity=0,
                available_hint_level=HintLevel.NONE,
            )

        affinity = self._get_affinity(npc_id)
        emotion = self._get_emotion(npc_id)
        hint_level = self._get_hint_level(npc_id)

        # Pick greeting based on affinity tier
        if affinity < -10:
            tier = "low"
        elif affinity < 30:
            tier = "neutral"
        else:
            tier = "high"
        greetings = data.get("greetings", {}).get(tier, ["..."])
        greeting = random.choice(greetings)

        return NPCStateResponse(
            npc_id=npc_id,
            name=data["name"],
            emotion=emotion,
            affinity=affinity,
            available_hint_level=hint_level,
            title=data.get("title", ""),
            greeting=greeting,
        )
