# SQL-02 — AC-03 executable SQL (SQL Server 2017+)

**Trạng thái:** IMPLEMENTED / **SQL_ENGINE_NOT_RUN** tại thời điểm tạo PR. Đây là executable specification cho slice AC-03, chưa phải chứng cứ SQL PASS, app E2E hoặc Go-Live. Không dùng để bật B_ONLINE production.

## Phạm vi và nguồn

- **SQL-ID/AC:** SQL-02 / AC-03 MIXED A+B_ONLINE; BR-03/04/07/11/12/13, SOP-02/03/04, một phần BR-02/10/16.
- **Oracle bất biến:** `../business/reference-data/expected-results/golden-oracles.json#AC-03` (7 checkpoints × 13 cột).
- **Given:** `../business/reference-data/scenarios/business-cases.json#AC-03`; opening riêng MAIN100/value1000, A hold40, B quota30, B grant100, giá bán15. Không dùng master seed.
- **Đơn vị:** `SYNTHETIC_UNITLESS`, `invoiceEligible=false`, không coi 200/375/1000 là VND hay hóa đơn thực.
- **SQL-01:** [Logical ERD](../docs/data-model/logical-erd.md), [invariants](../docs/data-model/invariants.md), [transaction boundaries](../docs/data-model/transaction-boundaries.md), [mapping T0..T6](../docs/data-model/ac03-mapping.md).

Các lựa chọn fixture-only chưa được Owner phê duyệt làm policy: OQ-01 A terms `N=7` có flag synthetic approved tại Confirm; OQ-02 lệnh B31 dùng offered cash465 để **chỉ kiểm lỗi quota**, không ghi receipt; OQ-03 grant B100 có scope `AC03_SYNTHETIC_TRIP`; OQ-04 A held15 chuyển placement về MAIN nhưng chưa tự đóng sạch Trip; OQ-05 fixed unit cost10, price15, DECIMAL exact, không kiểm lot/tax/currency.

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

Bộ negative cases có lỗi mong đợi/rollback và kiểm không còn side effect: **N-01** B31, **N-03** load vượt A hold, **N-04** replay/conflict & effect count, **N-06** OFFER không sổ, **N-08** wrong-tenant FK, **N-09** fault sau vài B/transfer effects, **N-11** sourceLineId duy nhất tenant nhưng ordinal có thể trùng khác event, **N-12** wrong-Customer allocation & A Delivery, **N-13** tổng manifest không đổi nhưng dòng/pool giả sai. Assertion theo từng source movement/2 posting legs, quyền quantity và source provenance. SQL-03A sẽ test **hai SQL sessions thực** tranh BQuota và credit grant; SQL-02 không tuyên bố đã test đồng thời đó.

## File và giới hạn

- `schema/001_ac03.sql`: schema vật lý nhỏ, composite tenant/customer FK, source/effects, view và checkpoint.
- `schema/002_commands.sql`: transaction & idempotency commands LOAD/UNLOAD/B/A/OFFER/ACCEPT, guard precondition, fault injection.
- `schema/003_assert_invariants.sql`: kiểm stock/value, quyền A/B, manifest/unload lineage, receivables, cash/grant.
- `seed/ac03.sql`: fixture T0; `scenarios/ac03.sql`: T1..T6 và rollback/replay tests.
- `tests/negative.sql`: wrong-customer/tenant/source, per-source corruption và retry.
- `run-tests.ps1`: entrypoint + DB guard + compare oracle gốc + evidence.

**Chưa kiểm chứng:** SQL engine actual/compatibility/build/log, two-session concurrency, VAT/rounding ngoài AC-03, tài khoản/authorization ở app, provider invoice/accounting, offline recovery, cutover, production tenancy, Go-Live. Bất kỳ thay đổi semantic nào phải thông qua Business Baseline canonical; `business/` và `business.lock.json` không bị sửa.
