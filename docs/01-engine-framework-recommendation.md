# 01 - Quyết định engine/framework

## Kết luận

Engine đã chốt: **Godot 4.5.x với GDScript**.

Lý do:

- miễn phí, open-source, chạy tốt trên Linux;
- editor nhẹ hơn Unity/Unreal, dễ prototype;
- GDScript phù hợp prototype nhanh trong Godot, dễ gắn với scene/UI/tooling và vẫn có thể tổ chức simulation core bằng typed scripts tách khỏi scene tree;
- scene/UI của Godot đủ cho 2.5D/3D strategy map;
- có thể dùng GDExtension/Rust/C++ sau khi profiling nếu pathfinding/logistics quá nặng;
- không bị khóa bởi licensing thương mại như Unity/Unreal.

Kiến trúc dự án không dựa vào việc tạo hàng chục nghìn `Node3D`. Godot đóng vai trò **renderer, input, UI, tooling, asset runtime**. Mô phỏng quân, logistics, thời tiết và kinh tế chạy trong lớp data-oriented riêng.

## Stack đã chốt

- Engine: Godot 4.5.x standard build.
- Language chính: GDScript.
- Gameplay core: typed GDScript modules/classes, không đặt logic rải rác theo scene nodes.
- Native extension tùy chọn: Rust hoặc C++ qua GDExtension cho pathfinding, chunk compiler, geometry jobs.
- Map tooling v0: procedural map generator + map pack compiler/validator.
- GIS preprocessing sau v0: QGIS + GDAL/OGR command-line cho adapter khu vực.
- Data format runtime: JSON manifest + compiled binary chunks.
- Asset workflow: marketplace 3D/2.5D model packs imported through a centralized asset catalog, with license/provenance metadata and Godot import settings tracked per asset.
- Tests:
  - Godot headless unit tests cho simulation core;
  - Godot headless smoke tests cho scene/UI;
  - golden tests cho map compiler và scenario loader.
- Version control: Git + LFS cho asset lớn nếu cần.

## Vì sao không dùng engine khác làm mặc định

### Bevy

Bevy rất mạnh cho ECS/data-oriented simulation, Rust performance tốt, open-source, Linux-friendly. Đây là lựa chọn tốt nếu team muốn code-first và chấp nhận tự xây editor/tools.

Điểm yếu với dự án này:

- thiếu editor kiểu Godot/Unity cho content iteration;
- UI/tooling/mod scenario phải tự xây nhiều hơn;
- đường cong Rust cao hơn với team mới;
- art/content workflow khó hơn cho campaign lịch sử.

Bevy phù hợp nếu mục tiêu là simulation-first, team thành thạo Rust, và chấp nhận tự xây toàn bộ toolchain.

### Unity

Unity có editor tốt, asset ecosystem lớn, DOTS/ECS mạnh cho số lượng entity lớn, Linux editor có hỗ trợ. Tuy nhiên:

- proprietary;
- licensing/terms cần theo dõi;
- dự án ưu tiên miễn phí/open-source nên Unity không phải lựa chọn mặc định;
- DOTS tăng độ phức tạp đáng kể.

Unity là lựa chọn thực dụng nếu team đã có kinh nghiệm Unity sâu và chấp nhận licensing.

### Unreal Engine

Unreal mạnh về 3D fidelity, world partition, rendering, tooling lớn. Nhưng với game này:

- nặng hơn cần thiết cho clean 2.5D strategy map;
- C++/Blueprint workflow phức tạp hơn cho simulation-heavy design;
- yêu cầu máy Linux cao hơn;
- licensing royalty cần tính khi thương mại hóa.

Unreal chỉ nên chọn nếu mục tiêu đồ họa 3D cinematic là ưu tiên chính.

### O3DE

O3DE open-source và có Linux support, nhưng ecosystem nhỏ hơn, documentation/community cho RTS strategy ít hơn Godot/Unity/Unreal. Không nên chọn làm default cho team nhỏ.

## Ma trận đánh giá

Điểm 1-5, cao hơn là tốt hơn.

| Tiêu chí | Godot 4.5 GDScript | Bevy | Unity | Unreal |
|---|---:|---:|---:|---:|
| Miễn phí/open-source | 5 | 5 | 2 | 3 |
| Dễ dùng trên Linux | 5 | 4 | 4 | 3 |
| Editor/content workflow | 4 | 2 | 5 | 5 |
| Simulation data-oriented | 3 | 5 | 4 | 4 |
| Performance ceiling | 3 | 5 | 4 | 5 |
| UI strategy game | 4 | 2 | 4 | 3 |
| Mod/scenario workflow | 4 | 3 | 4 | 3 |
| Team nhỏ prototype nhanh | 5 | 3 | 4 | 2 |
| Ít rủi ro licensing | 5 | 5 | 2 | 3 |

Kết quả: Godot được chọn vì cân bằng tốt nhất cho "miễn phí, dễ dùng, test Linux", miễn là simulation core không bị viết theo kiểu node-per-unit.

## Kiến trúc Godot cụ thể

Godot project chia thành 4 lớp:

1. **Runtime Shell**
   - scene root;
   - camera;
   - input;
   - UI;
   - map renderer;
   - debug overlays.

2. **Simulation Core**
   - typed GDScript modules/classes thuần data;
   - fixed tick;
   - không phụ thuộc trực tiếp vào scene nodes;
   - deterministic RNG seed;
   - có thể test độc lập.

3. **Content/Data Layer**
   - scenario manifest;
   - faction definitions;
   - unit/equipment/resource tables;
   - formula/global config tables;
   - asset catalog and visual style profile;
   - map chunk metadata;
   - historical source references.

4. **Tools/Compiler**
   - procedural map generation;
   - neutral map pack compile/load validation;
   - chunk generation;
   - LOD generation;
   - scenario validation;
   - balance simulation runner;
   - GIS region adapter sau v0.

## Rủi ro Godot và cách giảm

### Rủi ro: số lượng entity lớn

Không tạo mỗi lính thành một node. Dùng typed data objects trong simulation, render theo formation proxy.

Acceptance target:

- 5.000 squads mô phỏng ở 10-20 ticks/second;
- 100.000 individual records lưu stat nhưng không render đồng thời;
- 500-2.000 visual markers ở zoom chiến lược;
- zoom sâu chỉ render detail cho vùng đang xem.

### Rủi ro: bản đồ lớn

Dùng tọa độ simulation bằng mét, render chunk-relative.

Acceptance target:

- map generated v0 chia chunk, có khả năng scale lên map lớn sau này;
- camera không jitter ở zoom sâu;
- chunk visible load/unload không stutter quá 16 ms/frame trung bình.

### Rủi ro: pathfinding/logistics

Không pathfind trên mesh map lớn mỗi tick. Dùng graph đa cấp.

Graph:

- strategic graph: vùng, đèo, sông lớn, cảng, thành;
- operational graph: road/water/terrain chunk graph;
- tactical local steering: tránh obstacle trong khu vực xem.

### Rủi ro: lịch sử

Không hardcode dữ liệu lịch sử trong code. Mọi scenario campaign dùng data có source.

## Quyết định công nghệ cụ thể

| Hạng mục | Quyết định |
|---|---|
| Engine | Godot 4.5.x standard build |
| Language gameplay | GDScript |
| UI | Godot Control nodes + custom map overlay |
| Map renderer | chunk mesh/texture layers, LOD |
| Pathfinding | custom hierarchical graph, GDScript trước |
| Map generator v0 | procedural generator outside/alongside engine, deterministic by seed |
| GIS import sau v0 | GDAL/QGIS outside engine, xuất cùng map pack format |
| Scenario data | JSON + schema validation |
| Save game | binary snapshot + JSON metadata |
| Replay/debug | deterministic commands + seed |
| CI Linux | Godot headless unit/smoke tests, map compiler tests |

## Khi nào đổi sang Bevy

Chỉ đổi nếu 3 điều kiện đều đúng:

- team chính thành thạo Rust;
- không cần editor visual/content workflow kiểu Godot;
- mục tiêu simulation scale quan trọng hơn tốc độ làm campaign/content.

## Khi nào thêm native extension

Không thêm native từ đầu. Thêm sau profiling nếu:

- pathfinding vượt 8 ms/tick;
- route recomputation vượt 20 ms/job;
- map chunk mesh generation gây stutter;
- logistics flow solver quá chậm khi có hơn 10.000 tuyến.
