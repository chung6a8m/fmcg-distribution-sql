# SOP vận hành kho, tiền, trả hàng và báo cáo

Tài liệu tự đủ các luồng hỗ trợ A/B/Mixed; không yêu cầu người đọc tìm lại SOP nguồn.

## SOP-01 — Chuẩn bị đơn vị bán, danh mục và phân công

1. Xác định tenant/bên bán hợp lệ, người dùng được phân công, Customer/Outlet và địa chỉ giao có nguồn; SKU/baseUoM/lot/StockLocation; kho/xe/nhân sự.
2. Thiết lập chính sách có hiệu lực/phiên bản (giá, terms, credit, threshold, người duyệt). Credit thiếu là **UNSET**, không tự coi đã duyệt 0.
3. Kiểm quyền, sự trùng nguồn và tính nhất quán dữ liệu; chưa có hồ sơ seller/mode gate thì không bật giao dịch thật.
4. Tạo hoặc thay đổi master **không** tự phát sinh stock, AR hay doanh thu.

## SOP-05 — Nhập/xuất/điều chỉnh kho ngoài wave, giá vốn

1. Nhận/kiểm nguồn nhập và SKU, số lượng base UoM, lô/hạn, StockLocation.
2. Áp FEFO khi SKU yêu cầu; kiểm source và quyền trước post.
3. Kho→xe chuyển lượng và giá trị, không sinh COGS/AR; giao/bán thực mới sinh COGS theo bình quân di động SKU×location.
4. Hàng trả thực nhận vào quarantine, QA release riêng; cost hoàn dùng nguồn xuất và phần dư lũy kế.
5. Sau cutover, **mọi** biến động Kho-01, kể cả ngoài Wave 1, đều phải đi qua nguồn ghi được ủy quyền; đối chiếu chênh với kế toán bình quân kỳ.

## SOP-06 — Giá/khuyến mại/trả hàng

1. Chọn giá/discount thuộc nhóm rule hữu hạn, hiệu lực/snapshot; A chốt tại Confirm.
2. Tính quà theo mua ròng, số quà khách còn giữ, quà đã trả; không cấp quà thêm vì được miễn thu hồi.
3. Return Request/HELD không giảm AR và không làm available tăng; nhận hàng thực vào quarantine.
4. Khi source delivery, nghĩa vụ quà, phê duyệt thương mại/QA đã đạt mới tạo return acceptance, AR/credit/refund và cost reversal có nguồn.
5. Hoàn tiền chỉ giảm CustomerCredit khi **actual disbursement**; tax/invoice correction phụ thuộc hồ sơ pháp lý đã kiểm.

## SOP-07 — Thu khách, nợ, tiền dư và refund

1. Receipt PENDING từ cash/bank evidence; chỉ CONFIRMED sau thực nhận tiền mặt hoặc bank verified.
2. Cash confirmed tăng custody theo **toàn bộ confirmed cash**, không theo số phân bổ.
3. Phân bổ receipt thành nhiều ReceiptAllocation, không vượt nguồn hoặc AR open; phần dư là CustomerCredit có nguồn receipt.
4. Dùng CustomerCredit để trả nợ khác cần allocation riêng; refund request→approve→disburse.
5. Không giảm AR vì nộp quỹ, không coi ảnh chuyển khoản là paid, không hoàn vượt credit.

## SOP-08 — Nộp quỹ, tạm ứng và kết ca

1. Người thu tạo CashHandover OFFERED, chưa thay custody/quỹ.
2. Cashier kiểm tiền **thực nhận** và CASHIER_ACCEPTED; số được nhận mới giảm custody và tăng quỹ.
3. Advance ISSUED độc lập; approvedExpense làm giảm outstanding; ReturnOffer chưa giảm; CashierAcceptAdvanceReturn làm giảm; có thể nhiều lần.
4. Đối chiếu AR, custody, advance, quỹ, bank pending, invoice, kế toán và pending trips riêng; đóng ngày có CLOSED_WITH_OPEN_CASES khi có owner/next action/asOf.

## SOP-12 — Viếng thăm không đơn và báo cáo

1. Từ danh sách Customer/Outlet được phân công, ghi visit outcome có đơn, không đơn, không gặp; reason/observation/return request có nguồn.
2. Visit không đơn hoàn tất hợp lệ, **không sinh sale 0 đồng**.
3. Báo cáo doanh số/tồn/AR/visit với asOf, phạm vi, n/N, pending trip/offline và case owner. Không coi dữ liệu chưa sync = 0.
4. Readiness và Go/No-Go phải theo **từng mode**, dựa trên chứng cứ thật và profile tenant; không suy từ bộ dữ liệu mô phỏng.

**Kiểm soát chung:** mọi sửa sai dựa vào source/adjustment; posted/locked period không bị viết lại, chênh lệch có người nhận xử lý.
