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

## Cách triển khai sau khi chọn stack

- **Hiện chưa chọn tech stack, chưa có source và chưa có roadmap.** Không tự thêm những nội dung này khi chưa được yêu cầu.
- Với mỗi vertical slice: chỉ ra BR/POL/SOP/AC, scenario/fixture, expected, negative cases và cách kiểm tra actual; phân biệt **MODEL_ONLY / NOT_RUN**, local verified, integrated verified và go-live accepted.
- Bảo toàn bất biến tenant isolation, quyền phê duyệt, giá vốn, hàng trên chuyến, công nợ, tiền giữ hộ, tạm ứng, idempotency và audit theo contract. Không sửa golden data để hợp với implementation.
- Chọn cách làm tối thiểu, tránh thêm service, CI gate, tài liệu quản trị hoặc framework chưa cần.

## Kiểm chứng thay đổi

- Chạy `python3 tools/validate_business.py`; chạy kiểm thử thực tế của slice khi có source.
- Với thay đổi baseline có phê duyệt, kiểm `git rev-parse HEAD:business` trùng `businessTreeSha` trong lock.
- Validator và GitHub Actions chỉ kiểm tài liệu/model; không chứng minh E2E, integration hoặc go-live.
- Viết tài liệu tiếng Việt, ưu tiên UTF-8/LF, link tương đối nội bộ và PR nhỏ, có thể review.
