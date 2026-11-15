# AGENTS.md — DMS Product Repository

Repository này dành cho **phát triển sản phẩm**, sử dụng Business Baseline v1.0 đã freeze. Ưu tiên giải pháp nhỏ, dễ hiểu và kiểm thử được cho solo developer.

## Nguồn yêu cầu

- Bắt đầu bằng `business/README.md`, `business/scope.md`, `business/glossary.md` và các BR/POL/SOP liên quan.
- Lấy công thức tại `business/calculations.md`, AC tại `business/acceptance.md`, scenarios và expected tại `business/reference-data/`.
- `business.lock.json` xác định chính xác phiên bản đang dùng. Các link provenance chỉ dùng truy xuất lịch sử, không phải tài liệu bắt buộc phải mở để hiểu nghiệp vụ hằng ngày.

## Phạm vi chỉnh sửa

- **KHÔNG sửa `business/` trong Product Repository**, kể cả sửa wording, data mẫu, expected/oracle hay làm xanh test. Đây là snapshot read-only.
- Nếu cần đổi ý nghĩa nghiệp vụ: ghi ID BR/POL/SOP/AC liên quan, khác biệt trước/sau và tác động; đề xuất để Owner xem xét/phê duyệt tại **canonical repository**. Chỉ nâng `business/` và `business.lock.json` cùng nhau sau khi nguồn được phê duyệt; đối chiếu lại Git tree SHA và chạy validator.
- Mọi source, test, tài liệu triển khai về sau nằm **ngoài `business/`**; sử dụng contract trong repo này, không tạo phụ thuộc runtime vào repo canonical.
- Không chỉnh sửa canonical repository từ nhiệm vụ làm việc trên repo này. Không tự giả định rằng mô tả nghiệp vụ đã được Product Verification hoặc tenant Go-Live Acceptance.

## Cách triển khai SQL-first

- Roadmap SQL-first tại `docs/roadmap/sql-first.md` **đã hoàn tất review/handoff**; Owner đã phê duyệt `docs/decisions/2026-11-15-owner-app-decisions.md` và `docs/roadmap/app-00-app-01.md`. **Không tạo app/API/UI/ORM trong repository SQL**; ứng dụng phải sống trong repository độc lập đã xác minh.
- SQL Server 2019 LocalDB compat150 chỉ là **engine đã được SQL CI kiểm chứng**, không phải production verification. Owner đã chọn **SQL Server + database-per-tenant, .NET 10/ASP.NET Core/Dapper/FluentMigrator, React PWA online-first, local-first CI** và APP-00/01 synthetic authorization. Không biến T-SQL scratch schemas thành app schema mặc định.
- Golden oracles tại `business/reference-data/expected-results/` phải được test harness đọc/derive xác định từ nguồn; không sao chép expected thủ công rồi chỉnh để PASS.
- Với SQL scenarios, thử cả **transaction rollback, negative tests, idempotency và đồng thời thực** khi được yêu cầu, kèm logs/actual/environment; test SQL không chứng minh app E2E hoặc tenant go-live.
- Với mỗi vertical slice: chỉ ra BR/POL/SOP/AC, scenario/fixture, expected, negative cases và cách kiểm tra actual; phân biệt **MODEL_ONLY / NOT_RUN**, local verified, integrated verified và go-live accepted.
- Bảo toàn bất biến tenant isolation, quyền phê duyệt, giá vốn, hàng trên chuyến, công nợ, tiền giữ hộ, tạm ứng, idempotency và audit theo contract. Không sửa golden data để hợp với implementation.
- Chọn cách làm tối thiểu, tránh thêm service, CI gate, tài liệu quản trị hoặc framework chưa cần.

## Kiểm chứng thay đổi

- Chạy `python3 tools/validate_business.py`; chạy kiểm thử thực tế của slice khi có source.
- Với thay đổi baseline có phê duyệt, kiểm `git rev-parse HEAD:business` trùng `businessTreeSha` trong lock.
- Validator và GitHub Actions chỉ kiểm tài liệu/model; không chứng minh E2E, integration hoặc go-live.
- Viết tài liệu tiếng Việt, ưu tiên UTF-8/LF, link tương đối nội bộ và PR nhỏ, có thể review.
