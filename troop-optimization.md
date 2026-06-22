# Question: Tại sao game như battle realms có thể quản lí việc di chuyển theo đội hình, combat (chọn đối tượng, phân công đối tượng để tấn công, v.v...) một cách rất hiệu quả và ít tốn tài nguyên tính toán.

Vì game RTS như **Battle Realms** không “tính thông minh hoàn hảo” cho từng lính ở mọi frame. Nó dùng rất nhiều thủ thuật thiết kế để biến bài toán phức tạp thành các bài toán nhỏ, rẻ và đủ tốt.

## 1. Di chuyển theo đội hình không phải là mỗi unit tự nghĩ hoàn toàn

Khi bạn chọn một nhóm lính và ra lệnh di chuyển, game thường không cho từng unit tự tìm vị trí tối ưu riêng. Thay vào đó:

1. Game chọn một **điểm đích chung** cho cả nhóm.
2. Tạo ra các **slot đội hình** quanh điểm đó, ví dụ hàng ngang, cụm vuông, hình cung.
3. Mỗi unit được gán vào một slot.
4. Unit chỉ cần đi tới slot của mình.

Ví dụ:

```text
Điểm đích nhóm
      X

Slot đội hình:
  A B C
  D E F
  G H I
```

Nếu có 9 lính, mỗi lính được gán vào A, B, C... rồi tự đi tới vị trí đó. Game không cần mô phỏng chiến thuật cấp cao cho từng con.

Điều này rẻ vì bài toán từ:

> “9 unit phải tự phối hợp với nhau”

trở thành:

> “mỗi unit đi tới một điểm đã được giao”.

## 2. Pathfinding thường dùng theo cấp nhóm, không phải mỗi unit tính đường mới liên tục

Một cách rất phổ biến là:

* Nhóm hoặc unit đứng đầu tìm đường chính bằng A* trên map/grid/navmesh.
* Các unit còn lại đi theo đường đó, nhưng offset ra vị trí đội hình.
* Chỉ khi kẹt hoặc lệch quá xa mới tính lại.

Game không cần chạy pathfinding đắt tiền cho toàn bộ quân mỗi frame. Thường pathfinding chỉ xảy ra khi:

* người chơi ra lệnh mới;
* unit bị kẹt;
* mục tiêu đổi vị trí nhiều;
* map có vật cản động đáng kể.

Còn trong phần lớn thời gian, unit chỉ “đi tiếp theo waypoint”.

## 3. Tránh va chạm dùng luật đơn giản, không mô phỏng vật lý phức tạp

Unit trong RTS thường không dùng physics thật như rigid body nặng nề. Chúng dùng các luật rẻ kiểu:

* nếu phía trước có unit khác thì giảm tốc;
* lệch nhẹ sang trái/phải;
* giữ khoảng cách tối thiểu;
* ưu tiên unit đang đi đúng đường;
* unit nhỏ nhường unit lớn hoặc unit đang tấn công.

Nhìn thì giống “né nhau thông minh”, nhưng thực chất thường là steering behavior đơn giản.

Ví dụ logic rất rẻ:

```text
Nếu quá gần unit khác:
    đẩy nhẹ ra xa
Nếu lệch khỏi slot:
    kéo về slot
Nếu có vật cản trước mặt:
    rẽ nhẹ
```

Không cần giải bài toán tối ưu toàn cục.

## 4. Combat dùng state machine đơn giản

Mỗi unit thường chỉ có vài trạng thái:

```text
Idle
Moving
Chasing
Attacking
Recovering / Cooldown
Dead
```

Khi combat xảy ra, unit không cần suy luận phức tạp. Nó chỉ kiểm tra vài điều kiện:

```text
Nếu có mục tiêu trong tầm:
    tấn công
Nếu mục tiêu ngoài tầm:
    đuổi theo
Nếu mục tiêu chết:
    tìm mục tiêu mới
Nếu bị ra lệnh mới:
    chuyển trạng thái
```

Đây là **finite state machine**, cực kỳ rẻ về tính toán.

## 5. Chọn mục tiêu không quét toàn bản đồ

Một sai lầm nếu tự làm game RTS là cho mỗi unit kiểm tra toàn bộ enemy để tìm mục tiêu gần nhất. Ví dụ 100 lính đánh 100 lính:

```text
100 x 100 = 10,000 lần kiểm tra
```

Nếu mỗi frame đều làm vậy thì tốn.

Game RTS thường dùng **spatial partitioning**, ví dụ:

* grid;
* quadtree;
* cell-based map;
* bucket theo vùng.

Map được chia thành ô. Khi unit muốn tìm mục tiêu, nó chỉ tìm trong các ô gần nó.

```text
Thay vì hỏi:
"Trong toàn bản đồ có enemy nào gần tôi?"

Game hỏi:
"Trong vài ô xung quanh tôi có enemy nào?"
```

Như vậy số kiểm tra giảm rất mạnh.

## 6. Phân công mục tiêu thường dùng heuristic, không tối ưu tuyệt đối

Khi một nhóm lính gặp địch, game không nhất thiết giải bài toán:

> “Unit nào nên đánh enemy nào để đạt DPS tối ưu?”

Thay vào đó dùng quy tắc gần đúng:

* đánh mục tiêu gần nhất;
* đánh mục tiêu đang đánh mình;
* ưu tiên mục tiêu trong tầm;
* không để quá nhiều unit melee cùng lao vào một mục tiêu nếu đã hết chỗ;
* ranged đứng sau bắn mục tiêu hợp lệ gần nhất;
* nếu mục tiêu chết thì chọn lại.

Điều này tạo cảm giác thông minh, nhưng không cần thuật toán nặng.

Ví dụ:

```text
Melee:
    chọn enemy gần nhất còn chỗ đứng xung quanh

Ranged:
    chọn enemy gần nhất trong tầm nhìn/tầm bắn

Healer/support:
    chọn đồng minh thấp máu nhất trong vùng gần
```

Đủ tốt cho gameplay, rẻ hơn rất nhiều so với tối ưu hóa chiến thuật.

## 7. Không phải unit nào cũng update AI mỗi frame

Game thường chia nhỏ update:

* unit gần camera update thường xuyên hơn;
* unit ngoài màn hình update ít hơn;
* tìm mục tiêu mỗi 0.2–1 giây thay vì mỗi frame;
* pathfinding chia ra nhiều frame;
* nhóm unit update luân phiên.

Ví dụ game chạy 60 FPS, nhưng AI targeting có thể chỉ chạy 5–10 lần/giây. Người chơi gần như không nhận ra, vì combat RTS không cần phản xạ từng millisecond.

## 8. Animation che giấu nhiều “gian lận”

Combat trong RTS nhìn mượt không có nghĩa là logic cực kỳ chi tiết.

Ví dụ một unit chém kiếm:

```text
0.0s: bắt đầu animation
0.4s: gây damage
0.8s: kết thúc animation
```

Trong thời gian đó, unit không cần suy nghĩ nhiều. Nó đang bị “khóa” trong animation/cooldown.

Animation, âm thanh, hiệu ứng va chạm và phản hồi máu làm người chơi cảm thấy combat phức tạp hơn thực tế.

## 9. Số lượng unit trong Battle Realms không quá khổng lồ

So với các RTS có hàng trăm hoặc hàng nghìn unit, **Battle Realms** thường có quy mô trận nhỏ hơn. Mỗi unit cũng có giá trị cao hơn, giống kiểu squad-based RTS. Điều này giúp game có thể dành nhiều logic hơn cho từng unit mà vẫn nhẹ.

Nhưng ngay cả vậy, game vẫn sẽ dùng các thủ thuật rẻ như:

* update theo đợt;
* tìm kiếm cục bộ;
* state machine;
* pathfinding không liên tục;
* đội hình theo slot;
* hạn chế số unit tham chiến trực tiếp quanh một mục tiêu.

## 10. Cốt lõi là “đủ thông minh”, không phải “thông minh thật”

Game RTS hiệu quả vì nó không cố mô phỏng chiến tranh thật. Nó chỉ cần tạo ra cảm giác rằng quân lính:

* biết đi theo nhóm;
* không kẹt quá ngu;
* biết đánh mục tiêu hợp lý;
* biết đổi mục tiêu khi cần;
* không đứng chồng lên nhau quá lộ.

Đằng sau đó là rất nhiều heuristic đơn giản.

Một mô hình đơn giản có thể là:

```text
Player command
    ↓
Group controller tạo formation slots
    ↓
Pathfinding tìm đường chính
    ↓
Unit đi tới slot của mình
    ↓
Local avoidance xử lý va chạm gần
    ↓
FSM quyết định Moving / Attacking / Chasing
    ↓
Spatial grid giúp tìm enemy gần
    ↓
Animation + cooldown làm combat trông mượt
```

Nói ngắn gọn: **Battle Realms và các RTS cũ chạy hiệu quả vì chúng dùng cấu trúc dữ liệu thông minh, update không liên tục, AI đơn giản theo trạng thái, tìm kiếm theo vùng nhỏ, và rất nhiều mẹo “đủ tốt” thay vì tính toán tối ưu toàn cục.**
