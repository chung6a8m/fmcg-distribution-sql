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

## SQL-02 — AC-03 executable (PR triển khai)

Xem [SQL runner, schema, test và hướng dẫn](sql/README.md). Script T-SQL + PowerShell dựng **scratch database có guard**, thực thi T0..T6, so runtime 7×13 giá trị với golden oracle và kiểm âm/replay/fault. **Code đã viết nhưng SQL_ENGINE_NOT_RUN** trong môi trường tác giả PR; chỉ nâng trạng thái khi có kết quả trên SQL Server thật cùng evidence.

## Trạng thái

**Business Baseline v1.0** đã freeze; SQL-01 đã merge dưới dạng MODEL_ONLY. SQL-02 đang được triển khai trên PR (chưa xác nhận engine/actual), SQL-03A/B/C và SQL-04 chưa triển khai. Chưa chọn backend/UI/ORM hoặc database production; không đánh dấu AC/EV là verified.
