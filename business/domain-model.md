# Mô hình miền nghiệp vụ và hợp đồng dữ liệu logic

Tài liệu mô tả **khái niệm và ràng buộc nghiệp vụ**, không phải SQL schema, HTTP API hay quyết định persistence. Mỗi chứng từ có ID ổn định, nguồn, người thực hiện, thời điểm thực tế/báo cáo, kỳ nghiệp vụ và phiên bản chính sách thích hợp.

## 1. Quan hệ chủ thể

- Subscriber có thể thuê dịch vụ cho một hoặc nhiều tenant; quyền thanh toán phần mềm **không** mặc nhiên cấp quyền xem dữ liệu tenant.
- Trong MVP, **một tenant ⇔ một đơn vị bán thương mại chính**. Việc tách dữ liệu bắt buộc; lựa chọn một database/tenant thuộc hồ sơ kỹ thuật lịch sử.
- Một Customer thuộc người bán; **Customer (1) — Outlet (0..n)**, quan hệ Outlet–Customer có khoảng hiệu lực.
- Mỗi Order/Delivery tham chiếu **Customer chịu nợ** và **ShipTo snapshot**; Outlet có thể không tồn tại. Thay đổi Outlet, tên hoặc địa chỉ sau đó không sửa lịch sử.
- Một Trip có xe và nhân sự theo vai trò; nhân viên giao hàng có thể kiêm lái xe với xe máy; xe tải có thể có cả hai người. Một người không mặc nhiên có quyền mọi vai trò.

## 2. Hàng hóa và quyền cấp hàng

- SKU (1) — UoM (1..n), có một base UoM; khi phát sinh chứng từ phải snapshot hệ số quy đổi và bước lượng.
- SKU (1) — Lot (0..n theo profile); mỗi biến động lot/expiry truy được đến nơi nắm giữ.
- StockLocation gồm kho chính, xe và quarantine. **Kho → xe là chuyển quyền giữ hàng/giá trị nội bộ, không phải doanh thu/công nợ/COGS**.
- AOrder (1) — OrderLine (1..n) — DeliveryLine (0..n); không giao vượt lượng xác nhận hoặc lượng còn lại.
- Trip — AReservation (0..n) và BQuota (0..n); cùng stock nguồn nhưng **không được chồng quyền lượng**.
- StockMovement có sourceLineId duy nhất trong phạm vi nguồn và đối soát được lượng/giá trị; ReturnReceived đưa hàng về vùng cách ly, QA Release là quyết định riêng.

## 3. Giá, khuyến mại, giá vốn

- PriceRuleVersion quy định phạm vi, hiệu lực, thứ tự ưu tiên và công thức hữu hạn; mỗi giao dịch chốt một snapshot giá/discount/tax profile và ruleVersion.
- GiftEntitlement tính từ số mua ròng đủ điều kiện; GiftDelivery/GiftReturn/GiftWaiver ghi riêng theo nguồn, không cấp trùng.
- CostBalance theo **SKU × StockLocation**; xuất có CostBasisSnapshot, Return dùng giá trị nguồn và cumulative refund; khóa kỳ chỉ cho phép điều chỉnh ở kỳ có quyền.

## 4. Hàng–tiền–nợ phải có nguồn riêng

- Delivery hoặc sale hợp lệ (1) — ReceivableOpenItem (0..n), theo chính sách trả ngay/bán chịu; mỗi khoản có dueDate riêng.
- Receipt (1) — ReceiptAllocation (0..n) tới open items; phần chưa phân bổ là CustomerCredit từ chính receiptSource. BankPending không tạo confirmed receipt.
- CashCustodyLedger chỉ tăng khi **tiền mặt thực nhận** và giảm khi người nhận quỹ chấp nhận handover; không trừ AR lần hai.
- AdvanceLedger độc lập: issued, approvedExpense, cashierAcceptedReturn; không tự bù custody/AR.
- B_ONLINE SaleDeliveryReceipt là một **đơn vị hiệu lực nghiệp vụ trọn vẹn**: hàng, AR, receipt, credit, grant/quota và nguồn phải cùng thành hoặc cùng không thành; các effect ID khác nhau.
- InvoiceIntent, InvoiceExternalFact và AccountingPosting/Reconciliation có trạng thái riêng; chưa thể suy POSTED kế toán từ ACK tiếp nhận.

## 5. Các trạng thái chính cần biểu diễn

| Đối tượng | Trạng thái tối thiểu có ý nghĩa |
|---|---|
| A Order | DRAFT → CONFIRMED → PARTIALLY_DELIVERED → FULFILLED hoặc REMAINDER_CLOSED có nguồn |
| Trip | PREPARED → RELEASED → IN_PROGRESS → RECONCILING → CLOSED / CLOSED_WITH_OPEN_CASES |
| Return | REQUESTED/HELD → PHYSICALLY_RECEIVED_QUARANTINE → COMMERCIALLY_ACCEPTED → QA_RELEASED hoặc DISPOSED |
| Receipt | PENDING → CONFIRMED (hoặc REJECTED); phân bổ/hoàn là event riêng |
| Handover | OFFERED → CASHIER_ACCEPTED hoặc DISCREPANCY_CASE |
| Invoice | PREPARED / CREATED / SIGNED / SUBMITTED / DELIVERED / UNKNOWN theo hồ sơ provider đã kiểm |
| Accounting | RECEIVED → POSTED → RECONCILED_OK / RECONCILED_DIFF |
| Offline/Recovery | chưa gửi / đã được nhận giữ bền / chờ phụ thuộc / đã giải quyết / recorded exception, không nhập làm một với kế toán |

Tên state trên là **hợp đồng ngữ nghĩa và ứng viên từ tài liệu nguồn**, không cưỡng bức giá trị enum của bất kỳ implementation nào. Với sự kiện từng xảy ra ngoài quyền, lưu sự thật + case thay vì xóa vì validate thất bại.

## 6. Điều kiện dữ liệu và sửa sai

Giữ ID và định danh nguồn bền; nhận cùng ID/cùng nội dung không sinh hai hiệu ứng, cùng ID/khác nội dung là conflict. Thời điểm nhân viên khai xảy ra khác thời điểm hệ thống nhận; không dùng đồng hồ thiết bị làm sự thật duy nhất. Chứng từ đã có hậu duệ hoặc thuộc kỳ khóa cần reversal/adjustment có source và approval, không viết lại quá khứ. Quan hệ khách hàng, giá, điều khoản và thuế phải snapshot đúng thời điểm, không truy bảng hiện tại để tính lại lịch sử.
