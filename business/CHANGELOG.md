# Business Baseline — Change log

## v1 candidate — 15/11/2026 (B01 + B02)

- **B01:** chuẩn hóa phạm vi, thuật ngữ, domain model, D-01..15, PADR-01..09, EVQ-01..07, BR/POL-01..24, AP-01..10 và SOP-01..12; tách lựa chọn kỹ thuật lịch sử khỏi hành vi.
- **B02:** công thức, 21 AC, 4 oracle bất biến từ R010-S2 và 4 bộ công thức bổ sung, seed/cases nhỏ, validator không phụ thuộc sản phẩm.
- **Tình trạng:** BUSINESS_CANDIDATE, chưa có Owner approval mới cho bản diễn đạt tại repo này; chưa có kết quả app E2E/tenant Go-Live.
- **Lịch sử:** Product Contract C′ đã được Owner chấp nhận tại commit eb9c4b04 trong research repo chỉ ở phạm vi PRODUCT_POLICY_AND_CONTRACT_ONLY.
- **Thay đổi kỹ thuật:** không chọn tech stack, database, UI, provider, hosting, API hay cách triển khai offline.

## Kiểm soát phiên bản sau này

Khi Owner chấp nhận business baseline này, mới cân nhắc tag `business-v1.0.0` trên commit cụ thể và ghi Owner acceptance thật. Từ đó mọi thay đổi ngữ nghĩa phải có delta D/BR/SOP/AC/oracle và quyết định Owner.
