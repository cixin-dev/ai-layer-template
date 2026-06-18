# Plan: Comprehension at the Boundary（誤路由修正 + 繁中理解關卡）

> **English TL;DR (for future sessions):** This is a System Evolution / retroactive patch
> fixing two failure modes: (1) `grill-with-docs` was being used as a cold-start feature
> entry point, silently inflating canonical docs on each use; (2) there was no mechanical
> floor ensuring the author could comprehend canonical doc changes. Fix: routing contract
> in `CLAUDE.md` (grill-with-docs cold-start forbidden), CI gate requiring a Traditional
> Chinese `## 變更說明` section in any PR touching `CONTEXT.md` or `docs/adr/`, and
> `strategic-planning` skill updated to narrate inline captures in TC before writing.
> See ADR-0022 for the decision record. The rest of this file is written in Traditional
> Chinese per the principle it proposes (TC prose stays ephemeral; this archived plan is
> an intentional exception and carries this English header for future-session access).

> 這是一次 **System Evolution / retroactive** 修補（`/retroactive` 的 Phase 4：Apply and
> record）。Phase 1–3（Diagnose / Locate the gap / Propose）已在一次 grill 中完成，本檔是其
> durable 產出。**散文用繁中、canonical 詞與 code 用英文**——本檔本身就在 dogfood 它所提議的
> 原則。

## Summary

修一個 class of problem：**`CONTEXT.md` 與多份 ADR 膨脹到（繁中母語的）作者無法掌握**。根因不是
「文件太多」，而是**進錯門**——作者把重型的 `grill-with-docs` 當成每個 feature idea 的入口，每次
都觸發一輪 canonical 文件重寫；而 harness 的 affordance 又裝反了（`strategic-planning` 是
`disable-model-invocation: true`、不會自動喚起，`grill-with-docs` 卻會），等於 harness 自己把人帶
去錯的門。理解無聲衰減後，作者從 *author* 被降級成 *看不懂的 reviewer*。

修法兩半，且**不對稱**：
1. **Routing（prose floor，被迫）**——`CLAUDE.md` 立一條路由契約：feature idea 一律走
   `strategic-planning`；`grill-with-docs` 只能由 escalation handoff 喚起，**禁止冷啟動**。
2. **Comprehension（deterministic floor，能上就上）**——canonical 文件留英文（保護 Ubiquitous
   Language 不漂移）；給人看的繁中**只活在 ephemeral 表面**（對話敘述 + PR body），**絕不持久化進
   canonical 文件**（那會重造「第二份會漂移的真相」，正是英文鐵律當初要避免的）。任何碰 canonical
   文件的 PR，body 強制要有非空的繁中「變更說明」，由 CI 擋。

## User Story

As the（繁中母語的）harness 作者，I want 新功能想法自動走對的入口、且任何 canonical 文件改動都在我
母語的 PR body 上說明，so that 文件不再無聲膨脹、我能重新讀懂並指揮自己的系統，且不犧牲詞彙零漂移。

## Metadata

| Field | Value |
|-------|-------|
| Type | REFACTOR（Harness / AI Layer 修補） |
| Complexity | MEDIUM |
| Systems affected | `CLAUDE.md`、`.claude/skills/strategic-planning/`、`.github/workflows/ci.yml`、`scripts/`、`docs/adr/` |
| Issue | N/A（retroactive，直接 plan） |
| Originating class of problem | 重型 alignment 工具被當 feature 入口 → canonical 文件無聲膨脹 → 作者理解/作者權喪失 |

## 設計決策（grill 結論，依賴順序）

1. **痛點分層**：A=誤路由（主因）、D=缺理解關卡（放大器）、B=作者權反轉（A+D 的後果）。**不走 C
   （整套方法論瘦身）**。
2. **誤路由根因 = B-reason**：升級判準（lone term vs 衝突詞團）需要熟記整份 glossary 才判得出來，
   而那正是作者失去的能力——所以理性外包給重型工具。**設計上這個判斷本就該由 agent 做**（它 fresh
   讀 `CONTEXT.md`、能暫存全貌），人只需 brain-dump。
3. **核心原則**：詞留英文（零漂移）；解釋散文可繁中，但只在可重生/用過即丟的表面（對話、PR body），
   **絕不寫進 canonical 文件**。
4. **理解關卡（D）依改動輕重分流**：
   - 輕量 inline 收詞 → agent 在對話用繁中講一句、人點頭即收（搭 feature PR 的順風車）。
   - 重型 `grill-with-docs` 升級 → 走專屬 PR，body 用繁中寫清楚動了哪些詞、為什麼。
   - **CI floor 對兩者統一適用**：任何碰 canonical 文件的 PR 都要繁中說明；輕重只決定搭順風車 PR
     還是專屬 PR。
   - **否決 `CONTEXT.zh.md`**：那等於做出最怕的第二份會漂移真相。「隨時讀懂舊文件」是一個*能力*
     （需要時叫 agent 用繁中解釋、用完即丟），不是一份庫存檔。
5. **不能動 `grill-with-docs`**：ADR-0004——它的產出 glossary-consistent，stays upstream, not
   vendored。修法只能落在我們擁有的表面：`CLAUDE.md`、`strategic-planning` skill、它升級時自己發出
   的 handoff（繁中契約注入 `grill-with-docs` session 的唯一接縫）。
6. **enforcement 不對稱**：能機械化的上 deterministic floor（繁中 PR 段落 → CI），只能 prose 的才
   prose（routing → `CLAUDE.md`，沒有「skill 被喚起」的 hook 可攔）。複製專案既有的 `validate
   gate`（機械 floor）+ `tdd-gate`（語意紀律）刀法。**否決「先全 prose、復發再補」**——prose-decay
   是*已證實*的失敗模式（我們就是被它埋的），不是臆測，故 simplicity-first 不適用。

## Assumptions & Risks

| Claim | VERIFIED / ASSUMED | Evidence / mitigation |
|-------|--------------------|-----------------------|
| `strategic-planning` 是 `disable-model-invocation: true`、`grill-with-docs` 無此限制（affordance 反裝） | VERIFIED | 讀 `.claude/skills/strategic-planning/SKILL.md:4`；`grill-with-docs` frontmatter 無此鍵 |
| `strategic-planning` 已含正確路由邏輯（inline vs escalate） | VERIFIED | `SKILL.md:50-67` Alignment checkpoint |
| `grill-with-docs` 為 upstream、不可 fork（除非污染 glossary） | VERIFIED | ADR-0004；它只在 `~/.claude/skills` 不在本 repo |
| ci.yml 跑在 `pull_request` 上，可延伸 | VERIFIED | `.github/workflows/ci.yml`：`on: pull_request` + 既有 `*.test.sh` job |
| `pull_request` 事件可讀到 PR body 供 CI 檢查 | ASSUMED | `github.event.pull_request.body`（標準）；Implement 首步以一個 test PR 證實，或退為 risk |
| GNU `grep -P` 的 CJK 範圍 `[\x{4e00}-\x{9fff}]` 可機械判「有無繁中」 | ASSUMED | CI `runs-on: ubuntu-latest`（GNU grep）；本機 test 同跑於 CI。非 Linux 開發機跑 test 可能無 `-P`——於 test 標註 |
| escalation `handoff` 能夾帶自訂契約文字進 `grill-with-docs` session | ASSUMED | Implement 先讀 `handoff` skill 確認其接受 free-form 內容（handoff 定義即「transfer a task 的文件」，幾乎必然可） |
| `grill-with-docs`（不可改）會*遵循* handoff 注入的「用繁中、走 PR」指示 | ASSUMED（不可 floor） | 這是 prose 紀律的固有殘餘風險，與 Q6 結論一致——narration 品質永遠留 prose。接受為 residual risk |
| 冷啟動 `grill-with-docs` 只能靠 `CLAUDE.md` prose 攔（無 hook） | ASSUMED（不可 floor） | 與 Q5 結論一致，接受 |

## Files to Change

| File | Action | Purpose |
|------|--------|---------|
| `scripts/doc_change_gate.sh` | CREATE | 純函數式 gate 邏輯：碰 canonical 文件的改動 → PR body 必須有非空繁中「變更說明」 |
| `scripts/doc_change_gate.test.sh` | CREATE | 以 fixtures 測 gate 邏輯，mirror 既有 `*.test.sh` assert 風格 |
| `.github/workflows/ci.yml` | UPDATE | (a) 既有 `test` job 加跑 `doc_change_gate.test.sh`；(b) 新增 `pull_request`-only 的 gate step，餵 changed-files + PR body 給 gate script |
| `.claude/skills/strategic-planning/SKILL.md` | UPDATE | inline capture 前用繁中敘述待確認；escalate 的 handoff 夾帶「繁中 + 走 PR」契約 |
| `CLAUDE.md` | UPDATE | （精簡）路由契約 + 一行繁中-comprehension 契約；順帶提交現有未提交的 `## Communication` 段落 |
| `docs/adr/0022-comprehension-at-the-boundary.md` | CREATE | 記錄此決定 |

## Tasks

> 順序 = retroactive 的 Dimension 0（gate 先）→ prose dimensions → record。第 1 任務是可 TDD 的
> 垂直 tracer bullet。

### Task 1：CI comprehension floor（deterministic gate，TDD）
- File: `scripts/doc_change_gate.sh`（CREATE）、`scripts/doc_change_gate.test.sh`（CREATE）、`.github/workflows/ci.yml`（UPDATE）
- Action: 先寫 test（red）再寫 gate（green）
- Implement:
  - `doc_change_gate.sh <changed-files-file> <pr-body-file>`：
    - canonical 判定：changed file 命中 `^CONTEXT\.md$` 或 `^docs/adr/`。
    - 無命中 → exit 0（gate 不適用）。
    - 有命中 → PR body 須同時 (i) 有標題 `^#{1,6}\s*變更說明` 且 (ii) 含 CJK 字元
      （`grep -P '[\x{4e00}-\x{9fff}]'`）→ exit 0；否則 exit 1 + 中英雙語錯誤訊息。
  - `doc_change_gate.test.sh` 覆蓋：①無 canonical 改動→pass ②`CONTEXT.md`+合格繁中 body→pass
    ③`CONTEXT.md`+空 body→fail ④`docs/adr/*`+純英文 body→fail ⑤`docs/adr/*`+合格 body→pass。
  - `ci.yml`：既有 `test` job 的 script 末加 `bash scripts/doc_change_gate.test.sh`；新增
    `pull_request`-only step（`if: github.event_name == 'pull_request'`），用
    `git diff --name-only origin/${{ github.base_ref }}...HEAD` 取 changed files、
    `env: PR_BODY: ${{ github.event.pull_request.body }}` 取 body，呼叫 gate script。
- Mirror: `scripts/piv_check.test.sh`、`scripts/validate_gate.test.sh`（assert/harness 風格）；
  `.github/workflows/ci.yml`（既有 job 結構）
- Validate: `bash scripts/doc_change_gate.test.sh` 全綠

### Task 2：strategic-planning skill — 繁中關卡 + handoff 契約
- File: `.claude/skills/strategic-planning/SKILL.md`
- Action: UPDATE（外科式，動 Alignment checkpoint 區塊）
- Implement:
  - **Inline capture**（`SKILL.md:54-56`）：寫入 `CONTEXT.md` 前，先用**繁中**向使用者敘述
    「要加哪個詞、意思、為什麼」，待點頭再寫。
  - **Escalate**（`SKILL.md:58-64`）：步驟 2「Emit a handoff」要求 handoff **夾帶契約**：該
    `grill-with-docs` session 對使用者的 narration 用繁中、文件改動走 PR、PR body 用繁中寫明動了
    哪些詞與原因。
- Mirror: 既有區塊語氣（祈使、精簡）
- Validate: 人工 review；改動為 prose，靠 validate gate 收尾

### Task 3：CLAUDE.md — 路由契約 + 繁中契約（保持精簡）
- File: `CLAUDE.md`
- Action: UPDATE（最小增量；包含現有未提交改動：`## Communication` 段落，一併帶入 feature branch）
- Implement: 於 `### Project specifics` 的 **Do-not** 增兩條（措辭極省）；並確認 `## Communication` 段落（當前 main 未提交）已在 worktree 中：
  - 路由：「新功能想法一律先進 `strategic-planning`（brain dump）；`grill-with-docs` 只能由
    `strategic-planning` 的 escalation handoff 喚起，**禁止當 feature 入口冷啟動**——那正是淹沒
    glossary 的誤路由。」
  - 繁中契約：「Canonical 文件（`CONTEXT.md`、ADR）為英文；每次改動都要在 PR body（及 inline 收詞
    時於對話）用繁中說明，**絕不把繁中翻譯持久化進 canonical 文件**。」
- Mirror: 既有 Do-not 條目格式（一句 + 括號註 retroactive 出處）
- Validate: 人工 review；確認 `CLAUDE.md` 仍在 ~2.5k token 預算內

### Task 4：ADR-0022 — 記錄決定
- File: `docs/adr/0022-comprehension-at-the-boundary.md`
- Action: CREATE
- Implement: 標題「Comprehension at the boundary: canonical docs stay English; the human layer
  is Traditional Chinese and ephemeral」。內容：
  - **Context**：英文鐵律（防詞漂移）被過度套用到所有散文；`grill-with-docs` 經誤路由自動增寫；作者
    被降級為看不懂的 reviewer。
  - **Decision**：詞英文；繁中理解層只在 ephemeral 表面（對話 + PR body）；不對稱 enforcement（繁中
    PR 段落上 CI floor、routing 留 prose）。
  - **Rejected**：bilingual `CONTEXT.md`（膨脹+漂移）、持久化 `CONTEXT.zh.md`（第二份會漂移的真相
    ——正是英文鐵律要避免的）、廢除英文鐵律（失去詞的零漂移）。
  - **Consequence**：作者在 change-time（繁中 PR body）與 on-demand（叫 agent 繁中解釋）重獲理解，
    且無第二份持久翻譯。
- Mirror: 任一現有 ADR 的結構（如 `docs/adr/0020-*.md`）
- Validate: Task 1 的 gate 此時應對「本 PR 含 `docs/adr/0022`」生效——本 PR 自己的 body 就必須有繁中
  變更說明（dogfood）

## Validation

- `bash scripts/doc_change_gate.test.sh`（新）+ 既有 `validate.sh` 全套綠。
- E2E：①開一個碰 `CONTEXT.md`、body 無繁中的測試 PR → CI 紅；補繁中變更說明 → CI 綠。②`strategic-
  planning` 跑一次：新詞被繁中敘述後才寫入；製造一個衝突詞團 → 確認它走 handoff 升級（且 handoff 含
  繁中契約）而非 inline。
- 本 PR 自身即 dogfood：它碰 `docs/adr/`，故其 body 必須有繁中「變更說明」段落，否則被自己的新 gate
  擋下。

## Acceptance Criteria

- [ ] All tasks completed
- [ ] `doc_change_gate.test.sh` 與既有 checks 全綠、零錯誤
- [ ] 遵循既有 pattern（`*.test.sh` 風格、ADR 結構、Do-not 條目格式）
- [ ] 每個 external-behavior 主張皆 VERIFIED 或列為明確 risk（見上表）
- [ ] E2E：誤路由被擋、繁中 floor 對碰 canonical 文件的 PR 生效
- [ ] `CLAUDE.md` 仍精簡（~2.5k token 內）

## 流程備註（給 implement / validate session）

- 本修補橫跨 4 面，**走 branch + PR**，禁止直接 commit 到 local `main`（CLAUDE.md Do-not）。
- 依 ADR-0014，plan 為 branch 首個 commit；implement 結束**留 plan 於 `.agents/plans/`** 供
  `/validate`，archiving 到 `completed/` 是 Validate 綠燈後的事，非 implement 的事。
- commit message 說明 originating class of problem（retroactive 慣例）。

## Out of scope（follow-ups，不擋主線）

- (i) `strategic-planning` 的 `disable-model-invocation` 該不該翻（Q5 暫緩；需先查清它被 disable 的
  原因，可能是刻意防 persona 劫持對話）。
- (ii) 「隨時讀懂舊文件」升成 `/explain-zh` command——做滿三次再升（CLAUDE.md「prompt 同件事 >3 次
  才 promote」）。
- (iii) light capture 繁中敘述的詳略度，留待實作手感校準。
