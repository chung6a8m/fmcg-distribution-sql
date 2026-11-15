# Business Specification — MVP v1 candidate

Đây là **đặc tả nghiệp vụ tự đủ nội dung**, là đầu vào cho nhiều cách triển khai công nghệ khác nhau. Không phải báo cáo nghiên cứu, API/DDL, tài liệu kiến trúc hay xác nhận sản phẩm đã vận hành.

**Mức hiện tại:** bản biên tập từ Product Baseline C′ đã được Owner chấp nhận ở phạm vi **PRODUCT_POLICY_AND_CONTRACT_ONLY**. Việc chuyển đổi sang cấu trúc mới vẫn phải được Owner review; **BUSINESS_BASELINE_APPROVED cho repository mới = PENDING**.

## Đọc tài liệu theo công việc

| Nhu cầu | Tài liệu |
|---|---|
| Hiểu khách hàng/mục tiêu, MVP và giới hạn | [scope.md](scope.md) |
| Tra cứu một thuật ngữ | [glossary.md](glossary.md) |
| Quan hệ dữ liệu, nguồn sự thật và trạng thái | [domain-model.md](domain-model.md) |
| Làm theo một luồng A, B, Mixed hoặc nghiệp vụ vận hành | [workflows](workflows/) |
| Kiểm logic và invariants | [business-rules.md](business-rules.md) |
| Biết cấu hình/approval được phép | [policies.md](policies.md), [roles-and-approvals.md](roles-and-approvals.md) |
| Biết quyết định đã có, điểm còn mở | [decisions.md](decisions.md), [constraints.md](constraints.md) |
| Truy vết ID | [traceability.md](traceability.md) |
| Kiểm xuất xứ khi có nghi ngờ | [provenance.md](provenance.md) |

**B02 candidate:** [công thức](calculations.md), [21 acceptance criteria](acceptance.md), [golden data](reference-data/README.md), [hướng dẫn kiểm chứng](validation-guide.md) và [change log](CHANGELOG.md). Không coi những file này đã được Owner chấp nhận chỉ vì có mặt trong PR.

## Cách hiểu mức độ bắt buộc

- **L0:** bất biến của sản phẩm, không cho tenant cấu hình để phá vỡ.
- **L1:** chính sách có thể cấu hình hữu hạn, có phạm vi, hiệu lực, lịch sử và quyền phê duyệt.
- **L2:** ngoại lệ có nguồn và kiểm soát, không phải bỏ qua L0.
- **DEFERRED/BLOCKED:** ngoài phạm vi hoặc chưa đủ điều kiện bật thật.
- **PENDING/NOT_RUN/MODEL_ONLY:** chưa đủ chứng cứ trên hệ thống thật.

## Ranh giới cần luôn giữ

**Business policy approved ≠ Implementation verified ≠ Tenant go-live accepted.** Không tự mở A/B/Mixed trên production, không miễn P0 và không giả dữ liệu nghiên cứu thành số liệu thực.

Không có quyết định chọn stack, cơ sở dữ liệu, runtime, UI framework, giao thức, cloud hay deployment trong thư mục business. Những lựa chọn kỹ thuật lịch sử được giữ trong [constraints](constraints.md) để hỏi lại khi vào implementation, không bị xóa khỏi lịch sử.
