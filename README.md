# FMCG Distribution — DMS SQL-first Prototype

Repository độc lập để kiểm chứng **mô hình dữ liệu và nghiệp vụ DMS bằng SQL** trước khi chọn toàn bộ tech stack ứng dụng, theo hướng **Business-first dành cho solo developer**. Không phải fork, submodule hoặc subtree của repository nguồn.

## Bắt đầu từ Business Baseline

1. Đọc [Business Specification](business/README.md) và [phạm vi MVP](business/scope.md).
2. Tra cứu [quy tắc](business/business-rules.md), [công thức](business/calculations.md) và [quy trình](business/workflows/).
3. Lấy [acceptance criteria](business/acceptance.md), [scenarios và golden data](business/reference-data/README.md) để xác định expected behavior.
4. Xem [hướng dẫn kiểm chứng](business/validation-guide.md) và [chỉ dẫn cho agent](AGENTS.md).

Nguồn snapshot được ghi tại [business.lock.json](business.lock.json). Thư mục `business/` là **read-only** trong repository ứng dụng: mọi thay đổi ngữ nghĩa phải được đề xuất, xem xét và phê duyệt ở canonical repository trước khi chủ động nâng Business Baseline tại đây. Tài liệu, scenario và golden data đã có trong repository này; không cần mở repository nguồn để phát triển hằng ngày.

## Kiểm tra contract

```sh
python3 tools/validate_business.py
git rev-parse HEAD:business
```

Tree SHA phải bằng `businessTreeSha` trong `business.lock.json`. Workflow `.github/workflows/business-contract.yml` chạy validator khi push/PR. Kết quả chỉ xác nhận **document/model**, không phải implementation verified hoặc tenant go-live accepted.

## Roadmap SQL-first

Xem **[Roadmap triển khai đang hoạt động](docs/roadmap/sql-first.md)**: SQL-01 Logical ERD → SQL-02 AC-03 runnable → SQL-03A/B/C kiểm thử quota/tiền/giá vốn → SQL-04 review & handoff. SQL Server 2017+ được đề xuất **chỉ làm engine thử nghiệm**, chưa phải quyết định DB production hoặc app stack.

## SQL-01 — Logical ERD (đã merge, MODEL_ONLY)

- [ERD và entity/source/snapshot](docs/data-model/logical-erd.md)
- [Bất biến, khóa logic và precision](docs/data-model/invariants.md)
- [Transaction boundaries và concurrency contract](docs/data-model/transaction-boundaries.md)
- [Mapping AC-03 T0..T6 / 13 oracle columns](docs/data-model/ac03-mapping.md)

SQL-01 là **thiết kế logic MODEL_ONLY** đã merge; không phải verification SQL. Những OPEN QUESTION trong ERD/mapping được xử lý **fixture-only** ở SQL-02, không thành production policy. `business/` và expected/oracle vẫn read-only.

## SQL-02 — AC-03 executable (đã merge, CI_SQL_VERIFIED)

Xem [SQL runner, schema, test và hướng dẫn](sql/README.md). Script T-SQL + PowerShell dựng **scratch database có guard**, thực thi T0..T6, so runtime 7×13 giá trị với golden oracle và kiểm âm/replay/fault, kể cả corrupt per-source cost và wrong ISSUE/right provenance. Đã **CI_SQL_VERIFIED** qua **2 lần chạy** trên Windows/SQL Server 2019 LocalDB (compatibility 150), mỗi lần 7/7 checkpoint và 91/91 cột PASS; guard sai target được xác nhận từ chối. [Evidence và TestRunIds](docs/evidence/2026-11-15-sql02-ac03-ci.md) — [CI run](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43705303178). SQL Server 2017/compat140 và máy local của người dùng chưa kiểm trực tiếp.

## SQL-03 — Các invariant khó (đã merge, CI_SQL_VERIFIED)

- **SQL-03A / AC-09:** B credit/cash/pending bank/overpay, atomicity, idempotency và 2 cuộc đua grant/quota qua 2 SQL sessions thật. [Evidence](docs/evidence/2026-11-15-sql03a-ac09.md) — [PR #4](https://github.com/chung6a8m/fmcg-distribution-sql/pull/4).
- **SQL-03B / AC-21 & AC-20:** receipt/allocation/custody/fund và advance độc lập, rollback/replay. [Evidence](docs/evidence/2026-11-15-sql03b-ac21-ac20.md) — [PR #5](https://github.com/chung6a8m/fmcg-distribution-sql/pull/5).
- **SQL-03C / AC-06:** moving average theo source/location, cumulative refunds, exact rounding và adjustment forward ở kỳ mở. [Final CI PASS](https://github.com/chung6a8m/fmcg-distribution-sql/actions/runs/43726916416) — [PR #6 đã merge](https://github.com/chung6a8m/fmcg-distribution-sql/pull/6).

Các ca SQL-03A/B/C dùng **schema namespace riêng để thử nghiệm**, chưa phải một physical model ứng dụng tích hợp. Hướng dẫn chạy và guard tại [sql/README.md](sql/README.md).

## SQL-04 — Review và handoff (HANDOFF_CANDIDATE / chờ PR review)

- [Review Logical ERD ↔ schema, constraints/concurrency, ma trận **21 AC** và gaps SQL04-G01..08](docs/handoff/sql04-review.md).
- [Application handoff: candidate APP-01, commands/queries, test gates, persistence ownership, **OWN-SQL04-01..06 PENDING**](docs/handoff/sql04-app-handoff.md).

**Trạng thái tổng:** Business Baseline v1.0 freeze và read-only; SQL-01 MODEL_ONLY, SQL-02/03A/B/C đã merge với bằng chứng **CI_SQL_VERIFIED chỉ trong phạm vi SQL** trên Windows SQL Server 2019 LocalDB/compat150. SQL-04 đang review tài liệu bàn giao; **chưa quyết định** database production, tenancy topology, backend, UI/PWA, ORM hoặc hosting. Không có application E2E, EV-01..15, P0 gate hoặc tenant Go-Live acceptance từ các SQL tests.
