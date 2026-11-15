# SOP bảo toàn sự thật: offline, hóa đơn, kế toán, cutover và phục hồi

Tài liệu này mô tả **hậu điều kiện phải đúng**, không chọn trình duyệt, giao thức, queue, database, cloud hoặc provider. Các cơ chế trong source R009/R010 là phương án kỹ thuật cần chọn/kiểm chứng sau.

## SOP-09 — Quyền ngoài mạng, giao nhận bền và cấp lại chuyến

1. Quyền offline **mặc định tắt**; nếu được mở, bị giới hạn bởi tenant/mode/Trip/Writer/thiết bị, hạn, lượng và ngân sách credit; chỉ một writer/trip.
2. Mọi sự kiện phát sinh có identity, source, nội dung, phiên bản, thứ tự/phụ thuộc và thời điểm khai báo. Người tạo phải giữ được sự kiện cho tới khi bên tiếp nhận xác nhận giữ bền.
3. Tiếp nhận thành công **không đồng nghĩa** nghiệp vụ đã ghi sổ hay đã đối soát. Gửi lại cùng identity/nội dung chỉ có một hiệu ứng, khác nội dung là conflict.
4. Nếu dependency chưa có thì chờ/case; mất ACK, khởi động lại, mất thiết bị hoặc revoke không khiến giao dịch nhân đôi/mất.
5. Việc thay thiết bị/writer phải đối chiếu sự kiện đã xảy ra và quyền trước khi cấp lại. Hàng/tiền đã trao ngoài quyền là **recorded exception**, không được xóa sự thật.
6. Quyền ghi offline **không** thay thế điều kiện hóa đơn B_ONLINE; B_NO_CHANNEL BLOCKED.

## SOP-10 — Hóa đơn và ghi sổ kế toán bên ngoài

1. Nguồn nghĩa vụ hóa đơn là Delivery/chuyển quyền thương mại hợp lệ; không phải chuyển kho→xe hoặc thu nợ cũ.
2. Kiểm seller, chứng từ, điều kiện thời điểm, loại hàng, thuế và kênh trước khi phát hành; nếu trạng thái đối tác UNKNOWN, đối chiếu identity gốc trước khi thử lại, không tạo mới tùy tiện.
3. Tách các mốc chuẩn bị/tạo/ký/gửi/đến người mua theo quy định và khả năng thực tế; không suy trạng thái hợp lệ từ một lần bấm gửi.
4. Kế toán nhận một tác động có source duy nhất: **RECEIVED → POSTED → RECONCILED_OK hoặc RECONCILED_DIFF**; thiếu line/cutoff hay posting lệch thì chưa đạt.
5. File/manual/API chỉ là cách thực hiện; tất cả phải đối chiếu ID/chứng từ, số lượng, tiền, công nợ, cost và correction cùng nguồn.

## SOP-11 — Chuyển đổi số dư, khóa nguồn cũ, Forward Recovery

1. Kiểm kê Kho-01 toàn phạm vi gồm main/trip/lot/quarantine, A hold/B quota, tiền/nợ/CustomerCredit/advance, invoice ngoài, đơn/chuyến dở và nguồn giấy/thiết bị chưa đồng bộ.
2. Đặt thời điểm freeze/cutoff và manifest; kiểm mọi đường writer cũ kể cả ngoài Wave 1, batch/import/thiết bị chưa sync.
3. Xem trước chuyển đổi, đối chiếu số dư và lấy chấp nhận đa bên (kho, kế toán, thủ quỹ, IT, Owner theo hồ sơ).
4. Chỉ mở writer mới sau khi khóa hết nguồn cũ và opening đã được chấp nhận; receipt/sale từ hệ cũ đến muộn phải đối chiếu source, không post lại.
5. Sau hiệu ứng kinh doanh đầu tiên, xử lý sai bằng **forward adjustment/reversal có nguồn**, không rollback làm mất sự kiện/ngoại hiệu ứng.

## Restore và quyền hiện hành

Sau khôi phục dữ liệu, phải xác thực lại quyền đã thu hồi, sự kiện riêng tư, danh tính phát hành bên ngoài và chứng từ có thể đến muộn trước khi cho ghi tiếp. Nếu thiếu khả năng đối chiếu, giữ **BLOCKED/QUARANTINED**, không tự coi bản backup là nguồn quyền đầy đủ.

## Ngoại lệ kết ca

Vẫn có thể biểu diễn **CLOSED_WITH_OPEN_CASES** nếu ghi rõ tồn chưa xử lý, mức độ đầy đủ nguồn, asOf, người chịu trách nhiệm, hạn/next action. Không dùng nhãn này để tự bỏ qua P0 hoặc tài liệu pháp lý bắt buộc.
