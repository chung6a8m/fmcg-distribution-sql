# SQL-02 — AC-03 executable SQL (SQL Server 2017+)

**Trạng thái:** **CI_SQL_VERIFIED** trên Windows / SQL Server 2019 LocalDB (compat 150), **2 lần fresh-scratch PASS**; PR #3 đã merge. [Evidence/actual và TestRunIds](../docs/evidence/2026-11-15-sql02-ac03-ci.md), [CI PASS](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43705303178). Đây là SQL executable specification, **không** phải app E2E hoặc Go-Live, không dùng để bật B_ONLINE production.

## Phạm vi và nguồn

- **SQL-ID/AC:** SQL-02 / AC-03 MIXED A+B_ONLINE; BR-03/04/07/11/12/13, SOP-02/03/04, một phần BR-02/10/16.
- **Oracle bất biến:** `../business/reference-data/expected-results/golden-oracles.json#AC-03` (7 checkpoints × 13 cột).
- **Given:** `../business/reference-data/scenarios/business-cases.json#AC-03`; opening riêng MAIN100/value1000, A hold40, B quota30, B grant100, giá bán15. Không dùng master seed.
- **Đơn vị:** `SYNTHETIC_UNITLESS`, `invoiceEligible=false`, không coi 200/375/1000 là VND hay hóa đơn thực.
- **SQL-01:** [Logical ERD](../docs/data-model/logical-erd.md), [invariants](../docs/data-model/invariants.md), [transaction boundaries](../docs/data-model/transaction-boundaries.md), [mapping T0..T6](../docs/data-model/ac03-mapping.md).

Các lựa chọn fixture-only chưa được Owner phê duyệt làm policy: OQ-01 A terms `N=7` có flag synthetic approved tại Confirm; OQ-02 lệnh B31 dùng offered cash465 để **chỉ kiểm lỗi quota**, không ghi receipt; OQ-03 grant B100 có scope `AC03_SYNTHETIC_TRIP`; OQ-04 A held15 chuyển placement về MAIN nhưng chưa tự đóng sạch Trip; OQ-05 fixed unit cost10, price15, DECIMAL exact, không kiểm lot/tax/currency.

**Giới hạn cost provenance:** SQL-02 giả định riêng AC-03 chỉ có một opening cost source/SKU và không có inbound/cost adjustment. Invariant so cost ManifestLine từ opening, so UnloadLine với manifest gốc; không coi đây là chính sách costing/rounding tổng quát (sẽ kiểm riêng ở SQL-03C).

## Cách chạy trên Windows

Yêu cầu: PowerShell 5.1+; SQL Server 2017+ (Developer/Express hoặc LocalDB) với compatibility level từ 140; `sqlcmd` bản ODBC trên PATH; kết nối **Windows Integrated Authentication**; account có quyền `CREATE DATABASE` và `DROP DATABASE` trong instance dùng cho **local scratch**. Không chạy trên SQL Server production/shared.

Từ root repository:

```powershell
# SQL Server Express local
.\sql\run-tests.ps1 -ServerInstance '.\SQLEXPRESS'

# Hoặc LocalDB, nếu đã cài:
.\sql\run-tests.ps1 -ServerInstance '(localdb)\MSSQLLocalDB'

# Giữ scratch DB để soi ledger nếu có lỗi:
.\sql\run-tests.ps1 -ServerInstance '.\SQLEXPRESS' -KeepDatabase
```

Exit code **0** chỉ khi toàn bộ script SQL, negative assertions và 91 comparisons (7×13) PASS; mọi lỗi guard/SQL/oracle/cleanup trả **exit code khác 0**. File evidence ở `sql/test-results/<TestRunId>.json` (bị gitignore), chứa server/instance, version, compatibility, expected/actual/diff từng checkpoint, guard checks, kết quả và cleanup. Khi SQL engine chưa chạy, không được điền số liệu actual/PASS giả.

**Một lệnh tạo scratch DB mới**, prefix `fmcg_sql02_` + GUID32. Không hề cung cấp tùy chọn reuse/reset database có sẵn. Runner yêu cầu tên mới đúng regex, kiểm `master` và `DB_ID` **trước khi CREATE**, tạo bảng `dbo.__Ac03ScratchMarker` ghi harness + đúng DB/instance + nonce, xác minh marker trước mỗi script. Cuối run, trước `DROP` xác minh lại tên/marker/nonce cùng batch. Nếu mất marker hoặc ownership không khớp, **không DROP**, giữ lại scratch để xử lý thủ công. `-KeepDatabase` cố ý không cleanup.

Ví dụ **test bảo vệ target** (mong đợi FAIL, exit code khác 0, không động DB):

```powershell
.\sql\run-tests.ps1 -ServerInstance '.\SQLEXPRESS' -ScratchDatabase master
if ($LASTEXITCODE -eq 0) { throw 'Guard unsafe target unexpectedly passed' }
```

Runner cũng tự thử ba negative probes không phá dữ liệu: tên `master`, database scratch **đã tồn tại**, và marker nonce **sai**. Nếu bất kỳ probe nào được phép đi qua, run FAIL trước schema.

## Dòng thực thi và assertions

| Bước | SQL transaction/effects | Assert |
|---|---|---|
| T0 | Opening +100/value1000; ConfirmA/hold40, B quota30, B grant100, snapshot | Stock100; không AR/COGS/custody |
| T1_LOAD | 2 ManifestLine A40/B30 → 2 movements × 2 legs; 4 rights postings | MAIN30/TRIP70; giữ quyền đủ ở xe; không giao |
| T2_REJECT | B31 đề nghị thanh toán đủ465, quota xe30 → REJECTED audit | Không SourceLine, effect, receipt; 12 numeric = T1 |
| T3_B20 | Delivery B20/COGS200, AR item300, receipt confirmed200, allocate200, grant consume100 | trip50, AR_B100, custody200 |
| T4_A25 | Delivery A25/COGS250, AR item375, dùng A order snapshot | trip25, held A15, AR_A375 |
| T5_HANDOVER | OFFER200 không ledger; cashier ACCEPT200 custody−200/fund+200 | AR giữ, custody0/fund200 |
| T6_RETURN | 2 UnloadLine A15/B10 → 2 movements × 2 legs; chuyển A15 về MAIN, release B10 | MAIN55/TRIP0, held A15, B quota0, AR/COGS không đảo |

`ac03.LiveBalances` derive actual từ StockPosting, DeliveryLine, CogsEffect, RightPosting, AR+Allocations, CustodyEffect/FundEffect; không copy các con số oracle vào bảng expected mới. `CaptureCheckpoint` lưu 7 snapshot **actual**; PowerShell nạp JSON golden gốc bằng `ConvertFrom-Json`, so tên cột đúng thứ tự và so numeric bằng decimal, không dùng FLOAT.

Bộ negative cases có lỗi mong đợi/rollback và kiểm không còn side effect: **N-01** B31, **N-03** load vượt A hold, **N-04** replay/conflict & effect count, **N-06** OFFER không sổ, **N-08** wrong-tenant FK, **N-09** fault sau vài B/transfer effects, **N-11** sourceLineId duy nhất tenant nhưng ordinal có thể trùng khác event, **N-12** wrong-Customer allocation & A Delivery, **N-13** tổng manifest/unload không đổi nhưng dòng/pool/giá trị A/B bị tráo vẫn bị reject; **N-14** sai pool quyền giao B/A, ISSUE trừ nhầm location/SKU, hoặc drift qty theo từng ISSUE trong khi tổng vẫn đúng. Assertion theo từng source movement/2 posting legs, quyền quantity và source provenance. SQL-03A sẽ test **hai SQL sessions thực** tranh BQuota và credit grant; SQL-02 không tuyên bố đã test đồng thời đó.

## File và giới hạn

- `schema/001_ac03.sql`: schema vật lý nhỏ, composite tenant/customer FK, source/effects, view và checkpoint.
- `schema/002_commands.sql`: transaction & idempotency commands LOAD/UNLOAD/B/A/OFFER/ACCEPT, guard precondition, fault injection.
- `schema/003_assert_invariants.sql`: kiểm stock/value, quyền A/B, manifest/unload lineage, receivables, cash/grant.
- `seed/ac03.sql`: fixture T0; `scenarios/ac03.sql`: T1..T6 và rollback/replay tests.
- `tests/negative.sql`: wrong-customer/tenant/source, per-source corruption và retry.
- `run-tests.ps1`: entrypoint + DB guard + compare oracle gốc + evidence.

**Đã xác minh thực tế:** `sqlcmd` chạy SQL Server **2019 LocalDB v15.0.4382.1 / compatibility 150**, 2 lần trên 2 scratch DB khác nhau, mỗi lần 7/7 checkpoints và 91/91 field comparisons PASS (tổng 182 phép so), negative/fault tests PASS, gồm 6 probes mới N-13c/d và N-14a/b/c/d, cleanup guard PASS. CI cũng thực thi lệnh chống target `master`, nhận **exit 1/UNSAFE_TARGET/NO_DATABASE_CREATED**. Artifact chứa JSON expected/actual/diff và môi trường từng run, kể cả negative guard có status FAIL **được mong đợi**. [Xem evidence](../docs/evidence/2026-11-15-sql02-ac03-ci.md).

**Chưa kiểm chứng:** máy Windows của người dùng, SQL Server 2017 compatibility 140, two-session concurrency (SQL-03A), VAT/rounding ngoài AC-03, tài khoản/authorization ở app, provider invoice/accounting, offline recovery, cutover, production tenancy, Go-Live. Bất kỳ thay đổi semantic nào phải thông qua Business Baseline canonical; `business/` và `business.lock.json` không bị sửa.


---

## SQL-03A — AC-09 B credit, atomic transaction và two-session races

**Trạng thái PR #4 (đã merge):** **CI_SQL_VERIFIED** cho executable code SHA `65819b1a5b4e67f875515f52e3ca89c4d2c992a8` sau fix P1 vòng 2. Hai fresh-scratch run PASS ở [SQL-03A run 43716390894](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43716390894), SQL-02 regression [run 43716390923](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43716390923), Business validation [run 43716390903](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43716390903) đều PASS. Xem [evidence/TestRunIds/negative assertions](../docs/evidence/2026-11-15-sql03a-ac09.md). Commit chỉ sửa docs sau executable SHA này cần đối chiếu CI trên final PR HEAD trước merge. Đây chỉ là executable specification; chưa chứng minh AC-11 đầy đủ, app E2E, kế toán/hóa đơn, local SQL Server 2017 compat140 hoặc Go-Live.

**Nguồn bất biến:** `../business/reference-data/scenarios/business-cases.json#AC-09`, `../business/reference-data/expected-results/additional-oracles.json#AC-09`; BR-04/11/12/13/14/16; SOP-03. Không sửa business snapshot hoặc copy expected numeric vào test SQL.

Chạy trên Windows/LocalDB/SQL Server 2017+ (có `sqlcmd`, Windows authentication và quyền tạo/xóa DB scratch):

```powershell
.\sql\run-tests.ps1 -ServerInstance '(localdb)\MSSQLLocalDB' -IncludeSql03A
# Khi cần tự kiểm ledger (database được giữ lại và phải xử lý thủ công):
.\sql\run-tests.ps1 -ServerInstance '.\SQLEXPRESS' -IncludeSql03A -KeepDatabase
```

**Hành vi của tùy chọn:** chạy SQL-02 AC-03 trước (vẫn so 7×13 golden fields), sau đó tạo `ac09` độc lập trên **cùng DB scratch đã xác thực marker/nonce**, chạy 5 nhánh oracle AC-09, kiểm negative/retry/conflict/fault và bắt đầu hai cặp tiến trình `sqlcmd` đồng thời. Cuối cùng xác minh owner marker một lần nữa rồi guarded DROP. Tất cả bước/Oracle/SQL lỗi đều trả exit code khác 0; evidence JSON `sql/test-results/<TestRunId>.json`.

| Nhánh/case | Dữ liệu có nguồn | Các sổ cần xác minh |
|---|---|---|
| CASH_60 | P100, cash confirmed60 | AR40, grant60, custody60 |
| CASH_100 | P100, cash confirmed100 | AR0, grant100, custody100 |
| CASH_60_CREDIT_20 | confirmed cash60, credit20 reserve riêng | AR20, grant80, credit trừ20, custody60 |
| BANK_PENDING | bank evidence pending, verified0 | AR100, grant0, custody0; không allocation/credit/receipt confirmed |
| CASH_OVERPAY_120 | cash thực120, áp100 | AR0, grant100, CustomerCredit mới20, custody120 |

Số trong bảng chỉ minh họa hợp đồng đã freeze; **runner lấy expected trực tiếp từ JSON gốc tại runtime**, so decimal chính xác và xuất expected/actual/differences. Opening quantity1, quota1, cost/unit10 và credit nguồn riêng chỉ là *synthetic fixture assumptions*, không là chính sách thương mại. Credit nguồn mở đầu có `CreditSource` và `CreditReservation` gắn duy nhất với intended `CommandId`; reserve và sale cùng khóa pool, không cho command khác tiêu phần đã giữ. Nguồn CustomerCredit phát sinh từ overpay chưa thể reserve để dùng cho sale mới trong SQL-03A (để SQL-03B). `ac09` giữ command/source identity và các effect theo từng sale; B transaction ghi source, stock/COGS, quota/grant, AR, verified receipt/allocation, reserved CustomerCredit, custody hoặc không ghi gì. Bank pending chỉ có receipt ở trạng thái `PENDING`; cash overpay có allocation100 và credit mới20.

**Concurrency thật:** mỗi race sử dụng **2 `sqlcmd` processes/SQL SPID khác nhau**, barrier persisted đảm bảo cả hai đã bắt đầu trước khi ai hoàn tất. **Một kết nối SQL quan sát độc lập** xác nhận `sys.dm_exec_requests` ghi nhận `LCK_M_*` và KEY lock cùng resource trên `ac09.Pool` giữa hai SPID, lưu dấu vào `RaceLockObservation`; test fail nếu không chứng minh contention. Cần quyền xem cross-session DMV (`VIEW SERVER STATE` trên SQL Server 2017/2019, LocalDB CI owner). `RACE_GRANT`: stock200, BQuota100, grant100; hai command cần exposure80, nên đúng một command được commit và command kia bị từ chối vì grant. `RACE_QUOTA`: stock200, grant1000, BQuota100; hai command qty80, trả cash đủ, nên đúng một commit và command kia bị từ chối vì quota. Cả hai phải chứng minh overlap, SPID khác nhau, error code mong đợi, không duplicate/partial ledger, số dư và amount không âm. **Cơ chế serialization:** `SERIALIZABLE` + `UPDLOCK,HOLDLOCK` trên đúng `ac09.Pool(TenantId,PoolId)` trước đọc quyền và ghi effect; đây là prototype, chưa phải chiến lược locking app được phê duyệt.

**Negative cases:** available credit nhưng chưa reserve / sai CommandId / không đủ source / amount khác reservation đều bị reject; **tạo mới credit reservation sau khi sale cùng CommandId đã ACCEPTED bị reject `53218` không đổi sổ, `AssertPool` vẫn PASS; retry reservation hợp lệ đã tồn tại sau ACCEPTED trả `ALREADY_RESERVED`**; reserve cùng command+payload replay không duplicate; same ID/all-input payload replay không tăng effect; thay đổi receipt amount cùng ID conflict; fault sau stock/COGS rollback command + mọi effect; thiếu quota/grant/reserved CustomerCredit bị reject trước effect; overpay chưa cover đủ payable bị reject; bank pending không làm tăng custody; thử hai ca race độc lập. *Không* kiểm AC-11 phần dependency P→C trước/sau restart hoặc lost ACK durability end-to-end. Những phần này cần slice/evidence riêng.

**File SQL-03A:** `schema/004_ac09.sql` (pool/ledger/view/invariants), `schema/005_ac09_commands.sql` (transaction, idempotency, race barrier), `tests/ac09-negative.sql`, `tests/ac09-races-setup.sql`, `tests/ac09-races-assert.sql`, `include-ac09.ps1` (load oracle, validation, sessions và evidence), workflow `.github/workflows/sql-ac09.yml`. [Evidence](../docs/evidence/2026-11-15-sql03a-ac09.md).

---

## SQL-03B — AC-21 thu, phân bổ, nộp quỹ; AC-20 tạm ứng độc lập

**Trạng thái:** **CI_SQL_VERIFIED / PR #5 chờ review.** [SQL-03B Actions run 43718593857 — PASS](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43718593857) trên executable/test commit `686ac03fe26794db6ce8788473b286324ce84e2f`, 2 scratch độc lập, AC-21 5×6 và AC-20 5×5, negative/rollback/replay và guarded DROP. [Evidence, TestRunIds và artifact](../docs/evidence/2026-11-15-sql03b-ac21-ac20.md). SQL Server 2019 LocalDB compatibility 150 đã chạy; 2017/compat140 NOT_RUN. Engine vẫn là prototype, chưa quyết định database production.

**Nguồn contract (read-only):** `../business/reference-data/scenarios/business-cases.json#AC-21`, `#AC-20`, `../business/reference-data/expected-results/golden-oracles.json#AC-21` (**5 bước × 6 trường**), `#AC-20` (**5 bước × 5 trường**), BR-13/14/16. Tiền thuộc `VND` trên hai ca này, không giống AC-03 synthetic unitleless. Runner **đọc JSON gốc mỗi run**, không hardcode các expected number.

Chạy từ root trên Windows SQL Server LocalDB/Express **riêng để thử nghiệm**, với PowerShell 5.1+, `sqlcmd`, Windows auth và quyền tạo/xóa scratch DB:

```powershell
.\sql\run-tests.ps1 -ServerInstance '(localdb)\MSSQLLocalDB' -IncludeSql03B
# Có thể kết hợp với SQL-03A trên cùng scratch, mỗi namespace độc lập:
.\sql\run-tests.ps1 -ServerInstance '(localdb)\MSSQLLocalDB' -IncludeSql03A -IncludeSql03B
```

Runner bắt buộc chạy AC-03 7×13 regression trước khi chạy SQL-03B; dùng **cùng scratch đã xác thực marker/nonce** rồi guarded DROP. `.github/workflows/sql-ac21.yml` gọi command hai lần, tạo hai DB khác nhau và upload `sql/test-results/*.json`. Exit code khác 0 nếu SQL, negative, oracle hoặc cleanup FAIL.

- `schema/006_ac21.sql`: Scope theo tenant/customer, opening AR item, receipt có nguồn `CONFIRMED/PENDING`, allocation FK tới receipt confirmed và AR item đúng customer, custody posting, handover offer/accept và cashier fund posting; các sổ tạm ứng employee độc lập. `ReceiptCredit`, `CustomerBalances`, `AdvanceBalances` đều **derive từ ledger**, không persist số dư để hợp expected.
- `schema/007_ac21_commands.sql`: `ac21.PostCommand` dùng SERIALIZABLE + UPDLOCK/HOLDLOCK trên `(TenantId,ScopeId)`, durable command hash theo payload; cùng ID/nội dung trả `REPLAY_ACCEPTED`, cùng ID/khác nội dung THROW 53301. `AssertScope` kiểm đối ứng source→posting và số dư không âm.
- `scenarios/ac21.sql`: AC-21 confirm60.000, allocate20.000 +15.000, OFFER50.000 chưa đổi custody/quỹ, cashier ACCEPT50.000 mới custody−50.000/fund+50.000. Sau đó AC-20 issue500.000, approved expense300.000, offer200.000, accept100.000 hai lần; chứng minh tạm ứng không tự trộn AR/credit/custody/quỹ khách.
- `tests/ac21-negative.sql`: receipt PENDING bị từ chối allocation, over-credit/over-AR/over-handover, cross-customer/tenant, FK confirmed-source; idempotent retry/conflict, rollback sau receipt/AR allocation và **giữa custody−/fund+**, quá hạn mức advance, fault rollback; kiểm bất biến và số dư sau mỗi nhánh.
- `include-ac21.ps1`: so **mọi cột** của AC-21 và AC-20 với golden JSON bằng decimal invariant culture; lưu expected/actual/differences và TestRunId ở evidence JSON.

**Giới hạn:** Đây là hai synthetic fixtures, không phải xác minh role thủ quỹ thật, ngân hàng/verified-bank callback, refund đã thực chi, đa đơn hàng/đa collector production, concurrency hai SQL connections riêng của SQL-03B, báo cáo kế toán/hoá đơn, app E2E, EV-06, Owner Acceptance hay go-live. Tất cả source/commands chạy với quyền DB test; authorization và quorum của cashier cần app/security slice riêng. Không sửa `business/` hay `business.lock.json`.
