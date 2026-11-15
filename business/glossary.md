# Thuật ngữ chuẩn

| Thuật ngữ | Nghĩa trong sản phẩm | Phân biệt với |
|---|---|---|
| **Subscriber** | Bên ký hợp đồng/trả phí sử dụng sản phẩm | Customer mua hàng của NPP |
| **Tenant** | Ranh giới dữ liệu, thành viên và chính sách của một đơn vị bán | Customer, nhà sản xuất, point-of-sale |
| **BusinessOperator / LegalSeller** | Bên thực sự mua/bán, chịu nghĩa vụ chứng từ và hóa đơn | Subscriber thuê phần mềm hộ |
| **NPP** | Nhà phân phối; vai trò thương mại, có thể là người bán vận hành tenant | Đại lý hoặc Customer mặc định |
| **Customer** | Đối tác mua hàng và chịu công nợ/nhận tiền dư trước người bán | Điểm bán, địa chỉ giao |
| **Outlet** | Điểm bán ngoài hiện trường; Customer có **0..n** Outlet, quan hệ chủ sở hữu theo hiệu lực | Bên chịu nợ độc lập mặc định |
| **ShipTo** | Địa chỉ/nơi giao được snapshot trên Order/Delivery | Outlet bắt buộc phải tồn tại |
| **Đại lý** | Vai trò thương mại có thể biểu hiện bởi Customer hoặc Outlet theo hồ sơ thực | Một loại thực thể cố định |
| **SKU** | Đơn vị mặt hàng tồn kho duy nhất, có đơn vị chuẩn và chính sách lô/hạn | Barcode/lot |
| **UoM/Base UoM** | Đơn vị đo và đơn vị tồn chuẩn; hệ số quy đổi/step chốt theo chứng từ | Giá vốn hoặc SKU mới khi đổi UoM |
| **Lot/Expiry** | Lô và hạn dùng để truy xuất/ưu tiên xuất hàng | Phương pháp tính giá vốn |
| **StockLocation** | Nơi nắm giữ tồn và giá trị: kho, xe, vùng cách ly | Xe hay nhân viên như một thực thể |
| **Trip** | Phiên cấp hàng, giao/bán/thu, trả hàng và đối soát | Xe, người lái hoặc một ngày kế toán |
| **A Order** | Đơn đặt trước, sau đó giao một hoặc nhiều lần | Giao hàng đã xảy ra |
| **AReservation** | Lượng hàng giữ cho đơn A theo nguồn, chuyến | Hàng B có thể bán tự do |
| **BQuota** | Lượng hàng được phép bán theo xe B trong chuyến | Hàng giữ cho A |
| **Delivery** | Sự kiện giao thực tế; nguồn ghi nhận tồn/giá vốn và khoản phải thu theo chính sách | Lệnh tạo đơn, cấp xe |
| **Receipt** | Tiền nhận từ Customer; chỉ CONFIRMED khi có xác nhận tiền thật | Ảnh chuyển khoản hoặc phiếu báo chưa kiểm |
| **ReceiptAllocation** | Phân bổ tiền confirmed hoặc CustomerCredit vào một khoản phải thu | Số tiền receipt chưa phân bổ |
| **CustomerCredit** | Tiền khách nộp dư/chưa phân bổ, có nguồn để dùng/hoàn sau | Hạn mức bán chịu |
| **Receivable/AR** | Khoản Customer còn phải trả, theo nguồn giao và hạn riêng | Tiền nhân viên đang giữ |
| **Custody** | Trách nhiệm giữ hàng hoặc tiền của người/bên được giao | Quyền sở hữu, doanh thu, tạm ứng |
| **Advance** | Tiền doanh nghiệp ứng cho nhân viên và nghĩa vụ quyết toán | Tiền thu hộ Customer |
| **Handover** | Đề nghị/nộp và xác nhận nhận thực giữa người giữ tiền và thủ quỹ | Receipt từ Customer |
| **Return/Quarantine** | Hàng trả có nguồn và khu vực cách ly, chưa mặc nhiên bán lại được | Trả hàng được duyệt thương mại |
| **Gift Entitlement / GiftHeld** | Quyền nhận quà theo mua ròng / lượng quà khách còn giữ | Quà miễn thu hồi không làm tăng entitlement |
| **SourceDocument/SourceLine** | Chứng từ/dòng gốc định danh bền để đối chiếu tác động | Một lần gửi lại hoặc tệp nhập |
| **BusinessEvent** | Sự kiện nghiệp vụ có hiệu ứng được ghi một lần | Lượt gửi, lần đồng bộ hoặc batch |
| **Writer** | Quyền ghi sự kiện cho một chuyến theo assignment, chỉ một writer có hiệu lực | Người lái xe mặc nhiên |
| **Mode Admission** | Quyết định cho phép một mode ở phạm vi cụ thể sau kiểm chứng | Yêu cầu mode hoặc bật tùy chọn |
| **asOf / n/N** | Thời điểm dữ liệu và lượng nguồn đã có / tổng nguồn kỳ vọng | “Thời gian thực” mặc định |
| **CLOSED_WITH_OPEN_CASES** | Kết thúc vận hành có ghi rõ vấn đề tồn và người chịu trách nhiệm | Tất cả nghiệp vụ đã đối soát đạt |

**Quy tắc ngôn ngữ:** luôn ghi **Customer** nếu nói bên chịu nợ; **Outlet** nếu nói điểm bán; **ShipTo** nếu nói nơi giao. Không dùng “đại lý” để suy ra chủ thể pháp lý, người bán hoặc bên chịu công nợ.
