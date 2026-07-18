# 백엔드 리뷰 — notion_manager M1 MVP

> 리뷰 대상: `01_spec_planner.md`. 근거: `00_cto_brief.md`, `notion-manager/docs/NOTION_AGENT_HANDOVER.md`,
> `notion-manager/agent/workspace_map.json`, `notion-manager/pyproject.toml` + `uv.lock`, `.env.example`.
> `notion-manager/.venv`에 설치된 실 패키지(discord-py 2.7.1, openai 2.46.0, anthropic 0.117.0,
> notion-client 3.1.0, aiosqlite 0.22.1)를 직접 확인해 SDK 시그니처·예외 클래스·`notion_version`
> 기본값·`data_sources` 엔드포인트 존재 등 스펙의 기술적 가정은 대부분 정확함을 검증했다.
> 아래는 그 위에서 발견한 계약/동시성/에러 경로/멱등성 문제다.

## Critical (must fix before implementation)

- **[C1] 히스토리 커밋이 "요청 성공 종료" 단일 시점에만 원자적으로 일어나 크래시·타임아웃 시
  중복 생성 위험이 생긴다** — §3.3 `AgentRunner.run` 4번, §5.1, §5.5 E3/E4.
  스펙: "종료 시 이번 요청에서 생성된 중립 메시지 전부를 SessionStore에 저장(원자적으로 커밋)."
  즉 사용자 원문·tool_calls·tool 결과가 세션 히스토리에 기록되는 시점은 루프가 **정상 종료했을 때뿐**이다.
  총 타임아웃(300초, E3) 또는 최대 턴(10, E4)에 걸려 중단되면, 그 요청 안에서 이미 실행된
  `create_schedule_entry`/`update_tracker_entry` 등 **Notion 쓰기는 이미 반영됐는데** 그 사실이
  히스토리 어디에도 남지 않는다. 특히 `asyncio.timeout(300)`이 Notion API 호출 도중(`pages.create`
  응답 대기 중) 발동하면 클라이언트는 취소됐지만 서버 쪽 페이지 생성은 이미 완료됐을 수 있다
  (write-timeout ambiguity). 이 상태에서 E3/E4 메시지("다시 시도" "나눠서 요청")를 그대로 따라
  사용자가 같은 요청을 재전송하면, 새 히스토리는 직전 실행의 결과를 전혀 모르므로 모델이
  **같은 일정/트래커 항목을 다시 생성**할 수 있다. 또한 프로세스 재시작 시나리오에서도 동일하게
  원 요청 텍스트 자체가 유실돼 "재시작 후에도 후속 피드백 이어짐"(DoD 3번) 요구를 완전히 만족하지
  못한다.
  제안: (a) 사용자 메시지는 AgentRunner.run 시작 즉시(루프 진입 전) 먼저 append_messages로 커밋하고,
  (b) 각 tool 턴이 끝날 때마다(전체 루프 종료를 기다리지 않고) 증분 커밋하도록 바꾼다. 그러면 중단
  지점까지의 실제 실행 결과(생성된 page_id 포함)가 히스토리에 남아, 재요청 시 모델이 "직전에 이미
  생성됨"을 인지하고 중복을 피할 수 있다.

- **[C2] 세션 히스토리 40개 절단이 단순 개수 기준(FIFO)이라 tool_calls/tool_result 쌍을 끊을 수 있다**
  — §2.2 DDL 주석, §3.3 `AgentRunner.run` 1번("세션당 최근 40개 중립 메시지 — 초과분은 오래된 것부터
  절단"), §5.3("히스토리 40개 초과 절단 시에도 시스템 프롬프트는 항상 온전히 재주입").
  한 번의 사용자 요청이 tool 호출을 포함하면 user 1 + (assistant+tool_calls, tool결과)×N + 최종
  assistant로 쉽게 5~10개 메시지를 소비한다. 활발히 쓰는 스레드는 4~8회 왕복만으로 40개를 넘길 수
  있어 M1 실사용 범위에서 드문 경우가 아니다. 단순 "오래된 것부터 잘라내기"는 assistant의
  `tool_calls`만 남고 그에 대응하는 `role:"tool"` 결과가 잘려나가거나, 반대로 `tool_call_id`가 가리키는
  이전 assistant 메시지가 잘려나간 상태로 남을 수 있다. 이 상태로 다음 요청을 처리하면:
  - OpenAI Chat Completions는 tool 메시지가 대응하는 assistant `tool_calls` 없이 오면 400 오류를 낸다.
  - Anthropic Messages API는 `tool_use`/`tool_result` 짝이 안 맞거나 대화가 `user`로 시작하지 않으면
    오류를 낸다.
  결과적으로 **정상 사용 중에 세션이 영구적으로 손상**되고(재시작으로도 복구 안 됨 — 손상된 히스토리가
  DB에 그대로 남아있으므로), 매 후속 요청이 E1/E6로 실패하게 된다.
  제안: 절단을 메시지 개수가 아니라 "요청(턴) 단위"로 하거나, 절단 시 히스토리 앞부분에서
  미완결 tool_calls/tool_result 쌍이 남지 않도록(짝이 안 맞으면 그 턴 전체를 통째로 버리도록) 명시.

- **[C3] 스레드 생성 자체가 실패하면 실패를 보고할 곳이 없다 — 불변 제약 6 위반 가능** —
  §2.1 송신 규칙("모든 응답은 세션 스레드 안에서만. 원 채널에는 쓰지 않는다"), §4.2, §5.1, §5.5.
  `message.create_thread()`는 권한 부족(Create Public Threads 미승인), 채널당 활성 스레드 한도,
  Discord 일시 장애 등으로 실패할 수 있다(리뷰 포커스의 "Discord API 실패(스레드 생성 불가 등)").
  그런데 §2.1은 원 채널에 절대 쓰지 않는다는 절대 규칙이고, 실패 메시지(§5.5)는 전부 "스레드에" 보내는
  것을 전제로 정의돼 있다. 스레드 생성이 실패한 시점에는 보낼 스레드가 존재하지 않으므로, 트리거
  조건은 충족했는데(A/B) **사용자에게 원인 요약도 대안도 전혀 전달되지 않는 완전한 무응답**이 된다.
  이는 브리프 불변 제약 6("실패 시 원인 요약 + 대안 제시")을 정면으로 위반한다.
  같은 계열 문제로, §5.1의 `on_message → triggers.decide(...)` 단계에서 예외가 나는 경우(예: 세션
  조회 중 DB 오류)도 아직 스레드/handler 진입 전이라 동일하게 보고 경로가 없다. §6 파일 표 어디에도
  이 두 케이스(스레드 생성 전 단계 예외)를 처리하는 책임 소재가 없다.
  제안: 스레드 확보 실패·트리거 판정 실패는 예외적으로 원 채널에 실패 리액션(예: ⚠️) + 최소한의
  DM(스터디장 등)/로그로라도 알리는 "스레드 이전 단계 전용" 에러 경로를 §5.5에 별도 항목(E7 등)으로
  추가하고, `on_message` 전체를 감싸는 최상위 try/except의 책임을 `bot/client.py`에 명시할 것.

- **[C4] `ToolDispatcher.write_count`(요청당 쓰기 3회 상한)의 리셋 시점/스코프가 스펙에 없다 —
  대량 변경 차단(§4.4 L2)이 무력화되거나 오작동할 수 있다** — §4.4, §6 `agent/tools.py` 인터페이스
  (`class ToolDispatcher: __init__(gateway), write_count: int (요청당 리셋)`).
  §3.3 (5)는 "서로 다른 스레드는 병렬"로 명시적으로 동시 처리를 허용한다. `NotionGateway`는
  `AsyncClient` 연결을 감싸므로, 요청마다 새로 만들기보다 봇 수명 동안 하나의 `NotionGateway`/
  `ToolDispatcher`를 공유하는 것이 자연스러운 설계다(연결 재사용). 그런데 §6 인터페이스에는
  `reset()` 메서드도, "AgentRunner가 매 요청마다 새 ToolDispatcher를 만든다"는 명시도 없다.
  - 만약 `ToolDispatcher`가 공유 싱글턴이면: 서로 다른 스레드의 두 요청이 동시에 진행될 때
    (§3.3 (5)가 허용) `write_count`라는 단일 가변 정수를 공유·경합하게 되어, 한쪽 요청의
    "요청 시작 시 0으로 리셋"이 다른 쪽 요청의 진행 중이던 카운트를 지워버리는 레이스가 가능하다
    — 이 경우 한 요청이 상한 3회를 넘는 쓰기를 수행할 수 있어 §4.4가 의도한 "대량 변경의 정량 차단"이
    깨진다.
  - 리셋 로직을 안 만들고 그냥 두면 정반대로, 봇이 재시작하기 전까지 **전체 수명 동안 총 3회**로
    영구 캡핑되어 4번째 요청부터 정상적인 단일 쓰기 요청도 전부 거부되는 심각한 가용성 버그가 된다.
  제안: `write_count`를 `ToolDispatcher`의 인스턴스 필드가 아니라 매 `AgentRunner.run()` 호출마다
  새로 만드는 로컬 카운터(또는 `run()`에 넘기는 요청 스코프 객체)로 설계를 바꾸고, `ToolDispatcher`
  자체는 무상태로 만들거나 명시적 `dispatch(call, write_count_ref)` 형태로 스코프를 요청 단위로
  강제할 것.

- **[C5] Notion date payload에 타임존 정보가 전혀 없어 일정 시간이 실제와 어긋날 위험** —
  §2.5 "속성 payload 형태 — date: `{"date": {"start": "2026-07-23T19:00"}}` (시간 없으면
  `"2026-07-23"`)", §5.6 point 2(Asia/Seoul 기준 상대 날짜 계산), OQ7(타임존 Asia/Seoul 고정).
  스펙 전체가 "사용자가 말한 시각 = Asia/Seoul 로컬 시각"이라는 전제 위에 세워져 있는데, 실제
  Notion API에 보내는 date 속성 payload에는 UTC 오프셋도 없고 `time_zone` 필드도 없다. Notion
  date 속성은 오프셋이 없는 datetime 문자열이 오면 `time_zone` 필드가 없는 한 UTC로 해석한다
  (offset-naive datetime + time_zone 필드 부재 = UTC 취급). 이 경우 "저녁 7시로 잡아줘"가
  `"2026-07-23T19:00"`(오프셋 없음)으로 전송되면 Notion에는 UTC 19:00으로 기록되고, 팀이 보는
  화면(KST, UTC+9)에는 다음날 새벽 4시로 표시된다 — **핵심 기능(일정 생성)의 시간이 매번 9시간
  밀리는 구조적 버그**다. 회의 시간을 다루는 이 봇에서 가장 치명적인 사용자 체감 결함이 될 수 있다.
  제안: date payload에 `"time_zone": "Asia/Seoul"`을 명시적으로 추가하거나(Notion date 속성이
  지원하는 필드), 아니면 저장 전 `+09:00` 오프셋을 문자열에 직접 붙인다. 어느 쪽이든 §2.5 payload
  예시를 수정하고, §7 `test_notion_api.py`의 `build_properties` date 케이스에 타임존 필드/오프셋
  존재를 검증하는 단언을 추가해야 한다. (정확한 Notion API 기본 동작은 §7 S2 스모크에서 재확인
  가능하나, mock 기반 단위 테스트만으로 통과되는 현재 스펙 상태로는 이 결함이 구현 완료 시점까지
  발견되지 않는다.)

## Important (should fix)

- **[I1] Notion 조회 결과 파싱(읽기 방향) 함수의 소유자가 없다** — §2.3 툴 반환 스키마
  (`query_schedule`/`query_tracker`의 `results` 배열이 "모임명","날짜","유형" 등 평탄화된 한국어
  키를 요구), §2.5, §6 `agent/notion_api.py` 인터페이스(`build_properties`는 쓰기 방향만 정의).
  Notion API가 실제로 돌려주는 페이지 속성은 `{"모임명": {"type":"title","title":[{"plain_text":...}]}}`
  같은 타입별 중첩 객체다. 이를 툴 계약이 약속하는 평탄한 문자열 값으로 변환하는 함수(rich_text
  세그먼트 결합, select→name 추출, multi_select→리스트, date→start만 취할지 등)가 §6 파일별
  공개 인터페이스 어디에도 없다. `NotionGateway.query() -> list[dict]`의 반환 타입이 raw Notion
  객체인지 이미 평탄화된 dict인지도 불명확하다. 동일하게 `query_schedule`/`query_tracker`의
  `status`/`date_from`/`date_to`/`keyword`/`member` 인자를 Notion `filter` JSON으로 조립하는
  함수도 owner가 없다(쓰기 방향의 `build_properties`에 대칭되는 읽기 방향 함수가 빠짐).
  제안: `agent/notion_api.py`에 `def build_filter(...)`, `def parse_page_summary(page: dict, schema: dict) -> dict` 같은 함수를 §6 인터페이스 표에 명시적으로 추가.

- **[I2] Anthropic 변환 시 여러 tool 결과를 하나의 user 턴으로 병합해야 한다는 지시가 불명확** —
  §2.4 "Anthropic 변환: ... tool → 다음 user 메시지의 tool_result block."
  한 assistant 턴이 여러 `tool_calls`를 만들면(§3.3 "tool_calls 있으면 각각 디스패치(순차 실행)")
  결과는 히스토리에 `role:"tool"` 메시지 여러 개로 개별 저장된다. Anthropic Messages API는 이
  여러 tool 결과를 **하나의 user 메시지 안에 여러 `tool_result` content block**으로 넣어야 하며,
  탈출구로 별도 user 메시지를 연달아 보내면(연속 user 메시지) 형식 오류 또는 예상 밖 처리가 된다.
  "다음 user 메시지의 tool_result block"이라는 문구만으로는 구현자가 이를 여러 개의 개별 user
  메시지로 1:1 오구현할 위험이 있다.
  제안: §2.4에 "동일 assistant 턴에서 나온 연속된 tool 메시지는 Anthropic 변환 시 하나의 user
  메시지로 병합해 여러 tool_result 블록을 담는다"를 명문화하고 `test_providers.py`에 다중
  tool_calls 케이스를 추가.

- **[I3] "빈 요청" 처리 경로가 "스레드 전용 응답" 규칙과 충돌한다** — §2.1 "빈 요청" 행,
  §6 `TriggerDecision(kind: Literal["ignore","new_request","follow_up"])`.
  멘션만 있고 본문이 빈 메시지가 왔을 때 "무엇을 도와드릴까요?" 안내를 보내야 하는데, 이게
  NEW_REQUEST로 분류돼 스레드까지 생성한 뒤 그 안에서 답하는 것인지(빈 본문으로 스레드 이름이
  "📝 "만 남는 어색한 스레드가 생김), 아니면 스레드 생성 없이 원 채널에 바로 답하는 것인지(§2.1
  "원 채널에는 쓰지 않는다" 규칙 위반) 스펙에 없다. `TriggerDecision.kind`에도 별도 값이 없다.
  제안: 빈 요청 전용 kind(예: `"empty"`)를 추가하고, 스레드를 만들지 않고 원 메시지에 대한 답글
  (reply)로 안내만 보내는 것으로 §2.1/§6을 명확히 할 것.

- **[I4] `Settings.llm_provider` 필드의 실제 역할이 D6 폴백 규칙과 연결되지 않는다** —
  §6 `config.py` Settings(`llm_provider` 필드 존재), §3.3 D6("OpenAI → Anthropic 요청당 1회 폴백"
  고정 방향).
  `.env.example`은 `LLM_PROVIDER=openai|anthropic`을 사용자가 선택 가능한 값으로 문서화하는데,
  스펙의 AgentRunner/폴백 로직은 "OpenAI가 항상 primary, Anthropic이 항상 fallback"을 하드코딩된
  전제로 삼는다. `LLM_PROVIDER=anthropic`으로 설정되면 primary/fallback이 뒤바뀌어야 하는지,
  아니면 이 필드가 현재는 사용되지 않는 죽은 설정인지 §6/§3.3 어디에도 답이 없다.
  제안: `main.py`에서 `settings.llm_provider` 값에 따라 `AgentRunner(primary=, fallback=)`를 어떻게
  구성하는지 한 줄로 명시(예: "M1은 항상 openai를 primary로 고정하고 llm_provider 필드는 향후 확장을
  위한 자리만 잡아둔다" 등).

- **[I5] "되묻기" 응답에 시각적 마커가 정의돼 있지 않다** — §5.4, §5.6 point 8.
  §5.6 point 8은 성공(✅)과 실패(원인+대안)의 보고 형식만 정의하고, §4.4는 미지원 안내를 ℹ️ 톤으로
  하라고 명시하지만, "되묻기"(tool_calls 없는 중간 질문, §5.4)에 대한 이모지/톤 지침은 어디에도
  없다. 리뷰 포커스가 요구하는 "성공/실패/되묻기의 시각적 구분"이 되묻기 쪽에서 비어 있다.
  제안: §5.6 point 8에 "되묻기 시에는 ❓ 로 시작하라" 같은 규칙을 추가.

- **[I6] 스레드별 `asyncio.Lock`을 `AgentRunner.run()` 전체(히스토리 로드~커밋) 동안 보유해야
  한다는 점이 §5.1 순서 나열로만 암시되고 §6 인터페이스에 명문화돼 있지 않다** — §3.3 (5),
  §5.1, §6 `bot/handler.py`.
  "handler: thread_lock 획득" 다음에 "AgentRunner.run(...)"이 나열돼 있어 락을 실행 전체 동안
  쥐는 것으로 읽히지만, 명시적 서술이 없어 "락 획득만 하고 바로 해제 후 실행"으로 오구현될 위험이
  있다. 그 경우 같은 스레드 연속 메시지의 히스토리 로드/저장이 인터리빙되어 C1/C2와 결합해 데이터
  손상으로 이어진다.
  제안: `RequestHandler.handle()`의 락 보유 범위를 "세션 로드 시작부터 히스토리 커밋 완료까지"로
  §3.3/§6에 한 문장 명문화.

## Minor (nice to have)

- **[M1] 스레드 이름 규칙의 "100자 초과 시 절단" 조항이 사실상 도달 불가능한 죽은 문구** — §2.1.
  "앞 80자"로 이미 잘라낸 뒤 "📝 " 접두(2자)를 붙이면 최대 82자로, 100자 초과 케이스가 발생하지
  않는다. 문구 정리 또는 실제 절단 기준을 하나로 통일 권장.

- **[M2] `minutes`(소요 시간) 0~240 상한이 Notion UI ring 표시 관례를 그대로 하드 비즈니스 규칙화한
  것으로 보인다** — §2.3, `workspace_map.json`의 "ring 표시, max 240" 주석.
  Notion number 속성 자체는 240을 초과하는 값을 거부하지 않는다(단지 ring 시각화가 240에서
  멈출 뿐). 240분(4시간)을 넘는 정당한 학습 기록(예: 주말 5시간 몰입)을 디스패처가 `ok:false`로
  거부하면 사용자가 실제 값을 축소해 보고해야 하는 부자연스러운 UX가 생긴다. 상한을 유지할지,
  단순 경고로 낮출지 확인 필요.

- **[M3] 스레드별 `asyncio.Lock` 딕셔너리의 정리(clean-up) 시점이 스펙에 없다** — §3.3, §6
  `bot/handler.py`. M1 규모(5인, 소규모 스레드 수)에서 실질 영향은 미미하지만, 봇 프로세스가
  오래 떠 있을수록 스레드 수만큼 Lock 객체가 누적된다는 점을 명시해 두는 편이 좋다.

- **[M4] 다중 tool 턴 처리 중 중간 진행 상황이 사용자에게 전혀 노출되지 않는다** — §5.1, §5.6.
  `thread.typing()` 표시 외에, "일정을 만들게요" 같은 중간 assistant 텍스트(§2.4 예시에 등장)는
  최종 응답 전까지 사용자에게 보이지 않는다. 최대 300초까지 걸릴 수 있는 처리에서 타이핑 표시만
  지속되는 것은 (기능적 결함은 아니나) 체감 대기 시간을 늘린다. M1 범위 밖 개선으로 기록만 남김.

## Questions for the CTO

- **[Q1]** C5(Notion date payload 타임존 누락)는 실제 Notion API 기본 동작(오프셋 없는 datetime을
  UTC로 처리하는지)을 §7 S2 스모크 테스트 전에는 100% 확증할 수 없다. 그러나 이 항목의 수정 비용이
  낮고(payload에 필드 하나 추가) 잘못됐을 때 피해가 크므로(모든 일정이 9시간 밀림), 스펙 승인 전에
  `time_zone: "Asia/Seoul"` 필드를 기본으로 추가하는 방향으로 확정해도 되는지 확인 요청.
- **[Q2]** C4(`write_count` 스코프)와 관련해, `NotionGateway`/`ToolDispatcher`를 요청마다 새로
  생성(연결 재사용 포기, 단순하지만 약간 비효율)할지, 아니면 공유 인스턴스 + 명시적 요청 스코프
  카운터로 갈지 아키텍처 방향 결정 필요.
- **[Q3]** C1(부분 실행 결과의 히스토리 미반영)에 대해 "증분 커밋"(턴마다 저장)으로 바꾸면 §3.3의
  "원자적으로 커밋" 문구와 성능/일관성 트레이드오프가 생긴다(SQLite 쓰기 빈도 증가는 M1 규모에서는
  무시할 수준). 이 방향 전환에 동의하는지, 아니면 다른 완화책(예: 재요청 시 "직전 시도에서 부분
  실행됐을 수 있다"는 경고를 프롬프트에 추가하는 수준의 완화)으로 충분한지 판단 요청.
