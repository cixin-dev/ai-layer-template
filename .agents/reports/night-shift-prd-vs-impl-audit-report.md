# PIV Ralph Loop(Night Shift)— 規劃 vs 實作對照報告

對照對象:`.agents/prds/piv-ralph-loop.prd.md`(2026-06-28 draft)vs 已合併的 PR #55–#83。
方法:ultracode 多代理稽核 — 9 維度稽核 → 每條發現對抗式驗證 → 手動補洞。
共 69 條發現;四個測試 seam 的測試套件都實跑過 exit 0。

---

## 一句話結論

**高度忠實。** PRD 的 33 條 user story 行為上全部落地,四個測試 seam(decider / durable state / executor probe / notify)都存在且測試通過。偏差幾乎都是「實作出比 PRD 字面更精簡的機制」+ 少數誠實延後的接地項 —— **沒有任何東西是「悄悄」缺漏的,每處走鐘/延後都有白紙黑字的依據**。

最該記住的一句:**「event-driven / 掉事件回收 / concurrency 撥盤」這三個賣點比 PRD 講得樸素** —— 出貨的其實是「同步序列 drain + ~5 分鐘輪詢」的 v1,誠實但沒 PRD 字面那麼花俏。

---

## 逐維度對照

| 維度 | 對應 PR | 結果 | 備註 |
|---|---|---|---|
| **Seam-1 決策器 + 狀態機 + retry ladder** | #65, #72 | ✅ 11/11 全符合 | 純函式、零 agent 記憶、re-implement→re-plan→escalate(K=3 可調)全部有測試背書,25 case 全綠 |
| **Seam-2 durable state** | #68 | ✅ 6/6 符合 | attempts+phase 存檔、跨重啟冪等、K 邊界剛好觸發 escalate |
| **Seam-3 thin executor + 每階段獨立 session** | #75, #80 | ✅ 大致符合(1 走鐘 / 1 延後) | session 隔離確認:每階段開新 `claude -p` 子程序 |
| **Hybrid trigger loop + 撥盤 + claim gate** | #81, #82 | ⚠️ 行為符合但框架被樸素化 | 見下方走鐘 #2/#3/#4 |
| **Seam-4 兩發通知** | #79 | ✅ 6/6 符合 | 只在 escalate / pr-ready 發、per-step 通知移除、有 contract 測試 |
| **Push 畢業開關 + 危險推送地板 + 不自動合併** | #71 | ✅ 5/5 符合 | 撥盤 ask→allow 是開關;force-push / push-to-main 地板獨立於撥盤、有回歸鎖 |
| **gate-0 詞彙和解 + zh 摘要 + PIV 生命週期** | #55, #67 | ✅ 符合 | #55 先落地;CONTEXT.md「輪詢→中斷」重構完成;/validate 仍歸檔 plan 到 completed/ |
| **Dashboard 可觀測性** | #83 | ✅ 符合(有條件) | 見走鐘 #6 |
| **Out-of-Scope 守恆** | 跨切面 | ✅ 8/9 守住,1 有意越界 | 自動合併/多repo/並行>1/依賴排程/自動生 Issue 全部確實擋在門外 |

---

## 真正的走鐘(shipped ≠ plan,但多半合理且有跡可循)

1. **Executor 比規劃更「薄」——副作用被移進 /validate。**
   PRD 說 executor 自己做 spawn/worktree/run/push/open-PR/notify。實際上 **push + 開 PR + pr-ready 通知都委派給 `/validate` Phase 5**,worktree 建立也委派出去。方向沒錯(邏輯留在 decider),但 PRD 那份「executor 副作用清單」與實作不符 —— executor 其實更瘦。

2. **「event-driven happy path」實際是同步 busy-drain,不是真的事件通道。**(trigger US-20)
   沒有 async 事件訂閱;是一個緊湊的同步 drain 迴圈 + ~5 分鐘輪詢。行為上達成「階段轉換零閒置」,但「事件驅動」是美化說法。

3. **US-19「回收掉落的完成事件」這半條是空殼。**(驗證者把 matches 下修為 drifted)
   因為設計是同步的,根本沒有 async 事件會掉,所以「掉事件回收」那半條的理由不成立。輪詢的**另一半**(撈新貼 ready 的 Issue)是真的有用、成立。

4. **Concurrency「撥盤」其實只是「不是 1 就拒絕」的守門。**(trigger US-18)
   沒有任何並行派工骨架;要升到 N 需要實作,不是改個數字。符合 v1 序列行為,但「不必重架構就能畢業到 N」偏樂觀。

5. **pr-ready / escalate 通知靠 agent 照 prompt 指令發(best-effort),不是硬程式路徑。**(notify US-12)
   行為上在,但依賴 agent 遵守 validate.md 的指示,不是決定性的 code。

6. **Dashboard 可觀測性有條件。**(dashboard US-31)
   executor 跑在自己的 clone(ADR-0024)、`.night-shift/` 被 gitignore,所以操作者在主 checkout 跑 `/dashboard` 未必看得到即時 loop 狀態。「一眼看到」要看你在哪個 checkout。

7. **OOS「gate-0 外不得改 CONTEXT.md/ADR」字面上被越界。**(oos)
   #81 動過 CONTEXT.md 等。但每次越界都有追溯/理由,**不是**悄悄漂移。

---

## 有意延後(有白紙黑字依據)

- **Executor 失敗路徑的「真 session 語意接地」**(#80 Task 6)—— 真實 session 裡 re-implement/re-plan 的語意行為**尚未實證**,只測了 wiring + 離線 SIM。report/PR body 明寫延後。
- **Substrate 決策的紀錄很薄** —— ADR-0024 把「週期性 event+poll 排程器」延到 #63,但 #81 實際選了什麼,沒有對應的 ADR 記下來。決策做了,痕跡不足。
- Dashboard 停滯/過期提示、#82 M4 的 report 漂移 —— 小項,明確延後。

---

## 測試 / 驗證缺口

- **沒有 loop 層測試單獨驗「跳過非 ready Issue」**(trigger US-21)—— 假 gh 忽略 `--label`,直接吐 TSV,所以那條 skip 沒被隔離測到。
- 部分 report 與出貨程式碼不同步(state report 舊、#82 新增的三個測試沒被算進去)—— 文件漂移,非程式缺陷。

---

## 過程觀察(retroactive 外圈在運作)

- **#66 CLOSED**(用 CI 強制 zh 變更說明)→ 被 **#67** 取代:改成「人審門的散文底線」,因為這個 free-private repo 的 CI 無法硬擋(ADR-0022)。
- **#74 CLOSED**(獨立 E2E probe)→ 併入 **#75** 的 executor + probe。
- 多個 retroactive(#69 clean-worktree 韌性、#70 HEAD-race checkout 隔離、#77 verify-check-commands、#78 runbook)—— System Evolution 外圈如設計般在建置途中收緊 harness。
- **完整性批判者沒跑到**(撞 session 上限,6:10pm 台北重置);最高價值的未驗項我已手動補查(auto-merge 擋住、session 隔離、序列撥盤、/validate 歸檔)。

---

## 補跑更新(2026-07-02 晚 — 尾段驗證 + 完整性批判)

第一輪撞 session 上限的尾巴補跑完成(15 agents,無失敗)。

**尾段驗證:14 條全部獨立確認,0 條被推翻。** 13 條 matches、1 條 drifted(gate-0 外改文件,確認為「越界但有跡可循」)。其中 #82 的 no-progress guard 還被 **mutation 測試**:把守衛拿掉 → 8 秒內派工 444 次、timeout 熱旋轉,證明那段 code 是真的在擋。先前手動抽查的 auto-merge / session 隔離 / 序列撥盤 / /validate 歸檔也都被獨立 grep 複驗坐實。

**完整性批判找到兩個「審計自己的盲點」(不是實作缺,是我第一版報告漏稽核的):**

1. **US-3 頭號承諾沒有端到端實證。** 「過夜把 ready 佇列自動跑到 review-ready PR、中間沒人」是整份 PRD 的招牌結果 —— 架構上組裝好了,但**唯一能證明它的東西(Seam-3 LIVE 完整 happy path)本身被延後了(#80 Task 6)**。也就是說核心賣點只證了 wiring + 離線 SIM,**從沒真跑過一次完整流程**。這是整份審計最重要的一條,而第一版沒有任何 finding 點出來。

2. **US-5 每任務獨立 worktree sandbox 沒被稽核。** 有實作(ADR-0024 / #75 executor 建立並進入 worktree),但第一版審計的 executor 維度只查了 US-4/US-6/US-23,漏了「每個任務自己一個 sandbox」這條不變式。**覆蓋缺口,非實作缺口。**

3. **Seam-4 沒有一等公民 finding**(只由 US-25 + #79 間接覆蓋)—— 四個測試 seam 裡唯一沒有專屬 finding 的。

**覆蓋率盤點:** 33 條 US 有 31 條被 finding 認領(只差 US-3、US-5);12 條 Impl decision 全覆蓋;6 個 PR 未按號歸屬但都有解釋 —— #66→#67(CI 閘門棄用改散文)、#74→#75(拋棄式 probe 被正式 executor 取代)、#70/#77/#78(retroactive harness PR)、#76(MIT 授權 chore,不屬功能範圍)。

**跨切面補強:** substrate 落在 PRD 說的地方(/plan 階段)但**拆成兩個決策、其中一個沒 ADR** —— ADR-0024 記了 session/executor substrate,但 #81 實際選的**排程器**(序列同步 bash drain + 5 分輪詢)只在 code 裡、沒 ADR。這正是 Issue #87 要補的。兩條 US-19/US-20 走鐘經 loop code 核實為**結構性**、非偶然。

---

## 給你的一句話

如果只想聽重點:**這套 Night Shift 忠實實現了 PRD 的行為契約(31/33 US 有 finding、四 seam 綠、14 條尾巴 0 推翻)。** 值得回頭補的三件事 ——
(a) 把「event-driven / concurrency 撥盤」的**文件用語**校正成「同步序列 drain + 輪詢」的真相 → **已開 #86**;
(b) 補一份 ADR 記下 #81 實際選的 runtime substrate(現在 ADR-0024 只說延後)→ **已開 #87**;
(c) **(補跑新增、也是最重要的一條)** 把 US-3 頭號承諾**端到端實跑一次**接地 —— 兌現先前延後的 Seam-3 live / #80 Task 6,證明佇列真的能過夜自動跑到 review-ready PR,而不是只證了半路的 wiring → **已開 #88**(operator-run probe,偏 ready-for-human)。
其餘走鐘都在可接受、可追溯的範圍。
