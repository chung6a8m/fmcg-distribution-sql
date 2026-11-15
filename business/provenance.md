# Xuất xứ, tính toàn vẹn và quy tắc chuyển đổi nguồn

## 1. Baseline nguồn đã được ký chấp nhận trong phạm vi tài liệu

- **Research repo:** https://github.com/chung6a8m/research-sme-phan-phoi-hang-tieu-dung
- **Product Contract C′ đã chấp nhận:** [commit eb9c4b04e334530367b80ea4178edb4dd4a07491](https://github.com/chung6a8m/research-sme-phan-phoi-hang-tieu-dung/commit/eb9c4b04e334530367b80ea4178edb4dd4a07491)
- **Owner Acceptance record:** [PR #2 — comment phê duyệt](https://github.com/chung6a8m/research-sme-phan-phoi-hang-tieu-dung/pull/2#issuecomment-6866595994), ghi nhận phạm vi PRODUCT_POLICY_AND_CONTRACT_ONLY.
- **Record metadata:** [acceptance-record-r](https://github.com/chung6a8m/research-sme-phan-phoi-hang-tieu-dung/tree/main/reports/2026-11-13-10-product-reference-go-live-blueprint/s5/acceptance-record-r) xác nhận 6 role-scoped refs **không phải 6 reviewer độc lập**.
- **Nguồn nghiệp vụ cốt lõi:** R009 — D-01..15, BR-01..24, DC-01..18, AC-01..21, EV-01..15 và R010 — PADR-01..09, EVQ-01..07, POL/CFG, SOP-01..12. Không coi câu chữ R008/R009 trước khi cập nhật chính sách là ưu tiên cao hơn Contract C′.
- **Ràng buộc nguồn:** việc ký Product Contract C′ không chấp nhận tự động mọi cách diễn đạt mới trong repository này.

## 2. Nguyên tắc biên tập

- **GIỮ NGUYÊN NGHĨA:** quan hệ Customer/Outlet/ShipTo; A/B/Mixed; moving average vận hành; ba sổ; credit UNSET khác approved zero; phê duyệt maker–checker; các mode/gate.
- **TÁCH KỸ THUẬT:** DB-per-tenant, PWA, API, inbox/outbox, SQL transaction, deployment, restore topology… nếu là cách triển khai; giữ mục tiêu an toàn/quan sát được và ghi lại quyết định kỹ thuật lịch sử trong constraints.md.
- **KHÔNG NGẦM ĐỔI:** R009 có điều khoản kỹ thuật lẫn BR; khi diễn đạt lại phải đối chiếu ý nghĩa, ghi biến đổi, điểm nào thiếu cần Owner quyết.
- **KHÔNG BỊA EVIDENCE:** synthetic/model CI, dữ liệu demo, báo cáo nghiên cứu và signed policy không phải E2E system verification; ghi pending đúng mức.
- **TECH-NEUTRAL:** tên hiệu lực/đối tượng nghiệp vụ có thể tồn tại độc lập implementation; không bắt buộc storage, framework hay API nào.

## 3. Theo dõi khác biệt cần Owner review

| Mã | Vấn đề chuyển đổi | Trạng thái |
|---|---|---|
| MAP-01 | D-01 trước đây chọn 1 DB/tenant; bản business chỉ buộc isolation và seller ownership. Quyết định DB được bảo toàn trong hồ sơ lịch sử, cần xác nhận khi chọn stack. | REVIEW_ON_IMPLEMENTATION |
| MAP-02 | PWA/web trước đây được nêu như kênh UI; business giữ hành vi ngoài hiện trường, sync/offline theo gate. | REVIEW_ON_IMPLEMENTATION |
| MAP-03 | Durable inbox/outbox, SQL transaction, IDs/hash được dịch thành yêu cầu nhận bền/chống trùng/atomic và truy vết. | TECHNICAL_DESIGN_PENDING |
| MAP-04 | R009/R010 có 22 AC và evidence; business B02 đã bổ sung cùng ID/expected ở mức candidate, không tự nâng MODEL_ONLY. | B02_CANDIDATE |
| MAP-05 | Thuế suất, invoice provider, seller profile, ngưỡng SLA/approval chưa xác minh thực; không tạo giá trị mặc định từ fixtures. | INPUT_OR_EVIDENCE_PENDING |

**Không có thay đổi ngữ nghĩa nào của baseline nguồn được tự tuyên bố Owner-approved trong PR này.**
