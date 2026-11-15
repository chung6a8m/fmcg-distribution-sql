# Acceptance Criteria — MVP Business Contract

**21 AC-01..21** kế thừa ID và expected của Product Contract C′; bản chuyển đổi này **chưa được Owner chấp nhận riêng**. Các giá trị kỳ vọng dưới đây là business oracle, **không phải kết quả chạy phần mềm**. Với các ca cần E2E/bên ngoài, phải có riêng build, môi trường, actual, logs, nguồn và người chấp nhận.

## 1. Ca cốt lõi: Given → When → Then

| ID | Given / điều kiện | When / hành động | Then / kết quả bắt buộc |
|---|---|---|---|
| **AC-01** | User thuộc tenant A, không thuộc B; sau đó có quyền revoked | Truy xuất B và phục hồi snapshot cũ | Từ chối đọc/ghi/xuất B; revoked không hồi sinh; audit; **EV-01/09** |
| **AC-02** | Customer C1 **không có Outlet**, có ShipTo S1 | Confirm, giao A rồi đổi địa chỉ/chủ Outlet | Customer C1 chịu nợ; ShipTo và terms/price snapshot không đổi; **EV-02** |
| **AC-03** | MAIN100 @ cost1.000, A40/B30, giá bán15, grant B100 | Load70; B31 fail; B20 cash200; A25; nộp200; trả xe25 | Sau load MAIN30/TRIP70/COGS0; cuối MAIN55/TRIP0/COGS450, AR_A375/AR_B100, custody0/fund200, A held15; **EV-03/04/06/07/08/11** |
| **AC-04** | Kho-01 có hoạt động ngoài 8 chuyến Pilot, writer cũ nhiều lối | Freeze/cutover và thử mọi writer cũ | Nguồn mới là writer duy nhất **toàn kho**; một lối cũ còn ghi ⇒ P0 FAIL; **EV-04/12** |
| **AC-05** | SKU nhiều UoM/lot/hạn, hàng trả từ delivery cũ | FEFO/giao/trả/QA | Base Qty, lot snapshot đúng; return chỉ ở quarantine tới QA, held không giảm AR; **EV-04/05** |
| **AC-06** | 2 đơn vị source cost6.667, kỳ khóa; nguồn điều chỉnh6.768 | Hoàn từng phần + adjustment | 3.334 +50 +3.384=6.768; không viết lại kỳ khóa; giá vốn kỳ kế toán đối soát riêng; **EV-07** |
| **AC-07** | Mua20 có2 quà; trả11 hàng+quà hoặc waiver hợp lệ | Mua tiếp11 và tính lại | Nhánh đã trả quà cần giao2; nhánh waiver còn giữ quà không giao thêm; **EV-05** |
| **AC-08** | A Confirm N=7; giao 01/11,08/11; master đổi N=14 | Tính due date từng Delivery | Hạn 08/11,15/11; order mới giao 08/11/N14 hạn22/11; **EV-06** |
| **AC-09** | B P100, grant100, nhánh cash/credit/bank pending | Bán/tranh grant/retry/overpay | R60/C0 ⇒ AR40/grant60/custody60; R100 ⇒ AR0; R60/C20 ⇒ AR20; R120 ⇒ credit mới20; hai command P80 không cả hai thành; **EV-06/08** |
| **AC-10** | AR140.000/custody60.000, advance độc lập | Thu+allocate20.000; offer và accept quỹ50.000 | AR120.000/custody30.000/fund+50.000 chỉ sau accept; không trừ AR lần hai; **EV-06/12** |
| **AC-11** | Sự kiện C phụ thuộc P, lost ACK và thử same identity khác payload | Gửi lại, phục hồi và giải quyết dependency | Same ID/nội dung một effect; khác nội dung conflict; sự kiện pending không rơi mất; **EV-08** |
| **AC-12** | One writer/trip, grant hết hạn, hàng/tiền đã trao offline có phiếu giấy | Sync muộn, cấp writer khác, restore | Intent chưa thực hiện bị từ chối; occurred-event/case bền, không post trùng giấy; **EV-08/09** |
| **AC-13** | User revoked, privacy action và invoice ngoài có thật | Restore trạng thái trước revoke/invoice | Không hồi sinh quyền/không phát lại invoice; thiếu chứng cứ khóa tới đối chiếu; **EV-09/10** |
| **AC-14** | A giao nhiều phần, B_ONLINE kênh hợp lệ; có timeout/UNKNOWN | Hóa đơn, tra cứu, thử B no-channel | Invoice theo Delivery, UNKNOWN tra cùng identity; B no-channel blocked, event đã thực xảy ra giữ case; **EV-10** |
| **AC-15** | Events nguồn lặp và một posting kế toán sai | Đồng bộ, posted, reconciliation | Một source effect; RECEIVED, POSTED, RECONCILED_OK/DIFF riêng; lệch có case/correction; **EV-11** |
| **AC-16** | Opening kho/xe/nợ/tiền/tạm ứng/hóa đơn/thiết bị và writer cũ | Freeze/preview/ký/open writer, event cũ tới muộn, thử rollback | Cân opening, khóa writer cũ, không replay; sau first effect chỉ Forward Recovery; **EV-04/12** |
| **AC-17** | Sales viếng thăm Customer/Outlet nhưng không có đơn | Ghi lý do/quan sát/hoàn tất visit | Visit hợp lệ, không sinh sale0đ/AR/stock; **EV-13** |
| **AC-18** | Gate mode cần thiết đã đạt và có Pilot profile | Chạy NPP-01 3A+3B+2Mixed/ngày ít nhất5 ngày | n/N, UX, cases, cost, SLO đo thực; Go/No-Go từng mode, không dùng demo; **EV-14/15** |
| **AC-19** | Price P/Q discount10.001, VAT 8/10 **chỉ synthetic** | Tính exclusive/inclusive, trả P1/3, refund20.000 | Gross315.133/315.999; credit69.600→49.600; net/tax/gross và residual cân; **EV-05/06/10/11** |
| **AC-20** | Advance issued500.000; expense approved300.000 | Offer200.000, cashier accept100.000 hai lần | Outstanding500k→200k→200k→100k→0; không sửa AR/custody khách; **EV-06** |
| **AC-21** | AR140.000, receipt cash60.000 confirmed | Allocate20k +15k, offer50k, accept50k | AR105k/credit25k/custody10k/fund50k, offer không thay số; **EV-06** |

**Chú ý:** Bản nguồn có **AC-01..21**, không phải AC-22. R008 nói 22 nhóm khả năng nhưng không đồng nghĩa có AC-22. Giá trị trong bảng được đối chiếu theo [golden oracles](reference-data/expected-results/golden-oracles.json) và [additional oracles](reference-data/expected-results/additional-oracles.json).

## 2. Negative/fault scenarios không được bỏ

| Fault | Điều kiện thất bại | Expected | AC |
|---|---|---|---|
| F-01 | Mất xác nhận sau ghi hiệu ứng | Retry đúng nguồn một hiệu ứng | 11 |
| F-02 | Hai writer một chuyến | Writer không hợp lệ bị chặn, không ghi một phần | 12 |
| F-03 | Hai lệnh tranh grant | Không cùng vượt budget | 09 |
| F-04 | Provider invoice UNKNOWN | Lookup nguồn gốc, không phát ID mới | 14 |
| F-05 | Người thu offer, cashier chưa accept | Custody/quỹ không chuyển | 10/20/21 |
| F-06 | Restore trước revoke | Quyền đã thu hồi không sống lại | 13 |
| F-07 | Writer legacy sau cutover | P0 NO-GO, kể cả ngoài wave | 04/16 |
| F-08 | Cost refund sau kỳ khóa | Điều chỉnh có nguồn trong kỳ mới | 06/19 |
| F-09 | Bank pending/refund chưa disbursed | Không giảm AR/credit sớm | 09/19/21 |
| F-10 | Mất thông tin chưa đồng bộ | Không coi unknown=0; recovery case | 11/16/18 |

## 3. Evidence cần giữ độc lập

| Evidence | Đề mục cần test thật | Trạng thái nguồn |
|---|---|---|
| EV-01..04 | Tenant/security/Customer/Mixed/stock/cutover | EVIDENCE_PENDING |
| EV-05 | Giá/VAT/quà/returns | MODEL_ONLY, real pending |
| EV-06 | Ba sổ/credit/receipt/advance | MODEL_ONLY, real pending |
| EV-07 | Moving average/return/đối soát giá vốn kỳ | MODEL_ONLY, real pending |
| EV-08 | Offline/chống trùng/ACK và concurrency | MODEL_ONLY, real pending |
| EV-09 | Restore/revoke/privacy/external effects | MODEL_ONLY, real pending |
| EV-10..15 | Seller/invoice; kế toán; cutover; UX; Pilot readiness/results | EVIDENCE_PENDING |

B-CASE-001/002/003 và LEGAL-MEMO: EVIDENCE_PENDING; INV-09: NOT_RUN. Không tự đánh giá nhà cung cấp/tuân thủ từ synthetic cases.

## 4. Cổng nghiệm thu theo mode

- **DOC/MODEL:** Có BR, SOP, AC, dữ liệu mẫu, expected và validator pass. Không phải phần mềm đã đạt.
- **Product Verification:** từng mode/build cần E2E thực, chứng cứ tồn/hàng–tiền–nợ, bảo mật, idempotency, invoice và accounting theo phạm vi; P0 không miễn.
- **Tenant Go-Live Acceptance:** hồ sơ NPP/seller, opening/kho–nợ–tiền ký, old writer bị khóa, quy trình kiểm soát thật, quyền/legal/provider, Pilot và Owner quyết định riêng theo mode.
- **A/B_ONLINE/MIXED:** NO_GO/PENDING tới khi đủ gate. **OFFLINE_WRITE**: disabled/pending. **B_NO_CHANNEL**: BLOCKED, ngoài MVP.

## 5. Giao Codex kiểm thử

Mỗi PR triển khai phải ghi: AC IDs + BR IDs; scenario version; expected vs actual theo từng step; negative tests; test command/build/environment; nguồn thực/giả lập; phần còn NOT_RUN/BLOCKED; reviewer/owner disposition. Không sửa expected để phù hợp một cách tính sai trong implementation.
