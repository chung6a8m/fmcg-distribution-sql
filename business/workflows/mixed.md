# SOP-04 — Chuyến hỗn hợp A+B_ONLINE

**Mục tiêu:** Một chuyến vừa giao đơn đặt trước (A) vừa bán theo xe (B), nhưng mỗi pool hàng và quyền tín dụng độc lập.

**Vai trò:** Warehouse Manager tạo phân bổ; Trip Writer giao/bán; Cashier/Accountant đối chiếu; Tenant Ops chấp nhận đóng chuyến. **BR:** 03/04/05/11/12/13/23/24. **AC:** 03/04/09/18.

## Bắt đầu chuyến

1. Xác định AOrder/AReservation theo source line/lot và BQuota từ tồn chưa bị giữ. **Không gán cùng một lượng hàng cho cả A và B**.
2. Kiểm chứng từ nguồn, FEFO, stock available; chuyển hàng kho→xe theo manifest A và B riêng, chưa ghi doanh thu/AR/COGS.
3. Cấp một người viết có quyền theo chuyến; lái xe có thể khác người giao hàng, quyền không suy từ chức danh.

## Trong chuyến

4. Mỗi A Delivery tham chiếu AOrder và tiêu thụ AReservation, có AR/due riêng; không dùng BQuota.
5. B SaleDeliveryReceipt theo SOP-03 tiêu thụ riêng BQuota và ngân sách bán chịu; B chỉ hoạt động khi B_ONLINE đã được admitted.
6. Thu khách ghi receipt/custody đúng nguồn; không nhập tiền của A vào B sale hoặc tự khấu trừ grant B bằng thu nợ cũ.
7. Viếng thăm không đơn hoặc return request không tạo sale/stock giả.

## Kết thúc

8. Đối chiếu từng pool: A giao/hold còn lại, B đã bán/quota dư, hàng trả vào quarantine, hàng quay về kho, tiền đang giữ, tạm ứng, công nợ, invoice, sự kiện chưa đồng bộ.
9. Chỉ release hold/grant theo quy tắc có nguồn sau đối chiếu, không tự giải phóng khi chưa nhận hết journal.
10. Đóng **CLOSED** nếu sạch; nếu còn case có người chịu trách nhiệm, **CLOSED_WITH_OPEN_CASES**, ghi asOf/n/N/next action.

## Scenario nguồn quan trọng — AC-03

Tồn chính 100 đơn vị, giá trị 1.000 (đơn vị tiền giả lập), A giữ 40 và B quota 30; cấp xe 70. B bán 20, thu 200 trên doanh số 300 ⇒ AR B=100; A giao 25 trị giá bán 375, chưa thu ⇒ AR A=375; giá vốn cuối 450. Handover thủ quỹ nhận 200; trả xe A15 + B10, tồn kho cuối 55, tồn xe 0, A hold15, AR tổng 475, custody 0 và quỹ +200. Bộ oracle theo từng bước sẽ được chép vào B02, không phải E2E verified.

**Không được làm:** lấy A hold để bán B; coi load xe là bán; tự xoá case; khép Mixed chỉ vì A hoặc B riêng đã vượt gate.
