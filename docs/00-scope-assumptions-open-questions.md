# 00 - Phạm vi, giả định, câu hỏi mở

## Mục tiêu sản phẩm

Game là một RTS thời gian thực tốc độ cao tập trung vào chỉ huy cấp chiến dịch, nơi người chơi zoom từ cấp chiến lược xuống cấp doanh trại, tuyến tiếp tế, đường sá, bãi ruộng, bến thuyền, kho và khu vực giao tranh. Không có loading zone riêng cho battle hoặc quản lý vùng.

V0 **không đưa bản đồ khu vực lịch sử cụ thể vào game**. V0 dùng map generated để chứng minh gameplay, renderer, pathfinding, logistics và save/load map. Bản đồ lịch sử sẽ được đưa vào sau bằng adapter chuyển dữ liệu địa lý/lịch sử sang cùng định dạng map pack.

Trọng tâm không phải "xây base cố định" kiểu RTS cổ điển, mà là:

- đặt quân, kho, trại, công sự và tuyến tiếp tế ở vị trí hợp lý;
- kiểm soát địa hình, đường thủy, đường bộ, ruộng, rừng, núi, cảng và nguồn tài nguyên;
- quản lý hậu phương, thuế, dân tâm, sản xuất, vận chuyển, bảo quản lương thảo;
- điều hành vây hãm, chặn tiếp tế, truy kích hoặc cố thủ bằng mệnh lệnh cấp cao;
- dùng thời tiết, khí hậu và mùa vụ như biến số chiến tranh thật sự.

## Scope v0 được đề xuất

V0 nên là một vertical slice có thể chơi được trên map generated, không phải campaign lịch sử hoặc bản đồ khu vực lịch sử cụ thể.

Phạm vi v0:

- Map generator deterministic theo seed.
- Map pack trung lập có thể save/load lại, không phụ thuộc nguồn dữ liệu procedural hay GIS.
- Terrain cơ bản: biển/coast, plain, hill, mountain, wetland, paddy/dry field, forest/dense forest, river/stream, road/settlement footprint.
- Tài nguyên gameplay: rice/food potential, wood, iron, salt, water access, arable land.
- 2-4 phe placeholder trong sandbox, chưa cần campaign lịch sử.
- Một map generated liên tục quy mô nhỏ, có chunk streaming và zoom xuống cấp camp.
- Một số phe phụ ở dạng diplomacy/resource actors, chưa cần full AI ngang phe chính.
- Logistics có kho, tuyến vận chuyển, tiêu hao, spoilage, bandit risk.
- Weather có mưa, bùn, nóng, bão, tác động tới hành quân và bảo quản.
- Combat có morale, supply, terrain, siege, pursuit order.
- Units được mô phỏng theo đội/đơn vị chiến thuật và chuỗi chỉ huy, nhưng vẫn lưu stat cá nhân ở lớp dữ liệu khi cần.
- Scenario sandbox có objective đơn giản để test logistics/combat/construction.

Sau v0:

- Tạo adapter chuyển dữ liệu bản đồ khu vực vào định dạng map pack.
- Thêm resource/historical overrides phù hợp theo nguồn kiểm chứng.
- Thêm campaign slice khi map format, validator và gameplay loop đã ổn.

Ngoài scope v0:

- Multiplayer playable/online trong v0/v1; tuy nhiên kiến trúc vẫn phải chuẩn bị deterministic tick, serialization, command log và tách simulation khỏi presentation để chuyển sau.
- Naval warfare phức tạp với thủy triều/dòng chảy chi tiết.
- Render từng cá thể lính/dân chi tiết ở mọi mật độ hoặc mọi trận lớn. Vùng ít người có thể hiển thị toàn bộ; vùng đông người hoặc trận lớn phải dùng đại diện theo tỷ lệ.
- Bản đồ lịch sử của khu vực cụ thể, hoặc dữ liệu lịch sử hoàn chỉnh.
- Campaign lịch sử strict mode.
- AI chiến lược cấp quốc gia tương đương grand strategy hoàn chỉnh.

## Giả định kỹ thuật

Các giả định này dùng để lập kế hoạch. Nếu thay đổi, roadmap cần cập nhật.

- Nền tảng build mục tiêu: Linux và Windows.
- Nền tảng thử nghiệm chính: Linux desktop.
- Target hardware: máy phổ thông, 8 GB RAM, CPU không quá cao và GPU tích hợp. Asset, renderer và simulation phải ưu tiên LOD/impostor, batching, streaming và giới hạn memory rõ ràng.
- Người chơi dùng chuột + bàn phím.
- Camera: top-down/oblique 2.5D với zoom mượt xuống cấp camp.
- Bản đồ render 3D/2.5D, nhưng mô phỏng dùng tọa độ thế giới dạng mét, tách khỏi scene tree.
- Visual target: unified 2.5D strategy look, chạy tốt trên GPU tích hợp. Dùng model/pack từ các marketplace asset lớn sau khi kiểm tra license, format import và độ khớp phong cách; không dùng art hand-drawn làm hướng chính.
- Asset, công thức, tham số balance và global config phải được khai báo tập trung trong content/config registry có schema. Gameplay core không hard-code đường dẫn asset, magic number hoặc tham số tuning.
- Runtime chỉ đọc định dạng map pack trung lập. Generator v0 và adapter khu vực sau này đều xuất cùng format.
- Simulation tick cố định để dễ test, replay, cân bằng và chuẩn bị multiplayer/online sau này.
- Mỗi lính/dân có thể có stat riêng trong data, nhưng renderer chọn chế độ theo mật độ: vùng ít người hiển thị đầy đủ, vùng đông người/trận lớn dùng representative entity theo tỷ lệ 10 người thành 1 hoặc cao hơn. Giới hạn v0 cho số người được biểu diễn trong một khu vực/trận lớn là 10.000 người, không phải 10.000 mesh người chi tiết đồng thời.
- Ngoài quân đội, scene cần hiển thị làng mạc, dân thường, gia súc, nhà cửa, cây cối, ruộng và các dấu hiệu sinh hoạt để zoom gần vẫn thấy đời sống yên bình.
- Người chơi điều khiển đội quân thông qua tướng/chỉ huy sứ, không micro từng lính. Người chơi đặt intent/order cho cấp chỉ huy; AI cấp dưới tự triển khai formation, di chuyển, giao chiến, rút lui, đóng quân và quản lý hậu cần cục bộ theo quyền hạn.
- Cấu trúc chỉ huy quân đội có 2 cấp chính:
  - Quân khu khi đóng quân hoặc đạo quân khi chiến đấu, do đô đốc chỉ huy. Đô đốc do AI điều khiển và có thể ra quyết định về vị trí đóng quân, bố trí lực lượng tại nhiều vị trí chiến lược trong khu vực lớn mà người chơi chỉ định. Người chơi có thể để AI xử lý để tránh micromanage hoặc chọn tự điều khiển toàn bộ.
  - Chỉ huy sứ, người chơi có thể điều khiển trực tiếp ở cấp intent/order. Một chỉ huy sứ chỉ huy một đội quân và chỉ có thể đóng quân tại một vị trí cố định.
- Mức độ lịch sử cần gần đúng về dân số, kinh tế, tài nguyên, trang phục và bối cảnh xã hội. V0 vẫn dùng bản đồ random/thủ công, không dùng bản đồ lịch sử.
- UI mặc định dùng tiếng Việt.
- Các công thức trong docs là **tham số v0 để implement và balance**, không phải dữ liệu lịch sử.

## Chính sách không hallucination

Không tự khẳng định các điểm sau nếu chưa có nguồn:

- ranh giới hành chính chính xác của thế kỷ trong bối cảnh cụ thể;
- vị trí chính xác của từng trại, kho, tuyến hành quân, làng, cầu, cảng;
- sản lượng lúa/gỗ/sắt/muối cụ thể theo vùng trong từng giai đoạn lịch sử được chọn;
- khí hậu từng ngày/năm trong chiến dịch;
- tên tướng, trận đánh, số quân, casualty hoặc timeline nếu chưa được kiểm chứng.

Cách xử lý:

- V0 dùng map generated với nhãn `source = "generated"` và không đưa historical object vào strict campaign.
- Khi làm adapter khu vực, dữ liệu địa hình/hydrography hiện đại chỉ là lớp vật lý cơ sở.
- Tạo lớp historical override thủ công cho settlement, road, region, stronghold, resource zone sau khi có nguồn.
- Mỗi item lịch sử phải có `source_id`, độ tin cậy và ghi chú.
- Scenario không được đưa content lịch sử chưa kiểm chứng vào campaign chính; có thể đưa vào "fictional/randomized variant".

## Câu hỏi đã chốt

Các câu trả lời này là quyết định phase 0 và nên được dùng để cập nhật roadmap, architecture và content pipeline.

1. **Asset budget:** target hardware là máy phổ thông với 8 GB RAM, CPU không quá cao và GPU tích hợp. Đồ họa theo hướng 2.5D, ưu tiên asset nhẹ, LOD/impostor, texture atlas, batching, chunk streaming và giới hạn memory thay vì nhiều mesh/texture chi tiết đồng thời.
2. **Quy mô:** mục tiêu là hiển thị toàn bộ lính/dân ở vùng ít người. Với vùng nhiều người hoặc trận chiến lớn, renderer hiển thị tượng trưng theo tỷ lệ 10 người thành 1 hoặc cao hơn tùy mật độ/performance. Giới hạn thiết kế hiện tại là 10.000 người trong một khu vực/trận lớn. Ngoài quân đội, scene còn cần hiển thị làng mạc, người dân, gia súc, nhà cửa, ruộng, cây cối và sinh hoạt thường ngày.
3. **Granularity:** người chơi điều khiển đội quân do tướng/chỉ huy sứ chỉ huy thông qua cấp chỉ huy, không điều khiển từng nhóm nhỏ/từng lính. Quân đội có 2 cấp:
   - **Quân khu/đạo quân:** khi đóng quân là quân khu, khi chiến đấu là đạo quân, do đô đốc chỉ huy. Đô đốc do AI điều khiển, có thể quyết định vị trí đóng quân và bố trí lực lượng tại nhiều vị trí chiến lược trong khu vực lớn mà người chơi chỉ định. Người chơi có thể giao AI xử lý để không phải micromanage, hoặc chọn tự điều khiển toàn bộ.
   - **Chỉ huy sứ:** người chơi có thể điều khiển trực tiếp ở cấp intent/order. Một chỉ huy sứ chỉ huy một đội quân và chỉ có thể đóng quân tại một vị trí cố định.
4. **Multiplayer:** chưa cần multiplayer trong v1. Tuy vậy code phải chuẩn bị để sau này chuyển sang multiplayer/online: simulation deterministic, command log rõ ràng, state serialization, replay-friendly, tách gameplay simulation khỏi rendering/UI và tránh phụ thuộc vào trạng thái local khó đồng bộ.
5. **Mức độ lịch sử:** cần gần đúng về dân số, kinh tế, tài nguyên, trang phục và bối cảnh xã hội. V0 chỉ dùng bản đồ random/thủ công, không dùng bản đồ lịch sử chưa kiểm chứng và không trình bày map generated như dữ liệu lịch sử thật.
6. **Ngôn ngữ:** UI dùng tiếng Việt trước. Nếu cần đa ngôn ngữ sau này, thêm i18n layer nhưng không ưu tiên tiếng Anh trong v0/v1.
7. **Marketplace sourcing:** chưa khóa một marketplace duy nhất. Shortlist để khảo sát gồm [Fab](https://www.fab.com/), [Unity Asset Store](https://assetstore.unity.com/), [itch.io game assets](https://itch.io/game-assets), [Kenney](https://kenney.nl/assets), [Quaternius](https://quaternius.com/) và [Synty](https://syntystore.com/) hoặc low-poly vendor tương đương. Ưu tiên asset có license rõ ràng, format mở như FBX/glTF/OBJ/PNG, polycount thấp, LOD sẵn có hoặc dễ tạo, phong cách 2.5D thống nhất và không ràng buộc engine quá chặt.
8. **Target machine:** build để chạy trên Linux và Windows với cấu hình phổ thông, 8 GB RAM và GPU tích hợp. Không giả định desktop GPU rời.
9. **Camera:** zoom đến cấp camp, đủ để thấy chi tiết dân/lính, gia súc, nhà cửa, làng mạc, cây cối và sinh hoạt yên bình. Không yêu cầu render từng cá thể chi tiết ở mọi mật độ.
10. **Combat control:** không micromanage từng lính. Người chơi đặt intent/order cho các cấp chỉ huy; AI chỉ huy tự xử lý triển khai chi tiết trong phạm vi quyền hạn.

## Rủi ro chính

- **Định dạng map:** nếu format v0 gắn chặt với generator, adapter khu vực sau này sẽ khó làm. Cần map pack trung lập ngay từ đầu.
- **Độ lớn bản đồ:** map generated v0 nhỏ, nhưng vẫn cần floating origin/chunk-relative rendering để không phải đổi kiến trúc khi scale lên.
- **Số lượng lính:** lưu stat cá nhân được, nhưng render từng lính không khả thi nếu quy mô lớn. Cần aggregate simulation.
- **Đường tiếp tế:** pathfinding trên map lớn theo thời gian thực rất nặng. Cần graph đa cấp: road/water/terrain graph.
- **Lịch sử:** thiếu dữ liệu chính xác thế kỷ trong bối cảnh cụ thể. Cần pipeline kiểm chứng và content notes.
- **Balance:** nhiều hệ thống liên kết nhau; phải có simulation tests và scenario benchmarks từ đầu.
