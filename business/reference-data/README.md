# Dữ liệu mẫu và Golden Oracles

**Trạng thái:** SYNTHETIC, MODEL_ONLY. Dữ liệu tại đây không phải giao dịch, tenant, seller, VAT, số dư hay KPI thực; **không được dùng để phát hành hóa đơn, nhập production hoặc quyết định Go-Live**.

## Thành phần và mục đích

| File | Ý nghĩa |
|---|---|
| [master-data/seed.json](master-data/seed.json) | Danh mục nhỏ tự đủ để đọc ca: tenant giả lập, Customer/Outlet/ShipTo, SKU, UoM và nơi tồn; không phải F0 đầy đủ |
| [scenarios/business-cases.json](scenarios/business-cases.json) | 21 AC nghiệp vụ tương ứng từng case, bước thực hiện, expected và rule refs, **NOT_RUN** trên ứng dụng |
| [expected-results/golden-oracles.json](expected-results/golden-oracles.json) | **Chép nguyên giá trị số** của bốn oracle AC-03/19/20/21 từ Product Contract C′, đánh dấu MODEL_ONLY |
| [expected-results/additional-oracles.json](expected-results/additional-oracles.json) | Các oracle tính độc lập cho AC-06/07/08/09, số giả lập và công thức có thể tái lập |
| [../validation-guide.md](../validation-guide.md) | Cách kiểm cấu trúc, công thức và kết quả trên hệ thống khác |

## Quy tắc sử dụng

1. Mỗi scenario có **opening snapshot riêng**, trừ khi nói rõ chuỗi nối tiếp; không cộng kết quả hai fixture như cùng một chuyến thực.
2. Mỗi dòng giao dịch có nguồn ID ổn định; cùng nguồn/idempotency không được ghi hai lần; expected không thay khi đổi giao diện hay tech stack.
3. Số tiền đơn vị VND trong AC-19/20/21 là **giả lập**; AC-03 dùng đơn vị giá trị trừu tượng SYNTHETIC_UNITLESS.
4. Bộ oracle giữ cả bước bị từ chối, pending, offer chưa được cashier nhận và credit chưa được thực chi. Không xóa negative cases để “làm xanh” tests.
5. Thử A/B/Mixed không thay thế test hóa đơn, tác động bên ngoài, tenant isolation/cutover/restore trên hệ thống thật.
6. Chỉ ghi **IMPLEMENTATION_VERIFIED** khi có test run trên build/env cụ thể với actual/expected và người xác nhận, không sửa status của fixture.

## Quan hệ với F0/F1/F2 lịch sử

R010-S2 nguồn có F0 (seed101, 12 SKU/6 Customer/4 Outlet/3 Trip), F1 (seed202, 50 SKU/40 Customer/55 Outlet/40 Trip) và F2 (seed303, 3 tenant/tổng360 SKU/240 Customer/300 Outlet/300 Trip), cùng 343 trip projections. Chúng được lưu trong research repository như **test-model lịch sử**, không nhân bản dump lớn vào business v1. Bộ nhỏ ở đây chứa các ca **có expected giải thích được** để solo dev triển khai vertical slice.

Nếu cần tải/stress test F1/F2 sau này, tạo implementation fixture riêng từ nguồn có version và không trộn vào golden business oracle.

## Xuất xứ

Golden source: https://github.com/chung6a8m/research-sme-phan-phoi-hang-tieu-dung/blob/eb9c4b04e334530367b80ea4178edb4dd4a07491/reports/2026-11-13-10-product-reference-go-live-blueprint/s2/golden-oracles.json

Bản nguồn chỉ MODEL_ONLY; mọi ánh xạ được tái dựng đều cần giữ expected không đổi trừ khi có Business Change Decision.
