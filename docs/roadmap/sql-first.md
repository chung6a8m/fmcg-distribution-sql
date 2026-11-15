# Roadmap SQL-first — Data Model → SQL Simulation → Application

- **Ngày lập:** 2026-11-15
- **Trạng thái:** ACTIVE — SQL-01 đã merge (MODEL_ONLY); SQL-02 **CI_SQL_VERIFIED** (2 fresh scratch runs PASS), PR review/merge pending; SQL-03..04 TODO. [Evidence SQL-02](../evidence/2026-11-15-sql02-ac03-ci.md).
- **Repository thực hiện:** `chung6a8m/fmcg-distribution-sql`.
- **Nguồn contract:** `business-v1.0.0` tại `business.lock.json` (source commit `88d70b3be72f34011b49b0de265ad2c43202492f`; tree `business/` = `c9a4164a99ea57e1d5f9bc8711285c6d3705f8e3`).
- **Mục tiêu:** Có ERD đủ dùng, một mô phỏng SQL chạy được, và kiểm chứng một số bất biến khó nhất trước khi chọn backend/UI/ORM.

## 1. Nguyên tắc triển khai

1. **Business-first:** `business/` và expected/oracles là read-only. Nếu phát hiện mâu thuẫn, ghi finding + BR/AC/SOP/đầu vào bị ảnh hưởng; không sửa expected để SQL pass, không tự đổi ngữ nghĩa nghiệp vụ trong repo này.
2. **Vertical slice thay vì ERD toàn hệ thống:** thiết kế và chạy **AC-03 (Mixed A+B_ONLINE)** trước. Chỉ mở rộng bảng/quan hệ khi một scenario tiếp theo cần.
3. **Data model ≠ DB engine:** logical ERD, transaction boundaries, invariants độc lập DB; physical DDL và SQL test dùng **SQL Server 2017+ làm engine prototype tạm chọn** (Developer/Express hoặc môi trường local tương đương). Đây **không** phải quyết định DB production, database-per-tenant hay application tech stack.
4. **SQL là executable specification**, không phải backend production. Cho phép T-SQL transaction, procedure nhỏ khi có lý do; không bắt buộc đưa toàn bộ business logic vào stored procedures hoặc quyết định ORM/API/frontend ở giai đoạn này.
5. **Chứng cứ phân cấp:** kiểm tài liệu/model, SQL implementation local, app integrated E2E, tenant go-live là các cấp khác nhau. SQL pass không xác nhận kênh hóa đơn, security xuyên tầng, cutover toàn kho, restore hay pilot.
6. **Solo developer:** PR nhỏ, script reset và chạy lại được, không dựng microservice, migration framework, test platform hay governance mới chỉ để bắt đầu.

## 2. Đường đi và trạng thái

| Chặng | Trạng thái | Mục tiêu / AC | Đầu ra và điều kiện hoàn tất |
|---|---|---|---|
| **SQL-01 — Logical ERD** | MERGED / MODEL_ONLY | Domain → quan hệ, source, snapshot, bất biến, transaction boundaries cho **AC-03** (BR-03/04/07/11/12/13) | ERD slice + mapping từng bước AC-03 + quy tắc khóa/unique/decimal; không còn dữ liệu chủ chốt chưa có chỗ lưu |
| **SQL-02 — AC-03 SQL executable** | CI_SQL_VERIFIED / PR_IN_REVIEW | SQL DDL tối thiểu, opening và 7 checkpoints `T0..T6`; test cả B31 bị reject | Một lệnh local chạy lại từ **scratch database được xác thực**; mọi cột ở oracle AC-03 khớp từng checkpoint; reject không tạo side effect |
| **SQL-03A — B credit, atomicity** | TODO | **AC-09** và fault liên quan **AC-11** (BR-04/11/12/14/16) | Cash, reserved credit, bank pending, overpay; retry cùng ID/cùng payload một effect, khác payload conflict; **hai ca độc lập trên 2 kết nối thật** tranh credit grant và BQuota đều không cùng commit |
| **SQL-03B — Thu, phân bổ, nộp quỹ** | TODO | **AC-21** (BR-13/14), có thể bổ sung **AC-20** nếu nhỏ | AR/CustomerCredit/custody/fund độc lập; OFFER chưa chuyển sổ; cashier ACCEPT mới chuyển; số dư từng bước trùng oracle |
| **SQL-03C — Giá vốn và hoàn** | TODO | **AC-06** (BR-07/20) | Cumulative source-cost refund, rounding residual, late adjustment sau khóa kỳ; không sửa bản ghi kỳ khóa; tất cả số khớp oracle |
| **SQL-04 — Review và handoff cho app** | TODO | Đánh giá mô hình sau các SQL scenarios | Review constraints/concurrency, ghi gap và quyết định còn mở; xác định vertical slice app đầu tiên và tiêu chí kiểm thử; **sau đó mới chốt app stack** |

**Đường găng:** SQL-01 → SQL-02 → SQL-03A/B/C → SQL-04. Các phần SQL-03 có thể tạo PR nhỏ độc lập sau khi SQL-02 được chấp nhận; không cần hoàn thiện toàn bộ 21 AC rồi mới bắt đầu app.

## 3. SQL-01 — Phân rã cho Codex

**Phạm vi nguồn cần đọc:** `business/domain-model.md`, `business/business-rules.md`, `business/calculations.md`, `business/workflows/mixed.md`, `business/workflows/module-a.md`, `business/workflows/module-b-online.md`, `business/acceptance.md`; scenario AC-03, `golden-oracles.json`.

- [x] Dựng **logical ERD bằng Mermaid**, nhóm rành mạch: tenant/seller & customer/ship-to snapshot; SKU/UoM/location; A order/reservation; trip/manifest/B quota; delivery/B sale; stock movements/cost balance; AR/open item; receipt/custody/handover. Chỉ thể hiện các entity/quan hệ cần cho AC-03; ghi rõ những nhóm tạm hoãn.
- [x] Phân biệt **master**, **snapshot trên chứng từ**, **business event/source**, **ledger effects** và **derived balances**. Mỗi hiệu ứng truy được tới source line; không lấy trạng thái master hiện tại để viết lại lịch sử.
- [x] Đề xuất **keys, cardinality, uniqueness/idempotency scope, tenant boundary, quantities/decimal precision, check constraints** và chỗ cần transaction/locking. Không khẳng định SQL constraints một mình bảo đảm toàn bộ authorization.
- [x] Đặc tả **quyền lượng không chồng nhau** giữa AReservation/BQuota, stock transfer kho→xe (không doanh thu/AR/COGS), A Delivery theo phần giao, B SaleDeliveryReceipt atomic, receipt và handover là effect riêng.
- [x] Bảng mapping **AC-03 T0, T1_LOAD, T2_REJECT, T3_B20, T4_A25, T5_HANDOVER, T6_RETURN** → command → entities/effects → invariants → oracle columns. Ghi các chỗ chưa rõ là `OPEN QUESTION`, không tự hợp thức hóa.
- [x] SQL-01 đã review/merge; SQL-02 cụ thể hóa những OQ thành **synthetic test setup** chứ không thành policy sản phẩm.

**Tài liệu thiết kế SQL-01 đã merge:** [Logical ERD](../data-model/logical-erd.md), [invariants](../data-model/invariants.md), [transaction boundaries](../data-model/transaction-boundaries.md), [AC-03 mapping](../data-model/ac03-mapping.md). Các OPEN QUESTION được ghi rõ; chưa phê duyệt physical schema và chưa chạy SQL tests.

**Exit SQL-01:** tất cả checkpoints AC-03 đã ánh xạ được nguồn, quan hệ, mutation/derived balance và ít nhất một chiến lược enforce bất biến (DB constraint hoặc transaction logic/test); mọi giả định mở được nêu.

## 4. SQL-02 — Mô phỏng thực sự trên SQL Server

- [x] Tạo **minimal physical schema** từ SQL-01; có PK/FK/unique/check/index cần thiết, decimal exact cho tiền/giá vốn/lượng, source identity và scope tenant. Không đưa DDL production hoặc tối ưu premature.
- [x] Script dựng database thử nghiệm, reset/seed sạch theo opening snapshot **riêng của AC-03**. `business/reference-data/master-data/seed.json` là tham chiếu khái niệm, **không** phải opening AC-03; giá trị AC-03 có unit `SYNTHETIC_UNITLESS`, không diễn giải là VND.
- [x] **Guard database thử nghiệm trước mọi thao tác phá hủy (`DROP`/`TRUNCATE`/reset):** mặc định tạo database scratch riêng cho run; kiểm tra rõ server/instance và database đích, không dựa vào tên database đơn thuần. Nếu tái sử dụng scratch DB, phải xác thực marker sở hữu do harness tạo trong DB; từ chối DB hệ thống, DB tồn tại không có marker đúng, hoặc target không hợp lệ. Guard thất bại → dừng **trước mutation**, lệnh trả exit code khác 0; có negative test trỏ nhầm DB để xác minh từ chối. Không được reset dữ liệu ngoài phạm vi test.
- [x] Chạy lần lượt `T0` (MAIN100 @ value1000, A hold40/B quota30), `T1_LOAD` (load70), `T2_REJECT` (B31 fail, state unchanged), `T3_B20` (B20/receipt200/AR_B100), `T4_A25` (A25/AR_A375), `T5_HANDOVER` (cashier accepted200), `T6_RETURN` (xe trả25).
- [x] **Assert đủ 13 cột** `step, mainQty, tripQty, soldQty, mainCost, tripCost, cogs, aHold, bQuota, arA, arB, custody, fund` so với `business/reference-data/expected-results/golden-oracles.json#AC-03`. Harness đọc JSON gốc tại runtime hoặc sinh expected từ JSON một cách xác định; **không chép tay một bộ golden mới**.
- [x] Khẳng định các bất biến: không âm, bảo toàn qty/value, không double-consume A/B, load không sinh COGS/AR, reject không ghi dở, custody chỉ giảm khi cashier accept, B effects cùng commit/rollback.
- [x] Có lệnh chạy **một bước** từ local Windows (ví dụ PowerShell + `sqlcmd`), chỉ yêu cầu SQL Server/`sqlcmd`; reset độc lập để chạy nhiều lần. Kết quả PASS/FAIL rõ ràng; lỗi SQL/test làm command trả exit code khác 0.
- [x] Bàn giao README chạy test, phiên bản SQL Server/compatibility level, actual vs expected theo bước, logs, những điều chưa thử. Không tự chấm full E2E.

**Đã triển khai:** `sql/schema/`, `sql/seed/`, `sql/scenarios/ac03.sql`, `sql/tests/`, `sql/run-tests.ps1`, `sql/README.md` và CI verification. Entrypoint duy nhất `sql/run-tests.ps1` (mỗi run tạo scratch mới).

**Exit SQL-02 (gate sang SQL-03):** schema dựng từ scratch DB sạch, AC-03 chạy lặp lại PASS, T2 không có tác động, all 13 oracle fields từng bước khớp; kiểm thử target DB sai/không có marker phải FAIL trước mutation với exit code khác 0. **Technical evidence đã đạt trên Windows SQL Server 2019 LocalDB compat150**; [run và artifact](../evidence/2026-11-15-sql02-ac03-ci.md). **Review/merge PR #3 vẫn pending**. Oracle AC-03 đánh dấu `MODEL_ONLY` ở nguồn; SQL CI PASS không nâng AC E2E/EV/go-live.

## 5. SQL-03 — Các ca khó cần ưu tiên

### SQL-03A — AC-09 + phần liên quan AC-11

- Cash 60/100, cash 60 + reserved credit 20, bank pending, overpay120 theo `additional-oracles.json#AC-09`; AR/quota/grant/credit/custody chính xác.
- Một transaction B phải ghi toàn bộ sale/delivery, stock/cost, receipt/allocation, open AR, quota/grant/credit source effects hoặc **không ghi gì**. Thử fault sau ghi giữa chừng.
- Gửi lại cùng command ID + payload → không nhân đôi effect; cùng ID + payload khác → conflict. Kịch bản dependency/persistence đầy đủ của AC-11 **chưa được tuyên bố hoàn tất** nếu mới thử retry.
- **Concurrency thật — credit grant (AC-09):** 2 SQL sessions, hai command ID khác nhau cùng tranh grant100, mỗi bên cần exposure80; bố trí BQuota và tồn xe đủ cho cả hai để **chỉ grant là giới hạn tranh chấp**. Không cả hai commit.
- **Concurrency thật — BQuota (BR-04/11/12, SOP-03):** 2 SQL sessions, hai command ID khác nhau cùng tranh BQuota100, mỗi bên bán qty80; bố trí credit grant đủ rộng (hoặc verified receipt đủ để exposure không là giới hạn) để **chỉ BQuota là giới hạn tranh chấp**. Không cả hai commit.
- Sau mỗi ca, xác minh persisted stock/BQuota/grant không âm hoặc vượt quyền, chỉ có effect của các command đã commit, không có partial effect/duplicate; thử commit/rollback bằng **2 kết nối đồng thời thật**, không thay bằng các lần chạy tuần tự. Không đổi oracle AC-09 gốc.
- Gate: assertions, negative tests, **evidence riêng cho cả hai ca grant và quota**, xác định rõ locking/serialization mechanism.

### SQL-03B — AC-21 (AC-20 tùy chọn)

- Receipt cash60.000 confirmed trên AR140.000; allocate20.000 +15.000, offer50.000, cashier accept50.000; kết thúc AR105.000/credit25.000/custody10.000/fund50.000.
- OFFER không tác động custody/fund; handover không trừ AR lần hai; receipt chưa verified không được coi confirmed; số âm và over-allocation bị chặn.
- Nếu phạm vi không phình: AC-20 advance500.000/expense300.000/offer200.000/cashier accept100.000×2; AdvanceLedger **không** trộn AR/cash custody.
- Gate: đối chiếu từng bước với golden AC-21 (và AC-20 nếu đưa vào), đủ thử reject/rollback, trace từng source.

### SQL-03C — AC-06

- Moving average theo SKU × StockLocation và **cost source snapshot**; tách rõ giá vốn xuất khỏi công thức hoàn giá trị nguồn.
- Nguồn 2 đơn vị cost6.667, hoàn lần đầu3.334; original second3.333; sau nguồn adjustment cost6.768, ghi forward adjustment +50 và lần sau3.384 → tổng6.768.
- Không mutate kỳ khóa; source adjustments/reversal có định danh, không hoàn vượt lượng/giá trị nguồn; kiểm rounding residual.
- Gate: đối chiếu `additional-oracles.json#AC-06` và test âm cho locked-period mutation/over-return.

> **Phạm vi không đồng nhất:** SQL-03 chỉ kiểm các AC nêu trên. AC-02/08 (Customer/ShipTo/terms snapshot), AC-05/07/19 (lot/QA, quà, VAT/return) cần thêm slice khi app đầu tiên đụng tới; không tự tuyên bố tất cả BR hoặc MVP đã đạt.

## 6. SQL-04 — Handoff và quyết định stack

Khi SQL-03A/B/C hoàn tất, review một lần:

- [ ] Logical ERD và physical schema tương thích với các test đã chạy; chỉ rõ entity tạm thời, debt/limitations, key/tenant/source/decimal/index/lock và cách reproduce.
- [ ] Báo cáo **AC coverage**: SQL verified / model-only / not-run / external-blocked; không nâng `EV-01..15`, P0 gates hoặc Go-Live status dựa vào SQL simulation.
- [ ] Xác định contract cho app: commands/queries, transaction boundary, audit/idempotency, persistence ownership; stored procedure nào là prototype, phần nào cần chuyển vào application service.
- [ ] **Owner quyết định sau khi có evidence:** engine DB sản phẩm, database-per-tenant hay cách cô lập khác, backend/API/UI/ORM/hosting và app vertical slice đầu tiên. Quyết định lịch sử về database-per-tenant/PWA trong `business/constraints.md` không tự bị bãi bỏ.
- [ ] Tạo handoff ngắn cho application repo nếu cần, không bắt buộc thêm repo/code app trong roadmap SQL này.

**Exit SQL-04:** SQL prototype kiểm chứng được những invariants ưu tiên, biết rõ giới hạn, có backlog app slice và các quyết định pending. Chưa có app/integration/go-live pass.

## 7. Quy tắc PR, tracking và evidence

- **PR SQL-01:** tách riêng 4 tài liệu logical ERD để review trước khi chốt DDL. **PR tiếp theo SQL-02:** schema/seed/run-tests AC-03 có oracle assertions. SQL-03A, B, C tiếp tục là các PR riêng để tránh PR khổng lồ.
- Mỗi PR ghi: `SQL-ID`, BR/AC/SOP liên quan, input fixture/path/commit, expected oracle ref, actual/command, engine/build/compatibility level, negative/fault coverage, testRunId hoặc log, trạng thái `PASS/FAIL/NOT_RUN/BLOCKED` và giới hạn kiểm chứng.
- Không chỉnh `business/`, `business.lock.json` hoặc workflow business-contract để làm xanh SQL test. Kiểm `python3 tools/validate_business.py` và `git rev-parse HEAD:business` ở mỗi PR.
- Khi chưa có SQL source, **mọi SQL task vẫn TODO**, không ghi pass giả. Một ca chỉ được đánh dấu local SQL verified khi có command thật, actual, environment, người kiểm xác nhận. Không thay đổi expected data.
- CI SQL có thể bổ sung sau khi có local harness chạy ổn, **không là điều kiện tiên quyết để bắt đầu SQL-01/02**.
- Tài liệu triển khai trong repo SQL đủ tự chứa để làm việc hằng ngày; link canonical chỉ cho provenance. Giữ tiếng Việt, LF/UTF-8, PR gọn.

## 8. Ngoài phạm vi roadmap này

Không xây app shell/API/UI/auth hay lựa chọn ORM; không xây hạ tầng cloud/CI phức tạp, ledger kế toán hoàn chỉnh, hóa đơn provider thật, offline sync production, tenant migration, cutover Kho-01 thật, PWA, chứng cứ pháp lý, pilot NPP-01. Các mục này thuộc lộ trình ứng dụng/verification riêng; các gate G-STOCK/G-CUT/G-IDEMP/G-LEDGER/G-INV vẫn chưa được miễn hoặc hoàn tất.

**Bước hiện tại:** SQL-02 đã PASS hai run độc lập trên **SQL Server 2019 LocalDB / compatibility 150**, có [guard test, logs/actual và TestRunIds](../evidence/2026-11-15-sql02-ac03-ci.md). Tiếp theo review findings PR #3 và merge khi đạt; SQL Server 2017/compat140 chưa xác nhận riêng. Sau đó mở SQL-03A/B/C; không cần chọn app stack trước.
