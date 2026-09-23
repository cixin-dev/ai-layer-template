# Matt `pr` / `retro` skill 評估 — 延後接入

**評估日期：** 2026-09-23
**Upstream：** `mattpocock-skills` @ `c55ee46`（兩個 skill 都在 `skills/in-progress/`）
**狀態：** 延後，**還不是 plan**。等 upstream 正式化再開 `/plan`。

## 一句話結論

- **`pr` → `/validate` Phase 5：** 適合，技術上可行。只差 upstream 還在 beta。
- **`retro` vs `/retroactive`：** 兩者定位不同，**不互相取代**。retro 最有價值的是幾個「刪減」角度，之後可以挑進 `/retroactive`，不必整個 link。

## 什麼時候重新拿出來看

每次 pull `mattpocock-skills` 之後，看兩個 skill 在哪個 bucket：

```bash
ls <checkout>/skills/*/pr/SKILL.md <checkout>/skills/*/retro/SKILL.md
# 2026-09-23 實測 → skills/in-progress/pr/SKILL.md、skills/in-progress/retro/SKILL.md
```

離開 `in-progress/`（upstream README：「can change or disappear without warning」）就是觸發點。
retro 另外要等 `in-progress/README.md` 拿掉「**STUB: design notes only, not functional yet**」。

---

## 1. `pr` skill 接進 `/validate`

### 可行性

- **model-invoked**（沒有 `disable-model-invocation`），可以用 Skill tool 呼叫；本身沒有 Skill 依賴，link 後 freshness check (f) 會是綠的。
- **一定要 link 到 user scope。** Night Shift 會在背景跑 `/validate`（`scripts/night_shift_run.sh:198`），沒 link 的話這一步在背景不會發生，也沒有任何提示。

### 段落對照

| `pr` 模板段落 | 現在的 Phase 5 PR body | 接進來的好處 |
|---|---|---|
| Summary（pseudocode / diff / tree 圖示變更） | 只貼 plan `## Summary` 的文字 | reviewer 一眼看懂改了什麼形狀 |
| Evidence（before / after） | Phase 4 結果區塊已經有 | 幾乎直接對上；Phase 3.5 的 known-good / known-bad 就是現成 before/after |
| Merge Danger（單向門 / 雙向門 + blast radius） | 沒有 | **最大收穫**。cron、hook copy、user-scope symlink 常是單向門 |

### 必守（模板裡沒有，接入時要明寫「我們的段落優先」）

- `## 變更說明`（繁中，每個 PR 都要；CLAUDE.md Do-not、ADR-0022）
- `## Report` 路徑
- `Closes #N`（plan 有 Issue 時）

### 為什麼先不接

- 還在 `in-progress/`；進 `in-progress/` 後兩天內（2026-09-17～18）就有 8 個 commit 在改模板（`4cfa4cd`…`c55ee46`）。
- README 描述的段落（「what was left out on purpose」）跟目前 SKILL.md 對不上，upstream 自己還沒定案。
- symlink（ADR-0007）會自動跟著 upstream 改，PR 格式可能在沒人注意時變掉。
  （PR body 寫壞很好修，本身是雙向門，所以這不是擋路理由，只是等穩定比較省事。）

### 接入草案（給之後的 `/plan` 當起點）

1. Link `pr` 到 `~/.claude/skills/`。
2. `/validate` Phase 5 改成 `Call the Skill tool with "pr"` 產 body，再加上上面三個必守段落。
3. E2E：headless 跑一次 `/validate`，確認 skill 真的有觸發，PR body 同時有 Merge Danger 和 `## 變更說明`。

---

## 2. Matt 的 `retro` vs `/retroactive`

比喻：**`/retroactive` 像事故調查**，出事了才查，目標是這類問題不再發生，結論直接改進規章。**retro 像健康檢查**，每次跑完都能做，目標是下次跑得更順，只開建議清單，不動手改。

| | retro | `/retroactive` |
|---|---|---|
| 什麼時候用 | 任何 session 結束後，成功的也可以 | bug 進了 codebase、或漏抓了問題 |
| 讀什麼 | session log（agent 實際怎麼找檔、呼叫了哪些工具） | bug 或報告（錯在哪） |
| 輸出 | 依嚴重度排序的建議，**不套用** | 診斷 → 找缺口 → **在 `retroactive/` branch 上改好並 commit** |
| 方向 | 可以**刪減**（No-ops、搬走太肥的 steering 內容） | 幾乎只會**增加**（加 check、加 Do-not） |

### 已經收斂的部分

upstream `0243b6e`（2026-09-15）：「機械性的錯誤一律做成 deterministic check，judgement 類才寫成規則」≈ 我們的 **Dimension 0**。
「check 已經存在但沒接上、或壞了卻沒人發現，這件事本身就是 finding」≈ #96 和 freshness gate 學到的教訓。

### retro 有、我們沒有的角度（值得之後挑進來）

- **No-ops**：規則寫了但對 agent 行為沒影響
- **Global AGENTS.md 精簡**：always-loaded 檔案太肥 → 搬到 review 階段或改成 check
- **Tool economy**：工具呼叫太貴
- **Information access**：agent 拿不到關鍵資訊
- **Navigation**：找檔案太慢
- **Implementation vs Review 分工**：coding standard 該由 context 壓力小的 reviewer 執行，不該塞進 always-loaded 檔案

### 我們有、retro 沒有的

真的動手改並留下紀錄、branch 紀律、依嚴重度 × 復發頻率判斷值不值得做、prose 規則放在最早的階段、gate 的 known-good fixture 要涵蓋所有「本來就預期會出現」的狀態。

### 接入草案

不要整個 link。把「刪減」角度挑進 `/retroactive` Phase 2，或另做一個定期精簡流程。retro 原文假設 `AGENTS.md` / `CODING_STANDARDS.md`，這個 repo 兩個都沒有，要換成 `CLAUDE.md` 和 `/validate`。

---

## 3. 評估過程中順帶發現（跟正式化無關，可以先處理）

### (a) freshness check (f) 抓不到用 backtick 寫的依賴

retro 寫的是 ``Call the Skill tool with `writing-for-agents` ``（backtick），但 check (f) 的 regex 只認雙引號（`.claude/hooks/harness_freshness.sh:185`）。

```bash
# known-bad：retro 實際內容
grep -h 'Skill tool' <checkout>/skills/in-progress/retro/SKILL.md | grep -oE '"[a-z0-9][a-z0-9_-]*"'
# 2026-09-23 實測 → （無輸出）rc=1
# known-good：同一個依賴改成雙引號
echo 'Call the Skill tool with "writing-for-agents"' | grep -h 'Skill tool' | grep -oE '"[a-z0-9][a-z0-9_-]*"'
# 2026-09-23 實測 → "writing-for-agents" rc=0
```

- **目前還沒發生**：已 link 的 skill/command 裡沒有只用 backtick 的 Skill 依賴（2026-09-23 掃過）。
- **link retro 那一刻就會發生**：`writing-for-agents` 沒 link，check (f) 卻不會報。
- **link retro 之前要先修**（可以開一個 retroactive）：regex 放寬到也接受 backtick。

### (b) CLAUDE.md 超過自己設的上限

2268 個英文字，估算約 3k tokens，超過 CLAUDE.md 開頭寫的「aim for under ~2.5k tokens」。Do-not 清單只增不減，正好是 retro No-ops / AGENTS.md 精簡角度會抓到的問題。

---

## 接入前 checklist

- [ ] `pr` 離開 `in-progress/`
- [ ] `retro` 離開 `in-progress/`，README 不再標 STUB
- [ ] 修好 check (f) 的 backtick 漏洞（link retro 前必做）
- [ ] 重讀正式版 SKILL.md，對照本文件，差異大就重新評估
- [ ] 開 `/plan`
