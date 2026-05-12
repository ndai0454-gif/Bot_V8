# 🗺️ BOTVANG V10 - SYSTEM WORKFLOW
**Project:** AI Hybrid Trading System (Python + C++ + MQL5)
**Strategy:** Multi-Timeframe (MTF) + Smart Money Concepts (SMC) + Machine Learning

---

## 🔄 1. THE MASTER PIPELINE (LUỒNG TỔNG THỂ)

Hệ thống hoạt động theo một chu trình khép kín chia làm 2 giai đoạn: **Offline (Học)** và **Online (Thực thi)**.

### 🟢 GIAI ĐOẠN OFFLINE: HUẤN LUYỆN (The Learning Phase)
*Mục tiêu: Tạo ra "não bộ" `ai_model_v10.txt`*

`MT5 Server` $\rightarrow$ `Export CSV (H4, H1, M15)` $\rightarrow$ `train_v10.py` $\rightarrow$ `features_v10.py` $\rightarrow$ `Model Training (One-vs-Rest)` $\rightarrow$ `ai_model_v10.txt`

1. **Thu thập:** Lấy dữ liệu thô từ Broker qua 3 khung thời gian.
2. **Xử lý (Preprocessing):** 
    - Kết hợp H4 (Xu hướng) và M15 (Biến động) vào trục H1.
    - Tính toán 22 đặc trưng (Features) bao gồm RSI, BB, EMA Gaps, MTF Alignment.
3. **Chuẩn hóa:** Sử dụng `RobustScaler` (Median/IQR) để loại bỏ nhiễu từ các nến tin tức (Outliers).
4. **Học:** AI học cách phân loại 3 trạng thái: **BUY (1), SELL (-1), NEUTRAL (0)**.
5. **Xuất bản:** Lưu trữ Trọng số (Weights) và Sai số (Bias) vào file `.txt`.

---

### 🔵 GIAI ĐOẠN ONLINE: GIAO DỊCH (The Execution Phase)
*Mục tiêu: Biến tín hiệu AI thành lợi nhuận*

`Tick Giá` $\rightarrow$ `MQL5` $\rightarrow$ `SMC Filters` $\rightarrow$ `C++ DLL (AI)` $\rightarrow$ `Confirmation` $\rightarrow$ `Order Execution`

#### 🛡️ Phễu lọc 3 Tầng (The 3-Tier Filter)
Để đảm bảo sự "Cẩn trọng", lệnh chỉ được vào khi vượt qua 3 tầng lọc:

**Tầng 1: Định hướng (Khung 4H)**
- **Logic:** `Price vs EMA 200`.
- **Kết quả:** Chỉ cho phép Buy nếu giá trên EMA200, Sell nếu giá dưới. $\rightarrow$ *Loại bỏ lệnh ngược sóng.*

**Tầng 2: Vùng giá trị (Khung 1H)**
- **Logic:** Quét tìm **FVG (Fair Value Gap)** chưa bị lấp (unfilled).
- **Kết quả:** Chỉ cho phép vào lệnh khi giá quay lại chạm vùng FVG. $\rightarrow$ *Tránh đuổi theo giá (FOMO).*

**Tầng 3: Xác nhận (Khung 15M)**
- **Logic:** Tìm mô hình nến **Engulfing** (Nhấn chìm).
- **Kết quả:** Chỉ bóp cò khi nến 15M xác nhận đảo chiều. $\rightarrow$ *Tối ưu điểm entry, ngắn SL.*

---

## ⚙️ 2. CHI TIẾT KỸ THUẬT (TECHNICAL STACK)

### 🧠 AI Engine (C++ DLL)
- **Input:** 22 Features (được tính toán Real-time từ MT5).
- **Processing:** 
    - Chuẩn hóa dữ liệu bằng Scaler từ Python.
    - Tính toán hàm `SymmetryLp` (Linear Combination + Sigmoid).
- **Output:** Xác suất (Confidence %) cho từng lớp.

### 💹 Quản lý rủi ro (Risk Management)
- **Sizing:** Lot size tỉ lệ thuận với `Confidence` của AI (AI càng tin $\rightarrow$ Lot càng lớn).
- **Protection:** 
    - `Partial Close`: Chốt lời 3 giai đoạn theo ATR.
    - `Trailing Stop`: Dời SL theo ATR để bảo vệ vốn.
    - `Emergency Stop`: Tự động khóa toàn bộ Bot nếu Equity sụt giảm $> X\%$.

---

## 🛠 3. QUY TRÌNH SETUP NHANH (QUICK START)

1. **Python:** `Sửa CSV` $\rightarrow$ `Chạy train_v10.py` $\rightarrow$ `Lấy ai_model_v10.txt`.
2. **C++:** `Sửa kFeatureCount = 22` $\rightarrow$ `Build Release x64` $\rightarrow$ `Copy DLL`.
3. **MQL5:** `Sửa FeatureCount = 22` $\rightarrow$ `Compile EA` $\rightarrow$ `Copy model.txt vào /Files`.
4. **Run:** `Allow DLL imports` $\rightarrow$ `Kéo Bot vào chart H1`.

---

## 📈 4. SƠ ĐỒ DÒNG DỮ LIỆU (DATA FLOW)

`MT5` $\xrightarrow{\text{H1 Data}}$ `DLL` $\xrightarrow{\text{SMC/H4/M15 Data}}$ `SMC Logic` $\xrightarrow{\text{Combined}}$ `SMC+AI Predict` $\rightarrow$ `Trade`