# Công thức tính nghiệp vụ — không phụ thuộc tech stack

**Phạm vi:** các công thức cần đúng khi xây DMS. Những giá trị của scenario trong tài liệu này là **SYNTHETIC/MODEL_ONLY**, không làm mặc định thuế, giá, tỷ giá, thời hạn hoặc approval cho NPP thật. Số tiền phải có kết quả thập phân chính xác, không sai số do cộng/trừ số thực nhị phân; quy tắc làm tròn có phiên bản và mốc snapshot.

## 1. Quy ước dùng chung

| Ký hiệu | Ý nghĩa |
|---|---|
| baseQty | Số lượng theo đơn vị tồn chuẩn của SKU |
| sourceAmount / sourceQty | Giá trị/số lượng đã chốt của chứng từ nguồn |
| P | Tổng tiền phải trả hợp lệ của sale/delivery theo giá/discount/thuế đã chốt |
| R | Receipt **đã verified** được phân bổ vào chính sale này, tối đa P |
| C | CustomerCredit **đã reserve riêng** và áp cho sale, tối đa P−R |
| AR | Khoản còn phải thu Customer từ sale/delivery |
| grantCreditRemaining | Ngân sách quyền bán chịu B còn được dùng trong chuyến |
| asOf | Thời điểm chốt dữ liệu, không đồng nghĩa tất cả nguồn đã đồng bộ |

Cấm tự suy các giá trị chưa có chính sách (ví dụ credit UNSET) bằng 0 đã phê duyệt. Posted/locked data chỉ sửa bằng chứng từ adjustment/reversal có nguồn, không tự tính lại theo master mới.

## 2. UoM, giữ hàng và cân kho — BR-04/06

**Quy đổi:** baseQty = enteredQty × conversionFactorSnapshot; phải thỏa unitStep và scale của SKU tại mốc tạo/ghi nhận. Ví dụ 2 thùng × 24 chai/thùng = 48 chai (hệ số chỉ là ví dụ).

**Khả dụng:** availableQty = onHandEligibleQty − AReservationActiveQty − OtherHoldsActiveQty − BQuotaAlreadyAllocatedQty, tính trên cùng phạm vi location/lot và không trừ B quota lần hai khi lượng đã chuyển sang xe. Chỉ cộng/trừ các bucket không chồng nhau. Không dùng công thức đơn giản này thay contract inventory khi có hàng quarantine, transit hoặc off-wave pending.

**Bảo toàn lượng theo nguồn:** openingQty + legitimateInbound − legitimateOutbound = closingQty; kho→xe là inbound/outbound bù nhau trên tập stock locations; giao/bán mới đi ra khỏi tập. ReturnReceived về quarantine **chưa** cộng available.

**Ví dụ Mixed AC-03:** MAIN100 @ cost1.000, A hold40, B quota30; load70 ⇒ MAIN30/TRIP70/COGS0. B bán20 ⇒ TRIP50/COGS200; A giao25 ⇒ TRIP25/COGS450; trả xe25 ⇒ MAIN55/TRIP0/COGS450, A held15. Không ghi doanh thu/AR khi load.

## 3. Giá vốn bình quân di động SKU × StockLocation — BR-07/20

Với một **location**, khi nhập có giá trị đã xác nhận:  
newQty = oldQty + receivedQty; newValue = oldValue + receivedCostValue; movingAverageUnitCost = newValue / newQty (nếu newQty > 0). Khi xuất: issuedCost = sourceQuantity × unitCost tại thời điểm xuất, làm tròn theo policy; remainingValue = oldValue − issuedCost. Chuyến chuyển kho/xe mang **giá trị tương ứng** sang nơi giữ mới và không làm phát sinh COGS.

Giá trị xuất cần có sourceCostVersion để trả hàng theo **giá trị của chính giao dịch gốc**, không lấy moving average hiện tại. Trả từng phần dùng lũy kế:

- cumulativeRefundValue(k) = phần giá trị gốc ứng với tổng quantity đã trả đến k, làm tròn theo quy tắc đã chốt;
- thisRefundValue(k) = cumulativeRefundValue(k) − cumulativeRefundValue(k−1);
- tổng các phần hoàn, cộng điều chỉnh có nguồn, phải bằng tổng giá trị nguồn được hoàn tương ứng.

**Oracle AC-06:** nguồn 2 đơn vị cost = 6.667; trả đơn vị đầu 3.334, hoàn đơn vị sau 3.333 ⇒ tổng 6.667. Nếu nguồn điều chỉnh lên 6.768 sau lần hoàn đầu: adjustment phần đã hoàn **+50**; lần hoàn sau **3.384** ⇒ 3.334+50+3.384=6.768. Không viết lại chứng từ kỳ khóa; cost kế toán bình quân kỳ vẫn phải đối soát riêng.

**Lưu ý thiết kế:** thứ tự khóa giao dịch, phần dư rounding và cơ chế đồng thời là vấn đề implementation cần kiểm tra; không mặc định thuật toán/tables/transaction engine đã được phê duyệt tại business baseline.

## 4. Giá bán, discount và VAT — BR-08

Bộ rule tự động hữu hạn: **list price, customer group, fixed discount, percentage discount, gift threshold**. Thứ tự áp dụng/tie-break, hiệu lực, điều kiện thuế và cách tính giá gồm/chưa thuế phải ghi trong snapshot phiên bản đã duyệt. Không chạy script giá tùy tiện hay tự cộng nhiều rule khi precedence chưa rõ.

**Phân bổ discount tổng:** tổng discount phân bổ theo từng source line = tổng discount đã duyệt; không mất hoặc tạo thêm đồng do rounding. Phần dư phân bổ theo nguyên tắc xác định, ổn định theo source line, không lệ thuộc thứ tự các dòng hiển thị. R009/AC-19 có case giá chưa/gồm thuế và trả một phần để thử tính đúng; **không áp mức VAT 8%/10% của fixture cho hàng thật**.

**Giá chưa VAT (exclusive)** trên một dòng có tax rate hợp lệ r:
- lineNet = taxableBase − discountAllocated;
- lineTax = round(lineNet × r, roundingProfile);
- lineGross = lineNet + lineTax.

**Giá gồm VAT (inclusive)**: khi tiền dòng gross sau giảm đã chốt, lineNet được suy ra theo quy tắc tách thuế của profile; lineTax = lineGross − lineNet. Làm tròn theo dòng và phân bổ tổng phải nhất quán; không tự trộn hai chế độ trên chứng từ đã posted.

**Golden AC-19 (VAT chỉ là input giả lập):**
- EXCLUSIVE: P net193.333/tax15.467/gross208.800; Q net96.666/tax9.667/gross106.333; tổng **net289.999/tax25.134/gross315.133**.
- INCLUSIVE: P net193.865/tax15.509/gross209.374; Q net96.932/tax9.693/gross106.625; tổng **net290.797/tax25.202/gross315.999**.
- Trả P một phần ba sau khi đã thu đủ: refund source net64.444/tax5.156/gross69.600; thành CustomerCredit69.600; thực chi refund20.000 ⇒ credit còn49.600. Các lần trả tiếp phải giữ tổng net/tax/gross nguồn.

Nếu profile thuế/nhà cung cấp hóa đơn chưa được xác minh, kết quả chỉ là phép toán nội bộ, không là giá trị hóa đơn áp dụng ngoài đời.

## 5. Quà mua ròng, trả và miễn thu hồi — BR-09

entitlement = floor(netQualifiedPurchases / threshold), với threshold/đơn vị tính/quy tắc đủ điều kiện lấy từ chương trình đã duyệt;  
giftHeld = giftDelivered − giftAcceptedBack;  
giftToDeliver = max(0, entitlement − giftHeld).

Nếu có quà được **miễn thu hồi** nhưng khách vẫn giữ, số đó vẫn thuộc giftHeld; waiver không tăng entitlement hoặc tự cấp thêm quà. Nếu quà thực trả về dù đã từng có waiver, phải điều chỉnh nguồn giftHeld/waivedHeld đúng lượng thực và không ghi đôi.

**AC-07:** mua 20 được 2 quà (ngưỡng 10/1 trong fixture); trả 11 hàng mua và 2 quà; mua thêm 11 ⇒ mua ròng20, giftHeld0, cần giao thêm2. Nếu hai quà **được miễn thu hồi và khách vẫn giữ**, lần mua lại để đạt 20 không tạo thêm quà, giftToDeliver0. Waiver phải có duyệt và nguồn.

## 6. Hạn trả & tín dụng — BR-10/12

**A:** dueDate(openItem) = localBusinessDate(Delivery) + N ngày theo snapshot terms của A Order lúc Confirm. N=0 **chỉ hợp lệ** khi là điều khoản đã duyệt; UNSET không tự tạo quyền mua chịu. Hai Delivery có thể có dueDate khác nhau, không dùng ngày Confirm làm hạn cho tất cả.

**B:** 
- R_applied = min(P, verifiedReceiptAllocatedToThisSale)
- C_applied = min(P−R_applied, reservedCustomerCreditAppliedToThisSale)
- newReceivable = creditExposureConsumed = P−R_applied−C_applied
- grantCreditRemaining' = grantCreditRemaining−creditExposureConsumed
- grantCreditInitial = grantCreditRemaining + tổng creditExposureConsumed kể từ lúc cấp grant, trước release có nguồn.

Các lượng phải không âm, R+C ≤ P. Grant được reserve trong pool chung; **không tính cả giá trị đã held và AR phát sinh như hai lần tiêu hạn mức**. Thu nợ cũ không tự nạp quyền B trong chuyến; tiền nhận đủ không tự giải phóng grant trước reconciliation.

**Ví dụ AC-09:** grant100, P100: R60/C0 ⇒ AR40, grant còn60, custody cash+60; R100 ⇒ AR0, grant vẫn100 cho đến release; R60/C20 đã reserve ⇒ AR20, grant còn80, CustomerCredit nguồn giảm20; bank pending ⇒ R0; thu thực120 và áp100 ⇒ dư20 thành CustomerCredit, nếu cash thì custody tăng120.

## 7. Thu–nộp–tạm ứng, ba sổ — BR-13/14

**Receipt Customer:** confirmedAmount = tổng receiptAllocationToAR + availableCustomerCredit + tổng approvedActuallyDisbursedRefunds (+/− correction có nguồn). Không tạo AR âm từ tiền dư. Một receipt có thể phân bổ nhiều open items. Bank evidence pending không tạo confirmed amount/custody.

**AR:** closingAR = openingAR + các open item mới − confirmed allocations/credit applications hợp lệ ± approved adjustments; không tính nộp quỹ là thu khách lần hai.

**Custody cash:** closingCashCustody = opening + thực cash received − cashierAcceptedHandover ± correction có nguồn. OFFERED chưa thay số; tiền ngân hàng không nằm trong custody nhân viên.

**Quỹ:** fund tăng bằng số thủ quỹ thực nhận, không phải số nhân viên báo. Thiếu/chênh có case.

**Advance:** advanceOutstanding = issuedTotal − approvedExpenses − cashierAcceptedAdvanceReturns ≥ 0. ReturnOffer không làm giảm outstanding; có thể hoàn/duyệt từng phần, không tự bù với AR hoặc custody.

**AC-20:** 500.000 issued → approved expense300.000 còn200.000 → offer200.000 vẫn200.000 → cashier accept100.000 còn100.000 → accept100.000 còn0.

**AC-21:** AR140.000; cash receipt60.000 confirmed tạo CustomerCredit60.000 và custody60.000. Allocate20.000, rồi15.000 ⇒ AR105.000/credit25.000; offer handover50.000 không đổi custody; cashier accept50.000 ⇒ custody10.000/quỹ +50.000. Không tự khấu trừ AR thêm lần nào.

## 8. Báo cáo, đối soát và close — BR-19/23/24

Mọi số liệu tổng hợp có asOf, scope, nguồn kỳ vọng N, nguồn đã nhận n và trạng thái pending/unknown. **Completeness = n/N chỉ khi N được xác định**, không suy N=0 hoặc không có dữ liệu = mọi thứ đã đối soát. Đóng ngày có thể là CLOSED_WITH_OPEN_CASES có caseOwner/nextAction; không tương đương financial reconciled.

Đối soát kế toán cần so nguồn, kỳ, số chứng từ/dòng, lượng, tiền, AR, giá vốn và sai lệch; POSTED không tự thành RECONCILED_OK. NPP-01 Pilot mẫu 8 chuyến/ngày × tối thiểu 5 ngày nhưng toàn Kho-01 vẫn phải được kiểm soát.

## 9. Điều kiện kiểm chứng

Kết quả số trong expected-results là **business oracle**, không phải kết quả ứng dụng. Một triển khai chỉ đạt khi test thực phù hợp so expected/actual và có trace cho negative cases, retry/concurrency, provider/accounting/cutover trước production. Xem [acceptance.md](acceptance.md) và [reference-data](reference-data/README.md).
