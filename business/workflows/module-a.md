# SOP-02 — Module A: đặt trước, giao hàng sau

**Mục tiêu:** Customer đặt trước và NPP thực hiện giao một hoặc nhiều lần; ghi nhận hàng–giá vốn–công nợ theo **phần giao thực**, không theo số đặt.

**Vai trò:** Sales lập, Warehouse giữ/cấp, Delivery thực giao, Accountant theo dõi thu và hạn nợ; Sales supervisor/Finance duyệt ngoại lệ. **BR:** 02/03/04/08/10/13/18. **AC:** 02/03/08/14.

## Tiền điều kiện

Customer có quyền giao dịch và ShipTo snapshot; SKU/UoM hợp lệ; giá/discount/tax/terms và tín dụng được kiểm; nếu tín dụng **UNSET**, không tự biến thành được mua chịu. Hàng đủ khả dụng để giữ; thiếu hàng thì pending/replan, không ghi tồn âm.

## Luồng chuẩn

1. Sales tạo **A Order DRAFT**: CustomerId, ShipToSnapshot (có thể không có Outlet), dòng SKU/qty/UoM, nguồn yêu cầu và chính sách.
2. Kiểm credit/terms: chính sách đã duyệt hay trả ngay đủ điều kiện, giá và quà hợp lệ, tồn và reservation.
3. **CONFIRM**: snapshot giá/discount cho lượng đã chốt, N ngày terms và giữ AReservation theo nguồn; **không tăng AR, revenue, COGS** ở bước này.
4. Warehouse lập manifest, chuyển lượng đã cấp lên Trip A (stock transfer, không là bán).
5. Delivery ghi nhận từng lần giao thực: deliveryId, source order line, quantity, lot, thời điểm businessDate, chứng cứ nhận và lượng còn lại. Không vượt lượng Confirm/remaining.
6. Ghi stock/cost và AR theo phần đã giao, tạo nghĩa vụ hóa đơn khi đúng điều kiện; theo chính sách CASH_ON_DELIVERY yêu cầu tiền đã verified trước khi hoàn tất giao, không tự chuyển nợ.
7. Mỗi lần giao tạo open item với **dueDate riêng** = ngày giao + N ngày trong snapshot lúc Confirm. Có thể tiếp tục giao cho tới đủ hoặc đóng phần còn lại bằng nguồn được duyệt.
8. Thu, phân bổ tiền và đối chiếu bằng SOP-07/08/10; thay terms Customer sau Confirm không làm đổi khoản nợ cũ.

## Ví dụ nghiệp vụ

Confirm ngày 30/10/2026 với terms N=7. Giao 01/11 (due 08/11) và 08/11 (due 15/11). Ngày 05/11 đổi terms mặc định Customer thành 14 ngày không làm hai khoản này đổi hạn. Đơn mới giao 08/11 theo N=14 có due 22/11.

## Ngoại lệ/không được làm

- Thêm/đổi Outlet hoặc address sau Confirm không thay snapshot của chứng từ đã có.
- Hết hàng, đổi giá, đổi terms cho lượng chưa giao phải qua amendment đúng phạm vi; không sửa phần đã giao.
- Không ghi doanh thu/AR từ Confirm, load xe hoặc phần còn lại chưa giao.
- Không tính lô hết hạn/return chưa QA được available mà bỏ qua kiểm tra.
- Hóa đơn phát sinh từ giao thực/điểm nghĩa vụ pháp lý, không suy từ create order.

**Kết thúc đúng:** Order FULFILLED hoặc REMAINDER_CLOSED có nguồn; tồn/cost/AR/receipt/reconciliation có thể đối chiếu theo từng Delivery, không mất phần giao chưa hoàn thành.
