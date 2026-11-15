# SQL-04 — Review mô hình, coverage và giới hạn SQL prototype

- **Ngày:** 2026-11-15.
- **Trạng thái tài liệu:** `HANDOFF_CANDIDATE / REVIEW_PENDING`. Đây là đánh giá trên repository, **không** phải kết quả chạy test mới hay Owner Acceptance.
- **Nguồn đọc:** `main` sau merge PR #6, commit `cf4d9079980e432728d1338525db1220bc3f953f`; SQL-01/02/03A/03B/03C đã merge. Nếu code thay đổi sau mốc này phải đối chiếu lại.
- **Business contract:** [`business.lock.json`](../../business.lock.json), `business-v1.0.0`; tree `business/` = `c9a4164a99ea57e1d5f9bc8711285c6d3705f8e3`, read-only.
- **Handoff tiếp:** [Hợp đồng và backlog vertical slice ứng dụng](sql04-app-handoff.md).

## 1. Kết luận review

**Đủ điều kiện bàn giao làm executable reference, chưa đủ điều kiện tái sử dụng physical SQL prototype như database ứng dụng.** Có bằng chứng CI cho năm AC ở **mức SQL-slice**: AC-03, AC-06, AC-09, AC-20, AC-21. Các oracle vẫn là Business Baseline candidate/model tại nguồn. **AC-11 chỉ được thử một phần** (retry cùng identity, conflict khác payload, rollback); lost ACK qua restart và sự kiện có dependency C→P chưa chạy.

Phát hiện kiến trúc trọng tâm: `ac03`, `ac09`, `ac21`, `ac06` là **bốn schema kiểm chứng độc lập** trên cùng database scratch, không phải một data model production tích hợp. Do đó tổng các test PASS không xác nhận rằng stock, B sale, AR, custody, advance và cost-return đã liên kết trong **một** transaction/source/tenant model chung. Đừng sao chép nguyên schema/`Stored Procedure` sang app hoặc coi riêng SQL-03A/B/C là integration test.

## 2. Logical → physical: đối chiếu và debt

| Chủ đề | Logical contract | Physical/test đã có | Khoảng trống cho app |
|---|---|---|---|
| Tenant/Seller, Customer | 1 seller thương mại/tenant; FK và access không xuyên tenant; Customer chịu AR, Outlet tùy chọn | `ac03.Tenant/Seller/Customer`; composite tenant FK; `ac21` kiểm Customer cùng scope khi phân bổ | Chưa có routing/auth/revoke/restore thực; các namespace chưa chia sẻ danh mục; Customer–Outlet history và ShipTo chuẩn còn thiếu |
| SKU/UoM/StockLocation/Trip | base UoM, factor/step snapshot, lot/expiry, kho/xe/quarantine | `ac03` có SKU, MAIN/TRIP, quyền A/B; `ac06` thử AVAILABLE/QUARANTINE, source cost/version | `ac06` dùng số lượng nguyên + tiền whole-unit trong fixture, `ac03` dùng qty `DECIMAL(19,6)` và value `DECIMAL(28,6)`; chưa thống nhất conversion/rounding/lot/QA |
| A order/reservation và B quota | A hold, B quota tách pool và không chồng lượng; manifest/unload theo source line | `ac03` có AOrderLine, AReservation, BQuota, ManifestLine, StockMovement/Postings, RightPosting; XOR/pool/lineage assertions | Không có aggregate A+B dùng chung `ac09.Pool`; grant scope và reassign hold A15 sau chuyến chưa thành policy |
| B sale, AR, receipt, credit | B SaleDeliveryReceipt nguyên tử; Customer/ShipTo/terms snapshot, đủ source cho từng effect | `ac03.ExecuteSaleB` + `ac09.ExecuteSale` độc lập; `ac09` thử credit reservation, cash, pending bank, overpay, grant/quota races | Chưa có API/identity chung giữa B sale `ac09` và `ac21` AR/receipt/custody; admission kênh hóa đơn, quyền writer và issuer thật chưa có |
| AR, custody, fund, advance | Receipt confirmed mới ghi; allocate riêng; offer ≠ accept; advance độc lập | `ac03` cash/AR; `ac21` thử AC-21 + AC-20 với separate ledger và replay/fault | Chưa nối receipt do bán B sang `ac21`; cashier maker–checker, bank verification và accounting integration chưa có |
| Cost source, return, locked period | Moving-average theo tenant×SKU×location; return dùng cost source và forward adjustment | `ac06.IssueSource/SourceCostVersion/ReturnLine/ReturnCostAdjustment` và `RoundProratedCost`; kiểm lịch sử khóa | `ac03.CogsEffect` và `ac06.CostEffect` chưa chia sẻ issue/source; thiếu fractional UoM, lot, cash refund, QA release và đối soát kỳ kế toán |
| BusinessEvent/SourceLine | Unique `(tenantId,producerId,commandId)` + payload hash; sourceLineId duy nhất/tenant; posted effects traceable | `ac03.BusinessEvent/SourceLine`; `ac09.Command`, `ac21.Command`, `ac06.Command` kiểm semantic retry ở **từng** namespace | Chưa có common inbox/outbox, external effect identity, persisted dependency queue/lost ACK recovery across modules |
| Index/lock/transaction | PK/composite FK/unique/check, serializable right/grant/stock/AR updates | FK/check/unique và assertions ở các schema; `SERIALIZABLE` + `UPDLOCK,HOLDLOCK` trong command procs | Không có benchmark load thực, plan/index review theo workload, deadlock retry strategy toàn app hoặc cross-namespace atomicity |

Tham chiếu chi tiết: [Logical ERD](../data-model/logical-erd.md), [invariants](../data-model/invariants.md), [transaction boundaries](../data-model/transaction-boundaries.md), [AC-03 mapping](../data-model/ac03-mapping.md); các DDL ở [`sql/schema/`](../../sql/schema/).

### Phân tách trách nhiệm khi xây ứng dụng

- **Bất biến data-layer:** composite tenant+identity FK, source/effect uniqueness, numeric range, lot/source reference, immutable posting và atomic commit là trách nhiệm của persistence/schema đã chọn.
- **Application/domain service:** phân quyền actor, maker–checker, tenant context từ identity, snapshot policy/terms, command orchestration, admission mode, xử lý conflict/rejection, các external workflow và recovery. SQL `CHECK`, trigger hoặc stored procedure mẫu **không thể thay** auth/approval production.
- **Read model:** ledger/source là nguồn kiểm toán; materialized balance phải reconcile được, có `asOf` và trạng thái pending. Không dựa vào bảng master hiện tại để tính lại snapshot chứng từ đã chốt.

## 3. Evidence đã có và cách reproduce

| SQL slice | Oracle nguồn/khối lượng | Mức đã xác minh, môi trường | Evidence |
|---|---|---|---|
| SQL-02 / AC-03 | `golden-oracles.json#AC-03`, T0..T6, 7×13 = **91 fields/run** | Hai fresh scratch, reject/rollback/source lineage/guard PASS | [SQL-02 CI 43705303178](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43705303178), [evidence](../evidence/2026-11-15-sql02-ac03-ci.md) |
| SQL-03A / AC-09 | `additional-oracles.json#AC-09`, 5 branches; hai race B grant và quota | Hai fresh scratch, two-session SQL clients + separate observer/lock contention, replay/fault PASS | [SQL-03A CI 43716390894](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43716390894), [evidence](../evidence/2026-11-15-sql03a-ac09.md) |
| SQL-03B / AC-21 & AC-20 | `additional-oracles.json#AC-21` (5×6) và `#AC-20` (5×5) | Hai fresh scratch, positive/negative/replay/fault PASS | [SQL-03B CI 43718593857](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43718593857), [evidence](../evidence/2026-11-15-sql03b-ac21-ac20.md) |
| SQL-03C / AC-06 | `additional-oracles.json#AC-06`, 10 fields/run; extra exact rounding regression | **Final executable/test HEAD `73a6a5f40c45c0dd160186c88961720b1ac77aa9`**: hai fresh scratch, 10/10, cost round/fault/immutability PASS; AC-03 regression 91/91 | [Final SQL-03C CI 43726916416](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43726916416), [PR #6 final review/merge](https://github.com/chung6a8m/fmcg-distribution-sql/pull/6) |

**Phạm vi environment được chứng minh:** GitHub Actions `windows-2022`, SQL Server **2019 LocalDB 15.0.4382.1 / compatibility 150**, Windows integrated auth và disposable scratch; guard database name/instance/marker/nonce, guarded DROP. **SQL Server 2017 / compat140, local machine thực, production tenancy, app integration chưa chạy.** Không nói “5 AC E2E verified”. Evidence gắn **code SHA/run**, không tự suy là đã tái chạy trên SQL-04.

Reproduce trên **instance thử nghiệm riêng, không phải production/shared**, có PowerShell 5.1+, `sqlcmd`, quyền CREATE/DROP DB scratch:

~~~powershell
python tools/validate_business.py
git rev-parse HEAD:business
.\sql\run-tests.ps1 -ServerInstance '(localdb)\MSSQLLocalDB' -IncludeSql03A -IncludeSql03B -IncludeSql03C
~~~

Lệnh cuối chạy AC-03 trước, sau đó ba namespace SQL-03 độc lập, so oracle từ JSON gốc và ghi `sql/test-results/<TestRunId>.json` (gitignored). Nếu fail, giữ actual/diff/engine/cleanup, không sửa oracle. **SQL-04 là tài liệu; không có lần chạy mới được tuyên bố ở PR này nếu không có CI/artifact tương ứng.**

## 4. Ma trận coverage AC-01..21

**Định nghĩa:** `SQL_VERIFIED_SLICE` = có CI chạy executable SQL và oracle cho đúng phạm vi; `SQL_PARTIAL` = mới kiểm một phần invariant, không phủ toàn AC; `NO_SQL_RUN` = chưa có test SQL riêng (Business oracle có thể đã `MODEL_ONLY`); `EXTERNAL_BLOCKED` = cần app/hạ tầng/đối tác/pilot thực, không được biến PASS SQL thành PASS gate. Mọi `EV-01..15` vẫn **chưa được nâng cấp** bằng kết quả SQL.

| AC | Mức SQL tại handoff | Chưa có để xác nhận AC end-to-end |
|---|---|---|
| AC-01 | NO_SQL_RUN | Tenant auth, revoke, restore, audit, EV-01/09 |
| AC-02 | NO_SQL_RUN | Customer không có Outlet, ShipTo/terms snapshot khi master đổi |
| AC-03 | **SQL_VERIFIED_SLICE** | UI/API/permissions, integration A+B, invoice/accounting, EV liên quan |
| AC-04 | EXTERNAL_BLOCKED | Kho-01 cutover, legacy writers ngoài wave, G-CUT/G-STOCK |
| AC-05 | NO_SQL_RUN | UoM/lot/FEFO, QA quarantine, delivery/return thật |
| AC-06 | **SQL_VERIFIED_SLICE** | Refund tài chính, QA, cost kỳ kế toán, EV-07 |
| AC-07 | NO_SQL_RUN | Quà/waiver/refund entitlement |
| AC-08 | NO_SQL_RUN | N=7/N=14 do master đổi, dueDate theo từng A Delivery |
| AC-09 | **SQL_VERIFIED_SLICE** | B admission thật, auth/writer, customer cross-ledger, EV-06/08 |
| AC-10 | SQL_PARTIAL | AC-21 thử cơ chế tương tự, nhưng chưa chạy riêng oracle AC-10 |
| AC-11 | **SQL_PARTIAL** | Dependency C→P, ACK lost qua restart, durable pending/recovery |
| AC-12 | NO_SQL_RUN | One-writer/trip, offline occurred-fact, grant expiry/recovery |
| AC-13 | EXTERNAL_BLOCKED | Restore/revoke/privacy, external invoice identity |
| AC-14 | EXTERNAL_BLOCKED | Provider invoice UNKNOWN lookup; B_NO_CHANNEL vẫn BLOCKED |
| AC-15 | EXTERNAL_BLOCKED | Accounting adapter, POSTED/reconcile/diff và corrections |
| AC-16 | EXTERNAL_BLOCKED | Opening/cutover/full Kho-01/old writer/forward recovery |
| AC-17 | NO_SQL_RUN | Visit không đơn, không sinh giao dịch giả |
| AC-18 | EXTERNAL_BLOCKED | Pilot NPP-01, n/N/UX/SLO, chấp nhận theo mode |
| AC-19 | NO_SQL_RUN | Pricing/VAT/credit refund/cumulative rounding tích hợp |
| AC-20 | **SQL_VERIFIED_SLICE** | Employee advance thật, approval, cashier/accounting integration |
| AC-21 | **SQL_VERIFIED_SLICE** | Receipt/AR/custody integration với sale thật, quyền cashier |

Các expected/scenario chỉ đọc từ [AC](../../business/acceptance.md), [cases](../../business/reference-data/scenarios/business-cases.json), [golden AC-03](../../business/reference-data/expected-results/golden-oracles.json) và [additional oracles](../../business/reference-data/expected-results/additional-oracles.json). **Không có AC-22**. `EV-01..15` và năm gate `G-STOCK/G-CUT/G-IDEMP/G-LEDGER/G-INV` vẫn ở mức nguồn, **NOT_ACCEPTED / không được miễn**; trạng thái `MODEL_ONLY` của Business Baseline không bị SQL-04 ghi đè. `B_NO_CHANNEL` BLOCKED; offline write chưa được bật; no tenant go-live.

## 5. Gaps ưu tiên và disposition

| ID / mức ảnh hưởng | Phát hiện / điều kiện khắc phục | Disposition |
|---|---|---|
| **SQL04-G01 / APP_BLOCKER** | Bốn namespace thử riêng, chưa có unified source/ledger/tenant model. Chốt aggregate + migrations/app persistence, chứng minh AC-03 và AC-09/20/21/06 không double-post khi nối thật. | **OPEN → APP-01 thiết kế trước coding** |
| **SQL04-G02 / APP_BLOCKER** | Auth/tenant access/approval/maker–checker chưa chạy; DB FK và role giả lập không đủ. | **OPEN → app test negative, AC-01/12/13** |
| **SQL04-G03 / APP_BLOCKER** | Idempotency mới cục bộ; inbox/outbox, persisted dependency C→P, lost ACK/restart và external effect không được chứng minh. | **OPEN → AC-11/F-01/F-10** |
| **SQL04-G04 / APP_BLOCKER** | Decimal cost/qty/rounding khác giữa ac03 và ac06; UoM fraction, lot/QA, price/VAT chưa có policy mapping vào storage chung. | **OPEN → design explicit conversion/version + tests trước real stock/return** |
| **SQL04-G05 / TEST_GAP** | Two-session contention chỉ verified ở `ac09.Pool` với `SERIALIZABLE` + `UPDLOCK,HOLDLOCK`; AC03 manifest/AR, AC21 custody, AC06 return/revalue, cross-module chưa race-tested. | **OPEN → integrated concurrency/rollback suite** |
| **SQL04-G06 / TEST_GAP** | SQL 2017 compat140, workload/perf, indexes/lock order/deadlock/restore/migrations chưa đo trong production-like environment. | **OPEN → engineering verification theo stack được chọn** |
| **SQL04-G07 / EXTERNAL_GATE** | Hóa đơn/provider, kế toán, pháp lý/retention, cutover toàn kho, EV-01..15/P0/pilot chưa có verification thật. | **PENDING/NO_GO; không kéo vào SQL-only completion** |
| **SQL04-G08 / OWNER_DECISION** | DB engine & tenancy (lịch sử D-01 DB-per-tenant), backend/API/UI/PWA/ORM/hosting, app first slice cần Owner định đoạt theo evidence. | **PENDING; xem handoff** |

**Không có thay đổi SQL schema/semantic trong SQL-04.** Mọi đổi business policy, oracle hoặc các quyết định lịch sử phải có quy trình Owner tại nguồn canonical; không sửa `business/` để đóng gap.

## 6. Handoff acceptance (ở mức tài liệu)

- [x] So Logical ERD với DDL/namespace và đánh dấu rõ phần không tích hợp.
- [x] Liệt kê đủ 21 AC với mức SQL, `EV/P0` tách riêng.
- [x] Review keys/tenant/source, decimal, lock, evidence/races và cách reproduce.
- [x] Gắn GAP ID, tài liệu handoff commands/queries/persistence/test gates.
- [ ] **Independent review PR SQL-04** và xác nhận disposition từng gap.
- [ ] **Owner decision riêng** cho stack/tenancy và quyền bắt đầu app; không giả là đã được phê duyệt.

**Kết luận:** `SQL_EXECUTABLE_REFERENCE_READY_FOR_REVIEW`; **APP_STACK_UNDECIDED**, **APP_INTEGRATION_NOT_RUN**, **GO_LIVE_NOT_ACCEPTED**.
