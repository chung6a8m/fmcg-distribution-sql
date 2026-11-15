# Application roadmap — APP-00 → APP-01E

- **Trạng thái:** `OWNER_AUTHORIZED / IMPLEMENTATION_NOT_STARTED` (2026-11-15). [Decision Register](../decisions/2026-11-15-owner-app-decisions.md).
- **Nguồn:** [Business Baseline](../../business/README.md), [AC-03 oracle](../../business/reference-data/expected-results/golden-oracles.json), [SQL-04 review](../handoff/sql04-review.md) và [application handoff đầy đủ](../handoff/sql04-app-handoff.md).
- **Phương châm:** Business-first, solo developer, mỗi increment có PR riêng; không mở rộng SaaS foundation, generic repository, cloud hoặc framework nghiệp vụ trước khi có nhu cầu kiểm chứng.
- **Nơi thực thi:** repository ứng dụng độc lập [chung6a8m/fmcg-distribution-dotnet](https://github.com/chung6a8m/fmcg-distribution-dotnet) — đã tạo và mở [APP-00A PR #1](https://github.com/chung6a8m/fmcg-distribution-dotnet/pull/1); repository SQL này chỉ lưu reference, decision, roadmap và evidence, không chứa app code.

## APP-00 — Foundation

| ID | Scope | Exit evidence bắt buộc |
|---|---|---|
| **APP-00A** | .NET 10 Modular Monolith tối thiểu: Web API, domain/application/infrastructure, Dapper/FluentMigrator; React+TS+Vite PWA online-first; SQL Server; test harness. | Build frontend/backend PASS; migration tạo hai database tenant **mới, synthetic**; migration repeat/no-op; DB target guard; authenticated tenant routing không phụ thuộc client-supplied connection string; negative cross-tenant access; CI trên PR HEAD ghi phiên bản, SHA và test log. |
| **APP-00 closeout** | Ghi engine/compatibility, secrets/audit strategy, migration rollback policy, source tree & test commands; lưu lock của Business Baseline v1.0. | Repro từ clean checkout, README/AGENTS điều hành được, zero hardcoded production secrets, mã và test review. |

**Không coi init solution/truy cập DB thành app integration verified.** Auth context tối thiểu có thể dùng test credentials **chỉ trên nonproduction**; production identity hardening thuộc APP-01A và các gate tiếp theo. Không tạo runtime link/fork/submodule tới canonical hoặc SQL repository.

## APP-01 — Mixed synthetic nonproduction

| ID | Increment chính | Hoàn thành khi |
|---|---|---|
| **APP-01A** | Tenant/auth boundary; Customer/ShipTo snapshot, SKU/location, Trip, A order/line, B quota/grant, command/source/ledger identity, persistence model tích hợp. | Test tenant A/B read/write negative, same command+payload replay, changed payload CONFLICT không effect; confirm A không sinh AR/COGS; schema source/effect toàn hệ thống có migration; mọi transaction có authoritative writer. |
| **APP-01B** | T0→T1→T2: A hold40, B quota30; manifest A40/B30, transfer kho→xe và rights pool riêng. | Stock/rights A/B không âm/chồng quyền; mỗi manifest line có 2 legs; B31 × price15 = P465, offered/verified cash465, used credit0: **`REJECTED_QUOTA` / `B_QUOTA_INSUFFICIENT`** và zero SourceLine/Receipt/ledger effect. |
| **APP-01C** | T3 B20 cash200/AR_B100/COGS200; T4 A25/AR_A375/COGS250, source cost/AR/receipt integrated. | Atomic transaction + fault rollback và wrong Customer/ShipTo/pool negative; không trừ double B grant/credit, AR và qty/cost balance đúng. |
| **APP-01D** | T5 cashier accepted200; T6 unload A15/B10, A hold vẫn MAIN; read-only audit/reconcile. | OFFER không ledger; ACCEPT custody−200/fund+200 không trừ AR lần hai; all **7 checkpoints × 13 fields = 91/91** theo expected JSON gốc từ actual persisted data; test reset sạch lặp >=2 với run identities khác nhau. |
| **APP-01E** | Resilience/concurrency/regression trên app schema tích hợp. | 2 connection/client races quota/grant (đối thủ thua không ghi effects), retry concurrent/conflict, rollback mid-effects, cross-module source reconciliation, tenant negative; TestRunId/actual/diff/CI HEAD. **AC-11 full vẫn NOT_VERIFIED nếu chưa test dependency C→P, lost ACK/restart, external UNKNOWN.** |

### Bài test tối thiểu xuyên APP-01

- Dùng `business/reference-data/scenarios/business-cases.json` và `business/reference-data/expected-results/golden-oracles.json#AC-03` **nguyên bản**; không hardcode expected và không dùng `ac03.*` làm backend.
- Command envelope có `tenantId` từ server auth, `actorId`, `producerId`, `commandId`, canonical payload hash/version, causation/correlation, recordedAtUtc; same identity/hash replay outcome cũ, khác hash -> conflict, reject effects=0.
- Mọi query report có `asOf`, tenant scope và pending/unknown rõ; 13 trường checkpoint đọc từ DB. `SYNTHETIC_UNITLESS`, `invoiceEligible=false` không phải tiền VND hay giao dịch B thật.
- Thử negative overdelivery, sai pool/customer/ship-to, bank pending ≠ verified receipt, OFFER ≠ ACCEPT, maker/checker khác người, wrong source/cost, fault after partial write và hai session đồng thời.

### Gap → nơi xử lý

| Gap SQL-04 | App increment / nghĩa vụ |
|---|---|
| G01 unified source/ledger, G02 tenant/auth | APP-01A, bắt đầu thiết kế ở APP-00A |
| G03 cross-module idempotency/outbox/dependency | APP-01A+E cho core idempotency; AC-11 dependency/recovery vẫn backlog riêng nếu chưa test |
| G04 decimal/UoM/cost rounding | APP-01A contract schema và APP-01C tests; AC-06/lot/QA nâng cấp cần slice riêng |
| G05 integrated races/rollback | APP-01B/C/E |
| G06 SQL compat/perf/restore | APP-00A nonprod baseline; benchmark/production-like và restore verification bổ sung trước pilot |
| G07 legal/invoice/accounting/cutover/EV/P0 | **EXTERNAL_GATE / NO_GO**; không nằm trong authorization APP-01 |
| G08 Owner decisions | **OWNER_APPROVED** bằng [register](../decisions/2026-11-15-owner-app-decisions.md), không tự đóng G01..G07 |

## Chu trình và tiêu chí merge

Mỗi PR độc lập: scope/AC/BR/SOP, test input, oracle version, expected vs actual, negative/fault/evidence, SQL Server/compat, commit SHA, CI run. Trạng thái `LOCAL_VERIFIED`, `CI_VERIFIED`, `BLOCKED`, `OWNER_ACCEPTED` phân biệt rõ. Review findings được xử lý ở HEAD mới; merge chỉ khi review và yêu cầu CI tương ứng PASS. PR đầu tiên **APP-00A**, sau đó **APP-01A**.

**Không vượt gate:** No production B, offline writes, EV-01..15, P0 signoff, NPP-01 cutover, accounting/legal verification hoặc go-live chỉ vì APP-01 synthetic PASS.
