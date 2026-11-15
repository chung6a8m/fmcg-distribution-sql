# SOP-03 — Module B_ONLINE: bán hàng theo xe

**Mục tiêu:** Nhân viên có quota hàng theo xe bán và giao tại Customer, ghi nhận phần thu thực và phần công nợ nhất quán; kênh hóa đơn phải phù hợp và được kiểm chứng trước giao dịch thật.

**Vai trò:** Warehouse/Trip Writer, Cashier, Accountant, Invoice operator/Legal Seller. **BR:** 04/11/12/13/15/16/18/19. **AC:** 03/09/11/12/14.

## Tiền điều kiện

Mode B_ONLINE được admitted cho đúng tenant/seller, kênh hóa đơn online đã đạt gate; TripManifest và BQuota có nguồn, không chồng A hold; có một writer/trip và hạn mức/chính sách tín dụng được duyệt. Customer, giá, SKU/lot/UoM hợp lệ.

## Luồng chuẩn

1. Kho giữ BQuota và chuyển lượng/giá trị sang StockLocation trên xe; bước này **không bán hàng**.
2. Tại điểm bán, nhân viên chọn Customer (Outlet tùy chọn) và ShipTo; xác định dòng đã giao, giá/thuế/discount và tiền thực nhận; ảnh ngân hàng chưa xác minh không là paid.
3. Xác định salePayable **P**, verifiedReceiptApplied **R**, reservedCustomerCreditApplied **C**. Phải có 0 ≤ R+C ≤ P; creditExposureConsumed = P−R−C.
4. Kiểm đủ BQuota và phần credit grant còn lại; nếu fail từ chối intent **trước giao**. Nếu thực tế đã trao trái quy trình, lập sự kiện thực/case để kế toán và kho xử lý; không tự bịa paid.
5. Chốt **cùng một nghiệp vụ** sale + delivery + receipt/allocations + AR + stock/cost + quota/credit grant, mỗi effect có ID riêng và không được chấp nhận nửa vời.
6. Nếu tiền mặt thực nhận, tăng custody theo toàn bộ số thực; nếu receipt vượt P thì phần dư thành CustomerCredit có source, không tạo AR âm.
7. Ghi nghĩa vụ hóa đơn từ delivery, xử lý channel/provider theo trạng thái; UNKNOWN phải tra cứu cùng identity thay vì phát mới bằng ID khác.
8. Cuối chuyến đối chiếu hàng B còn lại, AR, receipt, custody, invoice và kế toán; release phần grant còn lại chỉ sau reconciliation.

## Phản ví dụ bắt buộc

- P=100, nhận cash confirmed R=60, C=0 ⇒ AR mới 40 và custody +60.
- Khách trình ảnh chuyển khoản 60 nhưng ngân hàng chưa verified ⇒ R=0, không giảm nợ bằng chứng chưa xác minh.
- Hai sale cạnh tranh cùng quota/credit 100, mỗi sale đòi 80 ⇒ không được cả hai thành công.
- Cùng source gửi lại không ghi sale/AR hai lần; sai payload cùng identity bị conflict.

## Blocker

**B_NO_CHANNEL** không cho giao thật. Nhánh B có kênh hóa đơn thay thế lúc ứng dụng mất mạng là DEFERRED trong MVP. Một quyền ghi offline không phải bằng chứng phát hành hóa đơn đúng pháp luật.

**Kết thúc đúng:** sale/delivery/receipt có nguồn đối chiếu; tổng stock/cost/AR/custody/customer credit/credit grant cùng cân, không nhân đôi.
