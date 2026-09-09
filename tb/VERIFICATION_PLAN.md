# Verification plan

## Mục tiêu và giới hạn

Verify contract của DUT học tập trong `RTL/README.md`: dữ liệu đầu ra, route/drop,
parity error, backpressure, reset, register/memory behavior. Đây là kế hoạch và
test implementation; không phải báo cáo mọi yêu cầu đã sign-off. Trạng thái
thực tế luôn xem `VALIDATION.md`.

Reference model dựa trên input/HBUS monitor, không peek nội bộ RTL để tạo
expectation. RAL backdoor là test riêng để kiểm tra HDL path/cross-check access,
không thay cho functional reference model.

## Ma trận requirement → test → checker

Tên dưới đây bỏ tiền tố `router_` và hậu tố `_test` cho ngắn.

| ID | Yêu cầu | Test chính | Bằng chứng/tiêu chí trong TB |
|---|---|---|---|
| OBJ-01 | Randomize, clone độc lập, compare, pack/unpack, pure parity | packet_api | Assertions bằng UVM_ERROR + round-trip |
| PKT-01 | Header/length/payload/parity tới đúng 3 output | smoke, random | Input/output monitors + scoreboard |
| PKT-02 | Length 1, 14, 15, 16, 17, 20, 21, 63 | boundary | End-to-end compare, length bins |
| PKT-03 | Length=max được route, max+1 và 0 bị drop | drop, virtual | Reference route reason + absence of extra outputs |
| PKT-04 | Destination 3 không xuất output | drop, virtual | Illegal counter + unexpected detection |
| PKT-05 | Disabled ưu tiên hơn bad address/length | drop | Reference precedence + counters |
| PKT-06 | Bad parity vẫn forward, error pulse đúng | parity | Full-byte compare + independent error checker |
| PKT-07 | Không mất/nhân đôi/đổi thứ tự trong channel | boundary, random, backpressure | Per-channel queues + conservation + drain |
| BP-01 | Input giữ data/valid khi bị suspend | backpressure | SVA + explicit non-vacuity saw_input_stall |
| BP-02 | Output giữ valid/data khi receiver stall | backpressure, random | Output SVA + scoreboard |
| RST-01 | Reset khôi phục defaults/counters/memory | register, enable_bits, memory_walk | UVM reset sequence + bus checks |
| RST-02 | Reset hủy packet input/output dở dang | reset | Driver aborted_count=1, monitor flush, post-reset traffic |
| REG-01 | HBUS write 1 cycle, read 2 cycles | register, memory | Driver/monitor + HBUS SVA |
| REG-02 | Raw bus và RAL đều phản ánh vào mirror | register | Explicit predictor + mirror readback |
| REG-03 | Counter enable độc lập từng bit | enable_bits | One-hot enables + independent HBUS reference |
| REG-04 | RO writes không sửa counter | register | Raw write + observed read check |
| REG-05 | Counter 8-bit wrap 260 → 4 | counter_wrap | Reference + readback + mirrored-value assertion |
| REG-06 | Reserved bits, max=0, unmapped read | enable_bits | Raw read masked value/zero checks |
| MEM-01 | Packet window chứa header và payload cuối | register | Reads sau packet/drain + reference packet memory |
| MEM-02 | Scratch 256 byte không alias | memory | Full unique-pattern sweep + explicit data compare |
| MEM-03 | Built-in memory walking sequence | memory_walk | UVM built-in checker + reference bus checker |
| RAL-01 | Backdoor path phản ánh frontdoor/HW update | backdoor | ctrl/counter/scratch peek checks |
| FAC-01 | Type override hoạt động | factory | short_yapp_packet constraints, normal datapath checking |
| SYS-01 | Virtual sequence phối hợp HBUS và YAPP | virtual | Register setup + boundary/drop/route checks |
| NEG-01 | Scoreboard phát hiện data corruption | scoreboard_negative | Đúng UVM_ERROR ID PACKET_MISMATCH |
| NEG-02 | Memory checker phát hiện faulty DUT write | memory_fault | INJECT_ERROR → HBUS_MISMATCH + MEMORY_DATA |

`memory_fault` là runner case riêng chạy class `router_memory_test` với define
`INJECT_ERROR`. Không có class UVM tên `router_memory_fault_test`; runner ánh xạ
ID đó trong manifest. Code bình thường không bật fault injection.

## Các suite

- `smoke`: sanity test nhỏ nhất.
- `core`: 14 test cases, 18 runs theo seed mặc định; gồm data object, routing,
  factory, virtual sequence, counters, memory, reset và backpressure.
- `extended`: backdoor và memory walk (2 runs).
- `negative`: 2 runs có chủ đích gây lỗi, được phân loại `EXPECTED_FAIL`.
- `all`: 18 cases / 22 runs. Override `--seed` sẽ đổi số run cho các case nhiều seed.

Danh sách máy đọc được là `sim/regression.json`; `run.py --list` là cách kiểm tra
nhanh khi số test hoặc seed thay đổi.

## Coverage strategy

Coverage đo **quan sát**, không đo số lần sequence được gọi:

1. Input/decision covergroup: destination 0..3, length buckets bao gồm zero và
   FIFO boundaries, good/bad parity, bốn route reasons, đúng ngưỡng max.
2. Cross address × length, address × parity, address × outcome. Ignore bins chỉ
   áp cho tổ hợp bất khả thi theo policy: address=3 không ROUTE_OK/DROP_LENGTH,
   address hợp lệ không DROP_ADDRESS. Không dùng ignore để che ca chưa test.
3. Checked-output covergroup: channel × length × parity, chỉ sample khi scoreboard
   đã match. Input coverage đạt cao không bảo đảm dữ liệu thật sự đến đích.
4. HBUS covergroup: vùng register/memory × read/write. Coverage read/write của
   RO region còn bao gồm những write bị bỏ qua; cần directed tests nếu muốn
   khép tất cả bins. Default/unmapped bin không đóng góp tỷ lệ coverage.
5. Backpressure và reset hiện có directed assertions/non-vacuity checks, chưa
   có covergroup đầy đủ cho từng độ dài stall hoặc mọi điểm cắt reset.

Đích học tập: mọi requirement có positive test và checking phù hợp, mọi bin
reachable được giải thích. Không đặt “100% coverage” như bằng chứng duy nhất.
Sau khi chạy `--coverage` trên host thật, merge theo công cụ của site, rà từng
uncovered bin và thêm directed tests. Chưa có kết quả functional/code/assertion
coverage đo từ UVM simulator trong lần bàn giao này.

## Tiêu chí kết thúc test/regression

Test dương:

- Không UVM_ERROR/UVM_FATAL, assertion failure, randomization failure, timeout.
- Có sentinel `[TEST_PASS]` và exit code simulator hợp lệ.
- Scoreboard pending=0; không partial packet, unexpected/mismatch.
- Với traffic tests, reference observed>0; API/memory-only tests khai báo ngoại lệ.
- Scenario-specific checks phải đạt, ví dụ saw_input_stall và reset abortion.

Test âm:

- Phải thực sự chạy scenario và đến `[TEST_FAIL]` với đúng error IDs được cho phép.
- Không xem crash, thiếu license, compile error, timeout hoặc assertion unrelated
  là expected failure. Runner trả FAIL nếu lỗi ngoài whitelist xuất hiện.
- Không có `[TEST_PASS]` trong test âm. Pass bất ngờ là checker/injection problem.

Mỗi lần chạy lưu seed, argv, stdout, simulator log, source SHA-256, UVM path,
simulator version và JSON summary. Không ghi đè kết quả lần trước.

## Những phạm vi chưa được claim

- HBUS đọc/ghi đồng thời input packet đang chạy: reference packet-level chưa
  mô hình hóa chính xác thời điểm header và từng payload byte.
- Reset tại mọi cạnh/pha HBUS, reset chồng nhau, reset thời lượng cực ngắn.
- UVC passive tích hợp với nguồn drive ngoài; reuse tại block/subsystem khác.
- Toàn bộ tổ hợp cross coverage; mọi bật/tắt counter giữa chừng; mọi giá trị
  control read/write; mọi kiểu protocol violation/X injection.
- Cycle equivalence với Cadence RTL gốc, proof về latency/throughput tối ưu.
- Backdoor write làm thay đổi trạng thái mà HBUS monitor không quan sát được.
- Formal verification, synthesis/PPA, CDC, DFT, hardware emulation và multi-clock.

Đây là các hạng mục mở rộng rõ ràng, không phải hành vi đã được kiểm chứng ngầm.
