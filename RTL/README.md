# Đặc tả DUT học tập

`yapp_router.sv` + `yapp_fifo.sv` là DUT mặc định. Mục tiêu là một thiết kế đủ nhỏ
để đọc hết nhưng có đủ hành vi để học verification. Đặc tả dưới đây là contract
của project mới; không suy diễn rằng mọi chi tiết timing đều giống RTL Cadence.

## Packet và handshake

Một packet có `length + 2` byte:

```text
header[7:2] = payload length (6 bit)
header[1:0] = destination    (2 bit)
payload[0 .. length-1]
parity = XOR(header, tất cả payload bytes)
```

- Địa chỉ hợp lệ: 0, 1, 2. Địa chỉ 3 bị loại.
- Length hợp lệ: 1..63 và không vượt `maxpktsize`. Length 0 được định nghĩa là
  trường hợp negative/drop, vẫn có header rồi parity để parser kết thúc rõ ràng.
- Header/payload: `in_data_vld=1`; parity: `in_data_vld=0` nhưng byte parity vẫn
  phải được chuyển và tuân theo `in_suspend`.
- Mọi transfer được nhận tại cạnh lên. Driver đổi dữ liệu ở cạnh xuống.
- Ở trạng thái HEADER, cần `in_data_vld=1` để bắt đầu packet. Sau header không
  được chèn bubble bằng cách hạ valid; trạng thái parser xác định payload/parity.
- Khi `in_suspend=1`, giữ nguyên data và valid đến cạnh nhận tiếp theo. Driver
  chỉ tăng byte index sau cạnh lên có `in_suspend=0`.
- Mỗi output có FIFO 16 byte, first-word fall-through. Byte được đọc khi
  `data_vld_N=1 && suspend_N=0` tại cạnh lên. FIFO rỗng không xuất valid.
- Một FIFO full sẽ stall input của packet đang route tới FIFO đó. Pop tại cùng
  chu kỳ full chỉ mở chỗ cho chu kỳ sau: đây là lựa chọn conservative, có thể
  tạo một bubble. Không có yêu cầu độ trễ cố định hoặc reorder trong một channel.
- Packet dài hơn 16 byte vẫn hợp lệ: receiver đọc đồng thời với quá trình ghi.

FSM gồm HEADER → PAYLOAD → PARITY → HEADER. Nếu length=0, bỏ qua PAYLOAD.
FIFO xử lý dữ liệu ở mức byte; việc ghép thành packet thuộc về monitor UVM.

## Quyết định route/drop

Thứ tự ưu tiên:

1. Router disabled → drop, không tăng counter lỗi/địa chỉ.
2. Destination=3 → drop; tăng illegal counter nếu bit enable tương ứng bật.
3. Length=0 hoặc length>maxpktsize → drop; tăng length counter nếu được bật.
4. Các trường hợp còn lại → route và tăng counter địa chỉ nếu được bật.

Bad parity **vẫn được forward**. Với packet được route, parity sai làm `error`
lên trong một chu kỳ ngay sau cạnh nhận parity; tăng parity counter nếu được bật.
Parity của packet bị drop không gây `error` và không tăng parity counter.

Quyết định route được chốt tại header. Trong phạm vi verification hiện tại,
**không ghi config hoặc đọc trạng thái khi input packet đang chạy**. Counter
enables và cập nhật packet memory dùng config tại thời điểm cập nhật trong RTL;
project chưa định nghĩa atomic snapshot cho mọi side effect khi config đổi giữa
packet. Testbench không được dùng kết quả hiện tại để kết luận trường hợp đó đúng.

## HBUS và memory map

`hdata` là bus hai chiều 8 bit. `hen=1, hwr_rd=1` là write một chu kỳ. Read dùng
`hen=1, hwr_rd=0` trong hai chu kỳ; master lấy dữ liệu tại cạnh lên thứ hai.
Giữ địa chỉ và loại truy cập ổn định. Giữa hai transaction phải có một chu kỳ
`hen=0`. Slave chỉ drive bus khi read đang diễn ra; master chỉ drive khi write.

| Địa chỉ | Tên | Quyền | Reset | Ý nghĩa |
|---|---|---|---|---|
| `0x1000` | ctrl | RW | `0x3f` | Bits 5:0 = maxpktsize; bits 7:6 đọc 0 |
| `0x1001` | enable | RW | `0x01` | Các enable dưới đây; bit 3 đọc 0 |
| `0x1004` | parity_count | RO | 0 | Bad parity của packet được route |
| `0x1005` | oversized_count | RO | 0 | Length=0 hoặc vượt max với địa chỉ hợp lệ |
| `0x1006` | illegal_count | RO | 0 | Destination 3 khi router bật |
| `0x1009..0x100b` | addr_count[0..2] | RO | 0 | Packet được chấp nhận cho từng channel |
| `0x100d` | last_length | RO | 0 | Length header gần nhất khi router bật |
| `0x1010..0x104f` | packet_memory[0..63] | RO | 0 | Header + tối đa 63 payload byte, không parity |
| `0x1100..0x11ff` | scratch_memory[0..255] | RW | 0 | 256 ô nhớ độc lập cho RAL memory tests |

Enable bits: 0 router, 1 parity counter, 2 length counter, 3 reserved,
4 channel-0 counter, 5 channel-1 counter, 6 channel-2 counter, 7 illegal counter.
`0xf7` bật mọi chức năng có nghĩa; `0xf6` giữ enable counter nhưng tắt router.

Tất cả counter rộng 8 bit, wrap modulo 256. Ghi vào RO/unmapped không có hiệu
lực; đọc unmapped trả 0. Packet memory ghi cả packet bad address/bad length khi
router bật. Byte phía sau payload mới vẫn giữ nội dung cũ đến khi được ghi hoặc
reset; không tự xóa toàn bộ 64 byte mỗi packet. Counter địa chỉ và last_length
cập nhật ở header; parity counter cập nhật ở parity.

## Reset

Reset active-high bất đồng bộ, trong test giữ qua ít nhất vài cạnh clock.
Reset xóa FIFO, parser, counters, cấu hình và hai vùng memory về giá trị trên.
Packet dở dang bị hủy, không tự phát lại sau reset. TB phải flush cả partial
packet của monitor và expected queue. Không kiểm tra giá trị khởi tạo DUT trước
lần reset đầu tiên.

## Bản tham khảo Cadence

File `reference/cadence_yapp_router.sv` lấy từ
`D:\EDABK\Infineon\Cadence\UVM\yapp_router\router_rtl\yapp_router.sv`, không chỉnh
logic và không thuộc default build. Bản gốc có cấu trúc legacy và các điểm cần
điều tra riêng, gồm mixed-edge timing, nhánh xử lý enable và giới hạn mảng reset.

| Điểm | DUT học tập mới |
|---|---|
| Timing | Một contract cạnh lên, FIFO FWFT; không cycle-equivalent với bản gốc |
| FIFO | Module riêng, depth=16, conservative full handling |
| Reset/memory | Phạm vi index rõ ràng, reset đủ các phần tử |
| Unmapped/RO | Được định nghĩa và kiểm tra rõ ràng |
| Lỗi có chủ đích | `INJECT_ERROR` chỉ đảo dữ liệu ghi tại scratch `0x110f` |
| Error checker | Kiểm tra đúng pulse timing của DUT mới, không áp thẳng cho bản gốc |

Muốn verify Cadence RTL, cần một target riêng, rà lại đặc tả gốc và viết adapter
timing/checker phù hợp. Không compile hai file router cùng lúc vì trùng module;
không sửa scoreboard để bỏ qua sai khác chức năng chưa được chấp thuận.

RTL này chưa được đánh giá về inference RAM, timing closure, area, CDC hay DFT.
Reset bất đồng bộ toàn bộ memory thuận tiện cho học tập nhưng không phải quyết
định tối ưu cho mọi công nghệ FPGA/ASIC.
