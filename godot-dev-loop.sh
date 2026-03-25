#!/bin/bash
# ============================================================
# godot-dev-loop.sh - Godot 전용 멀티 에이전트 개발 루프
# 
# A(Claude 코더) → Godot 빌드/검증 → B(Claude 리뷰어) → 반복
#
# 사용법:
#   ./godot-dev-loop.sh "적 AI 패트롤 시스템 구현해줘"
#   ./godot-dev-loop.sh "인벤토리 UI 만들어줘" --scene res://scenes/inventory.tscn
#
# 환경변수:
#   GODOT_BIN=godot          Godot 실행파일 경로
#   PROJECT_DIR=.             Godot 프로젝트 디렉토리
#   MAX_ITERATIONS=3          최대 반복 횟수
#   LOG_DIR=.godot-dev-logs   로그 저장 경로
#   TEST_SCENE=               테스트할 특정 씬 (선택)
#   EXPORT_PRESET=            빌드 테스트용 export preset (선택)
# ============================================================

set -euo pipefail

# ── 인자 파싱 ──
TASK=""
ARG_SCENE=""
for arg in "$@"; do
    case "$arg" in
        --scene=*) ARG_SCENE="${arg#--scene=}" ;;
        --scene) :;; # 다음 인자에서 처리
        *) 
            if [ -z "$TASK" ]; then
                TASK="$arg"
            elif [ "$prev_arg" = "--scene" ]; then
                ARG_SCENE="$arg"
            fi
            ;;
    esac
    prev_arg="$arg"
done

if [ -z "$TASK" ]; then
    echo "❌ 사용법: ./godot-dev-loop.sh \"작업 내용\" [--scene res://path/to/scene.tscn]"
    exit 1
fi

# ── 설정 ──
GODOT="${GODOT_BIN:-godot}"
PROJECT="${PROJECT_DIR:-.}"
MAX_ITER="${MAX_ITERATIONS:-3}"
LOG_DIR="${LOG_DIR:-.godot-dev-logs}"
TEST_SCENE="${TEST_SCENE:-$ARG_SCENE}"
EXPORT_PRESET="${EXPORT_PRESET:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$LOG_DIR"

# ── 색상 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log()       { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
separator() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Godot 존재 확인 ──
if ! command -v "$GODOT" &> /dev/null; then
    echo -e "${RED}❌ '$GODOT' 를 찾을 수 없습니다.${NC}"
    echo "   GODOT_BIN 환경변수로 Godot 경로를 지정하세요:"
    echo "   GODOT_BIN=/path/to/godot ./godot-dev-loop.sh \"작업\""
    exit 1
fi

# ── project.godot 확인 ──
if [ ! -f "$PROJECT/project.godot" ]; then
    echo -e "${RED}❌ '$PROJECT/project.godot' 를 찾을 수 없습니다.${NC}"
    echo "   PROJECT_DIR 환경변수로 Godot 프로젝트 경로를 지정하세요."
    exit 1
fi

# Godot 버전 확인
GODOT_VERSION=$("$GODOT" --version 2>/dev/null | head -1 || echo "unknown")
log "🎮 Godot 버전: $GODOT_VERSION"

# ════════════════════════════════════════════════════════
# Godot 검증 함수들
# ════════════════════════════════════════════════════════

# GDScript 문법 검사
validate_gdscript() {
    log "${MAGENTA}📝 GDScript 문법 검사 중...${NC}"
    
    local errors=""
    local error_count=0
    local checked=0
    
    # 변경된 .gd 파일만 검사 (git 있는 경우)
    local files_to_check=""
    if git rev-parse --git-dir > /dev/null 2>&1; then
        files_to_check=$(git diff --name-only --diff-filter=ACMR -- '*.gd' 2>/dev/null || true)
        if [ -z "$files_to_check" ]; then
            files_to_check=$(git diff --cached --name-only --diff-filter=ACMR -- '*.gd' 2>/dev/null || true)
        fi
    fi
    
    # git이 없거나 변경사항이 없으면 전체 검사
    if [ -z "$files_to_check" ]; then
        files_to_check=$(find "$PROJECT" -name "*.gd" -not -path "*/.godot/*" -not -path "*/addons/*" 2>/dev/null || true)
    fi
    
    if [ -z "$files_to_check" ]; then
        echo "  검사할 GDScript 파일 없음"
        return 0
    fi
    
    while IFS= read -r gdfile; do
        [ -z "$gdfile" ] && continue
        [ ! -f "$PROJECT/$gdfile" ] && [ ! -f "$gdfile" ] && continue
        
        checked=$((checked + 1))
        
        # 기본 문법 체크: 들여쓰기 혼합, 빈 함수 등
        local file_path="$gdfile"
        [ ! -f "$file_path" ] && file_path="$PROJECT/$gdfile"
        
        # 탭+스페이스 혼합 체크
        if grep -Pn '^\t+ ' "$file_path" 2>/dev/null | head -3 > /tmp/gdcheck_indent 2>/dev/null; then
            if [ -s /tmp/gdcheck_indent ]; then
                errors="$errors\n  ⚠️ $gdfile: 들여쓰기 혼합 (탭+스페이스)"
            fi
        fi
        
        # 일반적인 실수 패턴 체크
        if grep -n 'var.*=.*null$' "$file_path" 2>/dev/null | grep -v '@export\|@onready' > /dev/null 2>&1; then
            : # null 초기화는 일반적이므로 패스
        fi
        
        # pass만 있는 빈 함수 감지 (경고만)
        if grep -Pn '^\tfunc.*:$' "$file_path" 2>/dev/null > /dev/null; then
            : # 나중에 더 정교한 체크 가능
        fi
        
    done <<< "$files_to_check"
    
    # Godot --check-only로 스크립트 검증 (가능한 경우)
    local godot_errors=""
    while IFS= read -r gdfile; do
        [ -z "$gdfile" ] && continue
        local file_path="$gdfile"
        [ ! -f "$file_path" ] && file_path="$PROJECT/$gdfile"
        [ ! -f "$file_path" ] && continue
        
        # res:// 경로로 변환 — PROJECT 접두사 제거
        local rel_path="$gdfile"
        if [[ "$rel_path" == "$PROJECT/"* ]]; then
            rel_path="${rel_path#$PROJECT/}"
        fi
        local res_path="res://$rel_path"
        
        local check_output
        check_output=$("$GODOT" --headless --path "$PROJECT" --check-only -s "$res_path" 2>&1 || true)
        
        if echo "$check_output" | grep -qi "error\|failed"; then
            error_count=$((error_count + 1))
            godot_errors="$godot_errors\n  ❌ $gdfile:\n$(echo "$check_output" | grep -i 'error\|failed' | head -5 | sed 's/^/      /')"
        fi
    done <<< "$files_to_check"
    
    echo "  검사한 파일: ${checked}개"
    
    if [ -n "$errors" ]; then
        echo -e "  경고:$errors"
    fi
    
    if [ "$error_count" -gt 0 ]; then
        echo -e "  에러:$godot_errors"
        return 1
    fi
    
    echo -e "  ${GREEN}✅ GDScript 검사 통과${NC}"
    return 0
}

# 프로젝트 임포트 & 빌드 테스트
validate_project_import() {
    log "${MAGENTA}📦 프로젝트 임포트 검증 중...${NC}"
    
    local import_output
    import_output=$("$GODOT" --headless --path "$PROJECT" --editor --quit 2>&1 || true)
    
    local import_errors
    import_errors=$(echo "$import_output" | grep -ci "error" || true)
    
    if [ "$import_errors" -gt 0 ]; then
        echo "  ⚠️ 임포트 중 에러 $import_errors개 발견:"
        echo "$import_output" | grep -i "error" | head -10 | sed 's/^/    /'
        return 1
    fi
    
    echo -e "  ${GREEN}✅ 프로젝트 임포트 성공${NC}"
    return 0
}

# 씬 실행 테스트 (지정된 경우)
validate_scene_run() {
    if [ -z "$TEST_SCENE" ]; then
        echo "  (테스트 씬 미지정 - 스킵)"
        return 0
    fi
    
    log "${MAGENTA}🎬 씬 실행 테스트: $TEST_SCENE${NC}"
    
    # 5초간 씬 실행 후 종료
    local scene_output
    scene_output=$(timeout 10 "$GODOT" --headless --path "$PROJECT" "$TEST_SCENE" 2>&1 || true)
    
    local scene_errors
    scene_errors=$(echo "$scene_output" | grep -ci "error\|exception\|crash" || true)
    
    if [ "$scene_errors" -gt 0 ]; then
        echo "  ❌ 씬 실행 중 에러:"
        echo "$scene_output" | grep -i "error\|exception\|crash" | head -10 | sed 's/^/    /'
        return 1
    fi
    
    echo -e "  ${GREEN}✅ 씬 실행 테스트 통과${NC}"
    return 0
}

# Export 빌드 테스트 (preset 지정된 경우)
validate_export() {
    if [ -z "$EXPORT_PRESET" ]; then
        echo "  (Export preset 미지정 - 스킵)"
        return 0
    fi
    
    log "${MAGENTA}🏗️ Export 빌드 테스트: $EXPORT_PRESET${NC}"
    
    local build_dir="$LOG_DIR/builds/$TIMESTAMP"
    mkdir -p "$build_dir"
    
    local export_output
    export_output=$("$GODOT" --headless --path "$PROJECT" --export-release "$EXPORT_PRESET" "$build_dir/game" 2>&1 || true)
    
    if echo "$export_output" | grep -qi "error\|failed"; then
        echo "  ❌ Export 실패:"
        echo "$export_output" | grep -i "error\|failed" | head -10 | sed 's/^/    /'
        return 1
    fi
    
    echo -e "  ${GREEN}✅ Export 빌드 성공${NC}"
    return 0
}

# GDScript 단위 테스트 (GUT/gdUnit 있는 경우)
validate_unit_tests() {
    # GUT (Godot Unit Test) 확인
    if [ -d "$PROJECT/addons/gut" ]; then
        log "${MAGENTA}🧪 GUT 단위 테스트 실행 중...${NC}"
        
        local test_output
        test_output=$(timeout 60 "$GODOT" --headless --path "$PROJECT" \
            -s addons/gut/gut_cmdln.gd \
            -gdir=res://test \
            -gexit 2>&1 || true)
        
        if echo "$test_output" | grep -qi "failures\|errors"; then
            local fail_count
            fail_count=$(echo "$test_output" | grep -oi '[0-9]* fail' | head -1 || echo "")
            echo "  ❌ 테스트 실패: $fail_count"
            echo "$test_output" | tail -20 | sed 's/^/    /'
            return 1
        fi
        
        echo -e "  ${GREEN}✅ 단위 테스트 통과${NC}"
        return 0
    fi
    
    # gdUnit4 확인
    if [ -d "$PROJECT/addons/gdUnit4" ]; then
        log "${MAGENTA}🧪 gdUnit4 테스트 실행 중...${NC}"
        
        local test_output
        test_output=$(timeout 60 "$GODOT" --headless --path "$PROJECT" \
            -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
            --add res://test 2>&1 || true)
        
        if echo "$test_output" | grep -qi "FAILED\|ERROR"; then
            echo "  ❌ gdUnit4 테스트 실패"
            echo "$test_output" | tail -20 | sed 's/^/    /'
            return 1
        fi
        
        echo -e "  ${GREEN}✅ gdUnit4 테스트 통과${NC}"
        return 0
    fi
    
    echo "  (테스트 프레임워크 없음 - 스킵. GUT 또는 gdUnit4 추천)"
    return 0
}

# ── 전체 Godot 검증 실행 ──
run_godot_validation() {
    log "${YELLOW}🎮 ═══ Godot 검증 단계 ═══${NC}"
    
    local validation_report="# Godot 검증 결과 - 라운드 $1\n\n"
    local has_errors=0
    
    # 1) GDScript 문법
    local gdscript_result
    gdscript_result=$(validate_gdscript 2>&1) || has_errors=1
    validation_report="$validation_report## GDScript 검사\n$gdscript_result\n\n"
    echo "$gdscript_result"
    
    # 2) 프로젝트 임포트
    local import_result
    import_result=$(validate_project_import 2>&1) || has_errors=1
    validation_report="$validation_report## 프로젝트 임포트\n$import_result\n\n"
    echo "$import_result"
    
    # 3) 씬 실행 테스트
    local scene_result
    scene_result=$(validate_scene_run 2>&1) || has_errors=1
    validation_report="$validation_report## 씬 실행\n$scene_result\n\n"
    echo "$scene_result"
    
    # 4) Export 빌드
    local export_result
    export_result=$(validate_export 2>&1) || has_errors=1
    validation_report="$validation_report## Export 빌드\n$export_result\n\n"
    echo "$export_result"
    
    # 5) 단위 테스트
    local test_result
    test_result=$(validate_unit_tests 2>&1) || has_errors=1
    validation_report="$validation_report## 단위 테스트\n$test_result\n\n"
    echo "$test_result"
    
    # 보고서 저장
    echo -e "$validation_report" > "$LOG_DIR/godot_validation_${TIMESTAMP}_r${1}.md"
    
    return $has_errors
}

# ── 변경 파일 수집 ──
collect_changed_files() {
    local contents=""
    local changed=""
    
    cd "$PROJECT"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        changed=$(git diff --name-only -- '*.gd' '*.tscn' '*.tres' '*.cfg' 2>/dev/null || true)
        if [ -z "$changed" ]; then
            changed=$(git diff --cached --name-only -- '*.gd' '*.tscn' '*.tres' '*.cfg' 2>/dev/null || true)
        fi
    fi
    
    if [ -z "$changed" ]; then
        # git 없으면 최근 수정된 Godot 파일
        changed=$(find . -name "*.gd" -newer project.godot -not -path "*/.godot/*" 2>/dev/null | head -10 || true)
    fi
    
    if [ -n "$changed" ]; then
        local count=0
        while IFS= read -r file; do
            if [ -f "$file" ] && [ "$count" -lt 8 ]; then
                contents="$contents\n--- $file ---\n$(head -150 "$file")\n--- 끝 ---\n"
                count=$((count + 1))
            fi
        done <<< "$changed"
    fi
    cd - > /dev/null
    
    echo "$contents"
}

# ════════════════════════════════════════════════════════
# 메인 루프
# ════════════════════════════════════════════════════════

separator
log "${GREEN}🚀 Godot 멀티 에이전트 개발 루프 시작${NC}"
log "📋 작업: $TASK"
log "🎮 Godot: $GODOT_VERSION"
log "📁 프로젝트: $PROJECT"
log "🔄 최대 반복: $MAX_ITER회"
[ -n "$TEST_SCENE" ] && log "🎬 테스트 씬: $TEST_SCENE"
[ -n "$EXPORT_PRESET" ] && log "🏗️ Export: $EXPORT_PRESET"
separator

for i in $(seq 1 "$MAX_ITER"); do
    log "${YELLOW}═══ 라운드 $i / $MAX_ITER ═══${NC}"
    
    # ══ Phase A: 코더 에이전트 ══
    log "${GREEN}🔨 [A 에이전트 - Claude 코더] 작업 중...${NC}"
    
    if [ "$i" -eq 1 ]; then
        CODER_PROMPT="$TASK

이 프로젝트는 Godot 엔진 프로젝트야.
- GDScript 컨벤션을 따라줘
- 씬(.tscn)과 스크립트(.gd)를 적절히 분리해줘
- 시그널 기반 설계를 선호해
- @export, @onready 등 Godot 4 문법을 사용해

작업 완료 후 변경/생성한 파일 목록과 주요 내용을 요약해줘."
    else
        REVIEW_CONTENT=$(cat "$LOG_DIR/review_${TIMESTAMP}_r$((i-1)).md" 2>/dev/null || echo "없음")
        VALIDATION_CONTENT=$(cat "$LOG_DIR/godot_validation_${TIMESTAMP}_r$((i-1)).md" 2>/dev/null || echo "없음")
        
        CODER_PROMPT="이전 리뷰와 Godot 빌드 결과를 반영해서 수정해줘:

--- 코드 리뷰 피드백 ---
$REVIEW_CONTENT
--- 끝 ---

--- Godot 검증 결과 ---
$VALIDATION_CONTENT
--- 끝 ---

수정 완료 후 변경 내용을 요약해줘."
    fi
    
    cd "$PROJECT"
    CODER_OUTPUT=$(claude --print "$CODER_PROMPT" 2>&1) || true
    cd - > /dev/null
    
    echo "$CODER_OUTPUT" > "$LOG_DIR/coder_${TIMESTAMP}_r${i}.md"
    log "💾 코더 출력: $LOG_DIR/coder_${TIMESTAMP}_r${i}.md"
    
    # ══ Phase G: Godot 검증 ══
    GODOT_PASS=true
    GODOT_VALIDATION=""
    
    log "${MAGENTA}🎮 [Godot 검증] 빌드 & 테스트...${NC}"
    GODOT_VALIDATION=$(run_godot_validation "$i" 2>&1) || GODOT_PASS=false
    echo "$GODOT_VALIDATION"
    
    # ══ Phase B: 리뷰어 에이전트 ══
    log "${RED}🔍 [B 에이전트 - Claude 리뷰어] 리뷰 중...${NC}"
    
    FILE_CONTENTS=$(collect_changed_files)
    
    REVIEW_PROMPT="너는 Godot 게임 개발 시니어 리뷰어야. 아래 코드를 엄격하게 리뷰해줘.

## 원래 작업 요청
$TASK

## 코더의 작업 요약
$(echo "$CODER_OUTPUT" | head -100)

## Godot 빌드/검증 결과
$GODOT_VALIDATION

## 변경된 파일들
$(echo -e "$FILE_CONTENTS")

## Godot 특화 리뷰 기준 (각 1-10점)

1. **기능 완성도**: 요청한 기능이 정확히 구현되었는가?
2. **GDScript 품질**: Godot 4 컨벤션, 타입 힌트, 네이밍(snake_case)
3. **씬 설계**: 노드 구조, 시그널 활용, 씬 분리가 적절한가?
4. **성능**: _process vs _physics_process 적절 사용, 불필요한 매 프레임 연산
5. **에러/빌드**: Godot 검증 통과 여부, null 참조 위험

## 반드시 아래 형식으로 출력:
### 총점: X/50
### 판정: PASS 또는 FAIL (40점 이상 PASS)
### Godot 빌드: $([ "$GODOT_PASS" = true ] && echo "✅ 통과" || echo "❌ 실패")
### 수정 필요 사항 (FAIL인 경우):
- 파일명과 구체적 수정 지시
### 개선 제안:
- Godot 베스트 프랙티스 기준"

    REVIEW_OUTPUT=$(claude --print "$REVIEW_PROMPT" 2>&1) || true
    
    echo "$REVIEW_OUTPUT" > "$LOG_DIR/review_${TIMESTAMP}_r${i}.md"
    log "💾 리뷰 출력: $LOG_DIR/review_${TIMESTAMP}_r${i}.md"
    
    # ══ 결과 판단 ══
    if echo "$REVIEW_OUTPUT" | grep -qi "PASS" && [ "$GODOT_PASS" = true ]; then
        separator
        log "${GREEN}✅ 라운드 $i에서 리뷰 + Godot 검증 모두 통과!${NC}"
        
        # 최종 요약
        cat > "$LOG_DIR/summary_${TIMESTAMP}.md" << EOF
# 🎮 Godot 개발 루프 완료

- **작업**: $TASK
- **통과 라운드**: $i / $MAX_ITER
- **Godot 버전**: $GODOT_VERSION
- **시간**: $TIMESTAMP
- **로그**: $LOG_DIR/

## 라운드별 기록
$(for r in $(seq 1 "$i"); do
    echo "### 라운드 $r"
    echo "- 코더: coder_${TIMESTAMP}_r${r}.md"
    echo "- 검증: godot_validation_${TIMESTAMP}_r${r}.md"
    echo "- 리뷰: review_${TIMESTAMP}_r${r}.md"
done)
EOF
        log "📊 요약: $LOG_DIR/summary_${TIMESTAMP}.md"
        separator
        exit 0
    fi
    
    # Godot 빌드 실패인데 리뷰는 PASS인 경우
    if echo "$REVIEW_OUTPUT" | grep -qi "PASS" && [ "$GODOT_PASS" = false ]; then
        log "${YELLOW}⚠️ 코드 리뷰는 통과했지만 Godot 빌드 에러 있음 → 수정 필요${NC}"
    fi
    
    if [ "$i" -lt "$MAX_ITER" ]; then
        log "${YELLOW}⚠️ 미통과 → 라운드 $((i+1))에서 수정${NC}"
    fi
    
    separator
done

log "${RED}⚠️ 최대 반복($MAX_ITER회) 도달. 수동 확인이 필요합니다.${NC}"
log "📊 전체 로그: $LOG_DIR/"
exit 1
