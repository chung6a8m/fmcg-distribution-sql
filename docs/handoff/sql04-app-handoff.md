# SQL-04 — Application handoff: contract, vertical slice và quyết định chờ Owner

- **Trạng thái:** `PROPOSED / OWNER_DECISION_PENDING`. Đầu ra thiết kế cho repo ứng dụng, **không** tự chọn stack hoặc mở B_ONLINE thật.
- **Contract bất biến:** [Business Baseline v1.0](../../business/README.md), [domain model](../../business/domain-model.md), [BR](../../business/business-rules.md), [SOP Mixed](../../business/workflows/mixed.md), [AC-01..21](../../business/acceptance.md) và [SQL-04 review/coverage](sql04-review.md).
- **Reference implementation:** [SQL scratch runner](../../sql/README.md), không phải migration/schema/API production. Không thêm fork/submodule hoặc runtime link về canonical repo.

## 1. Đề xuất vertical slice ứng dụng đầu tiên — APP-01

**Đề xuất cho Owner:** tái dựng **AC-03 Mixed A+B_ONLINE trên dữ liệu SYNTHETIC_UNITLESS, `invoiceEligible=false`** thành **một luồng ứng dụng tích hợp trên môi trường nonproduction**. Đây là cách dùng ngay oracle 7 checkpoints × 13 field đã kiểm SQL để phát hiện lỗi nối module/UI/API/persistence sớm. **Không mô phỏng một hóa đơn thật hoặc gán nhãn B_ONLINE production-admitted.** Nếu cần đưa B thực vào pilot phải hoàn tất gate invoice/legal/accounting/security tương ứng trước đó.

Lý do chọn: một chuyến đã bao trùm A reservation, B quota/grant, manifest load, delivery, AR, cash custody, cashier accept và unload; chính các phần này hiện mới **được kiểm thử trên nhiều schema SQL tách biệt**. APP-01 phải giải quyết khoảng trống tích hợp thay vì mở thêm module mới.

**Đầu ra demo đo được:** người dùng làm việc qua giao diện/API trên một database ứng dụng mới dựng từ migration; bảy bước T0..T6 được post bằng command bền, truy ledger/source và balances qua query, retry/reject/fault không nhân effect, và actual đọc trực tiếp từ persistence khớp [oracle AC-03](../../business/reference-data/expected-results/golden-oracles.json). UI không chỉ “render dữ liệu golden”, không gọi trực tiếp `ac03.*` để giả làm app.

### Backlog tối thiểu, triển khai lần lượt

| ID | Increment | Dấu hiệu hoàn thành / test cần có |
|---|---|---|
| **APP-00** | Owner chọn các quyết định stack/tenancy ở mục 6; tạo solution và test harness tối thiểu | Build và test repeatable, DB migration tạo schema sạch; biết chính xác environment/build/source; không triển khai production |
| **APP-01A** | Tenant/auth boundary tối thiểu cho **nonproduction**; Customer, SKU, location, Trip, A order/line, B quota/grant, source/command ledger | Cross-tenant read/write negative; Customer chịu AR, ShipTo snapshot; confirm A không tạo AR/COGS; same ID/cùng payload replay, khác payload conflict |
| **APP-01B** | Manifest A/B + stock/right postings; T0→T1→T2 | A40/B30 không chồng; transfer A/B mỗi line riêng, đủ 2 legs; B31 rejected, không side effect; rights và stock không âm; snapshot/source trace |
| **APP-01C** | B SaleDeliveryReceipt + A partial delivery; T3→T4 | B20, cash200, AR_B100, COGS200; A25, AR_A375, COGS250; mỗi transaction atomic, fault rollback; không dùng nhầm quota; reserved credit & grant conflict/race tham khảo AC-09 |
| **APP-01D** | Offer/accept quỹ + unload A15/B10; T5→T6; read-only audit/reconcile | OFFER không ledger; cashier accept200 custody−200/fund+200, AR không giảm lần hai; unload A15 hold ở MAIN, B10 release; all 7×13 oracle PASS; trip chưa tự CLOSED sạch nếu còn A hold/case |
| **APP-01E** | Integrated resilience/regression | Hai SQL/client sessions thực tranh BQuota/grant, replay concurrent, rollback sau partial effects, cross-module idempotency; evidence run ID/actual/diff; không nhận `AC-11 full` khi dependency/ACK chưa test |

**Các slice sau APP-01:** Customer/Outlet/ShipTo và dueDate snapshot (`AC-02/08`); receipt/credit/advance tích hợp (`AC-21/20/10`); source costing + QA return (`AC-06/05`); gift/price/VAT (`AC-07/19`); invoice/accounting, offline/recovery, cutover, Pilot. Thứ tự phụ thuộc vào sản phẩm và Owner approval; không được hiểu “APP-01 PASS” là đã đủ 21 AC.

## 2. Application command contract — không khóa HTTP/framework

Tên dưới đây là **candidate use cases**, không phải stored procedure/API endpoint công khai hay yêu cầu microservice. Từng command có **một transaction business** tại data store có thẩm quyền; external call không được giữ trong DB transaction dài.

| Candidate command | Bất biến/preconditions bắt buộc | Atomic effects / không được làm |
|---|---|---|
| `ConfirmAOrder` + `ReserveAStock` | Tenant/actor/Customer/ShipTo/terms và source line approved; không giữ vượt free stock | Order snapshot + A right. **Không** ghi AR/COGS/revenue |
| `GrantBQuota` / `GrantBCredit` | Quyền kho, trip/source/scope và stock chưa bị A giữ; grant có identity/version | Entitlement/quota/grant source riêng; không dùng source giả hoặc B no-channel để mở bán thật |
| `LoadTripManifest` | Trip/location, per-line right A XOR B, stock eligible, actor được phép | Một command → manifest lines, **mỗi line một movement 2 legs**, rights move, cost snapshot; không AR/COGS |
| `PostBSaleDeliveryReceipt` | B writer/mode (khi real), Customer/ShipTo snapshot, quota/stock/grant, verified receipt & reserved credit đủ | Sale+delivery+stock+COGS+AR+receipt/allocation+credit+custody+grant/quota, tất cả cùng commit hoặc rollback |
| `DeliverAOrderPart` | Order/Customer match, confirmed qty/held A, terms snapshot | Delivery/stock/COGS/AR theo **delivery thực**, không dùng B quota |
| `OfferCashHandover` | Custody và actor có quyền, nguồn tiền | Chỉ offer/source, **không** giảm custody/fund |
| `AcceptCashHandover` | Checker/cashier được phép và khác maker khi cần, offered/custody đủ | Cashier acceptance, custody âm + fund dương **cùng commit**, không trừ AR |
| `UnloadTripRemainder` | Manifest origin và right pool đúng nguồn, không unload vượt outstanding | Trả MAIN, rights A move, B release theo source; không coi là customer return hoặc QA release |

**Một command là một intent bền, không phải một HTTP request có thể lặp thoải mái.** Cần command envelope nhất quán:

- `tenantId` từ authenticated tenant context và được kiểm với mọi source/FK; không tin tenantId chỉ do client gửi; `actorId`, role/permission version (server-verified) và `producerId`.
- `commandId` ổn định qua retry, `canonicalPayloadHash` được định nghĩa/versioned bằng thuật toán deterministic; identity scope tối thiểu `(tenantId,producerId,commandId)`. Same hash ⇒ trả durable outcome cũ, **không** post tiếp; hash khác ⇒ CONFLICT không effect.
- `occurredAt` (khi actor khai sự kiện), `recordedAtUtc` (server nhận), business period/date, correlation/causation ID, source document/line, policy/snapshot versions. Không dùng đồng hồ thiết bị để tự nới quyền đã hết hạn.
- Accepted, rejected, pending-dependency và external-UNKNOWN có ý nghĩa khác nhau. Rejection có thể lưu audit nhưng **ledger effects=0**; lost ACK phải query được cùng command ID, không tạo nguồn mới.
- Các hậu điều kiện về AR, rights, qty/value, reserved credit, custody/fund, cost/refund cần được assert **trong cùng transaction**; optimistic version hoặc khóa theo resource, quyết định lock order rõ và test concurrency thực.

**Không tự áp một bảng nguồn SQL-03 lên API.** Implementation phải chọn cách giữ single-writer authoritative ledger, source/effect IDs có quy ước chung; unique FK tenant/customer trên **mọi** module; projection read có reconciliation; outbox cho tác động ra provider (invoice/accounting). Adapter external cần replay/lookup theo original identity, không phát lại ID khi trạng thái UNKNOWN. AC-11 pending dependency và durable inbox/outbox là backlog bắt buộc, **chưa** được SQL-03A chứng minh.

## 3. Read/query contract tối thiểu

| Query candidate | Fields bắt buộc / cách kiểm |
|---|---|
| `GetTripPosition(tripId,asOf)` | MAIN/TRIP qty+stockValue, sold/delivered, rights A/B theo source/pool, pending events/cases |
| `GetOrderDeliveryAndAR(orderId,asOf)` | Customer chịu nợ, ShipTo/terms snapshot, delivery sources, gross−allocated = outstanding và dueDate per delivery |
| `GetCustomerBalances(customerId,asOf)` | Open AR theo item, confirmed receipt, reserved/remaining credit; bank pending riêng, không tính như cash |
| `GetCashCustodyAndFund(actorId,asOf)` | Receipt cash confirmed, OFFERED vs CASHIER_ACCEPTED, custody/fund paired source, không trừ AR lại |
| `GetSourceTrace(sourceId)` | Command outcome, sourceLineIds, actor/occurredAt/recordedAt, postings/allocations/grants/periods; tenant-filtered |
| `GetAC03Checkpoint(step)` (test only) | **13 cột đúng tên** `step, mainQty, tripQty, soldQty, mainCost, tripCost, cogs, aHold, bQuota, arA, arB, custody, fund` derive từ database; không hardcode expected |

Mọi report/aggregate phải có `asOf`, scope, pending/unknown và `n/N` khi phù hợp. Client không được suy `UNKNOWN=0` hoặc dùng latest master để sửa snapshot lịch sử.

## 4. Kiểm chứng ứng dụng: điều kiện nghiệm thu APP-01

Từ [business cases](../../business/reference-data/scenarios/business-cases.json) và [oracle AC-03](../../business/reference-data/expected-results/golden-oracles.json) **nguyên bản**, chạy setup fixture đã khai rõ (unit `SYNTHETIC_UNITLESS`, không trộn [master seed](../../business/reference-data/master-data/seed.json)); đọc actual từ query ở mục 3:

1. `T0` MAIN100/value1000, A hold40, B quota30, B grant100, không AR/COGS.
2. `T1_LOAD` MAIN30/TRIP70; manifest A40/B30 per-source, transfer không ghi sale.
3. `T2_REJECT` B31 thất bại **do quota**, các cột vẫn bằng T1, không ledger effect.
4. `T3_B20` B20/P300/cash200 ⇒ AR_B100/custody200, COGS200; B grant còn0.
5. `T4_A25` A25/P375/unpaid ⇒ AR_A375, COGS tổng450, A hold còn15.
6. `T5_HANDOVER` cashier accept200 ⇒ custody0/fund200, AR không đổi.
7. `T6_RETURN` trip0/main55, A hold15 ở MAIN, B quota0, AR_A375/AR_B100.

**Assert đầy đủ 91/91 field/run**, không chỉ final checkpoint; thực thi fixture/reset sạch ít nhất hai lần với ID khác, expected load trực tiếp JSON. Negative matrix: wrong tenant/Customer/ShipTo, wrong A/B pool, overdeliver, duplicate same/changed payload, bank pending, OFFER only, maker/checker violation, fault after half effects, same-resource two-client race, wrong source/cost lineage. Ghi SQL/database/compatibility và API/UI build, test commit, TestRunId, expected/actual/diff, negative/fault/2-session trace và evidence link.

**Definition of Done cấp APP-01 nonproduction:** schema tích hợp mới từ migration, các command/queries thực chạy, checkpoint pass, không có side effects khi reject/fault/replay, source trace và tenant/auth negative PASS, review CI trên HEAD. Không tự tuyên bố `AC-03 FULL E2E` nếu invoice/real role/external/accounting thiếu; không mở production B, offline hoặc go-live. Bất kỳ extension `AC-06` hay `AC-21` qua module tích hợp cần test riêng, không dựa vào PASS namespace thử.

## 5. Persistence ownership / mẫu chuyển từ SQL prototype

| Giữ ở data layer | Chuyển sang service và interface |
|---|---|
| Composite PK/FK tenant+Customer/source, unique command/ledger effect, decimal/check constraints | Auth context, maker–checker, policy/version snapshot, mode admission, workflow/approval |
| Atomic transaction & compare-and-write stock/rights/grant/AR; source↔posting integrity | Command handlers + unit of work; deterministic error/outcome, stable retries |
| Append-only ledger/cost version và projection reconcile | External outbox/ACK query, pending dependency, recovery case, cross-module orchestration |
| Migration/test fixtures (engine-specific sau quyết định) | API/UI/view models, audit query, telemetry, tenant access, E2E tests |

`ac03.ExecuteSaleB`, `ac09.ExecuteSale`, `ac21.PostCommand`, `ac06.PostCommand` là **mẫu executable specification**. Không có quyết định phải dùng stored procedures, EF/Dapper/ORM, SQL Server production hay cách triển khai identity tại SQL-04.

## 6. Decision register — tất cả PENDING

| ID | Quyết định cần Owner ghi rõ | Điều kiện/ảnh hưởng |
|---|---|---|
| **OWN-SQL04-01** | Engine DB sản phẩm: SQL Server hay lựa chọn khác | Type precision, transaction semantics, migration, tooling, cost & deployment; SQL Server 2019 LocalDB mới là environment đã CI verified |
| **OWN-SQL04-02** | Tenancy topology & isolation | `business/constraints.md` còn **D-01 database-per-tenant** là quyết định lịch sử; thay đổi phải có Owner supersession/version, không mặc định pooled DB |
| **OWN-SQL04-03** | Backend/runtime/API & persistence/ORM | Một nguồn ghi có thẩm quyền; idempotency, transaction boundary và tooling test phải đáp ứng, không chọn vì SQL stored procs hiện tại |
| **OWN-SQL04-04** | Frontend/mobile/PWA và offline posture | PWA là quyết định lịch sử được giữ; field UX và thiết bị, không bật Offline Write chỉ vì app sync được |
| **OWN-SQL04-05** | Hosting/ops, audit, restore, secrets/retention | Chọn tối thiểu cho dev/test; trước real pilot phải kiểm security, backups/restore, access, provider, RPO/RTO |
| **OWN-SQL04-06** | Chọn/điều chỉnh **APP-01** Mixed synthetic nonproduction | Phạm vi, test evidence, Owner authorization để bắt đầu app; lựa chọn khác cần cập nhật backlog mà không đổi oracle |

**Đề nghị quy trình ra quyết định:** Owner chọn 01–06 và ghi date/rationale/alternatives trong repo ứng dụng; chỉ sau đó sinh solution/migrations. SQL-04 không “chốt stack hộ Owner”. Không có quyết định **Product Verification/EV/P0/Go-Live** ở đây. Bất kỳ thay đổi ngữ nghĩa business nào phải đề xuất tại canonical và nâng lock sau phê duyệt, không sửa snapshot local.

## 7. Gói bàn giao và trạng thái

- [x] Repo SQL chứa contract độc lập, runner, oracle, schema và links evidence; read-only `business/` không đổi.
- [x] Có review/gap [SQL04-G01..G08](sql04-review.md) và backlog APP-00→APP-01E với exit tests cụ thể.
- [x] Candidate commands/queries, boundaries, source/tenant/decimal/audit/idempotency, persistence ownership đã ghi.
- [ ] Independent review SQL-04 PR.
- [ ] Owner phê duyệt OWN-SQL04-01..06, sau đó app repo mới nhận stack/architecture decision riêng.
- [ ] Actual app integration/API/UI/security, external EV, tenant go-live: **NOT_RUN**.

**Handoff outcome:** `DOC_HANDOFF_CANDIDATE`; **không** phải `APP_IMPLEMENTED` hoặc `OWNER_ACCEPTED`.
