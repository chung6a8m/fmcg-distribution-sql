# Ma trận truy vết nghiệp vụ — B01

ID quyết định và quy tắc từ nguồn C′ được giữ ổn định. **SOP chính** là tài liệu nghiệp vụ trong repository này; AC/EV dùng ID nguồn và được biên tập chi tiết trong B02. Việc xuất hiện AC/EV ở đây **không có nghĩa đã chạy**.

| Nhóm | Decision / Product ADR | BR/POL | SOP chính | Acceptance IDs nguồn |
|---|---|---|---|---|
| Tenant/Customer | D-01/02, PADR-01 | BR-01/02; POL-01/02 | SOP-01/02 | AC-01/02 |
| A & ShipTo / terms | D-02/03/06, PADR-02 | BR-03/08/10; POL-03/08/10 | SOP-02 | AC-02/08 |
| Trip/Mixed/stock | D-03/04/11, PADR-03 | BR-04/05/06/07; POL-04/05/06/07 | SOP-03/04/05 | AC-03/04/05/06/16 |
| Pricing/returns/gifts | D-05/04, PADR-04/05 | BR-08/09/20; POL-08/09/20 | SOP-06 | AC-06/07/19 |
| B grant/credit | D-03/06/07, PADR-02/07 | BR-11/12/15; POL-11/12/15 | SOP-03/09 | AC-09/12 |
| AR/receipt/credit | D-06/12, PADR-05/06 | BR-10/13/14; POL-10/13/14 | SOP-07/08 | AC-08/09/10/20/21 |
| Offline/recovery | D-07/09/14, PADR-06/07 | BR-15/16/17; POL-15/16/17 | SOP-09/11 | AC-11/12/13 |
| Invoice/accounting | D-08/13, EVQ-05/06 | BR-18/19; POL-18/19 | SOP-10 | AC-14/15/19 |
| Cutover | D-10/11/14, EVQ-02/03 | BR-05/21; POL-05/21 | SOP-11 | AC-04/13/16 |
| Visit/report/pilot | D-15, PADR-08/09, EVQ-01/07 | BR-22/23/24; POL-22/23/24 | SOP-12 | AC-17/18 |

## Evidence/register không được nâng tự động

- **EV-01..15** ở nguồn còn real evidence pending, một số MODEL_ONLY; không gán PASSED khi chỉ xuất hiện trong tài liệu này.
- **TADR-01..06** vẫn technical design candidate; không mang vào business làm điều kiện phải chọn stack.
- Mode A/B_ONLINE/MIXED: **NO_GO/PENDING** cho tenant production; offline/cutover DISABLED_PENDING, B_NO_CHANNEL BLOCKED.

## Lưu ý

Mapping là index làm việc; các acceptance oracle trong B02 sẽ cụ thể hóa expected từng AC và duy trì dẫn tới BR. Khi phát hiện sai mapping, sửa bảng và ghi lý do, không “để liên kết cũ” cho qua validator.
