🏆 BotVang V10 — Advanced AI Quantitative Trading System
BotVang V10 là một hệ thống giao dịch tự động (Expert Advisor) chuyên sâu cho MetaTrader 5, kết hợp sức mạnh tính toán của C++ DLL, khả năng học máy của Python và chiến lược quản lý vốn nghiêm ngặt của MQL5.

Phiên bản V10 tập trung giải quyết vấn đề Symmetry (Đối xứng) trong dự báo tài chính và tối ưu hóa hiệu suất thực thi cho các tài sản biến động mạnh, đặc biệt là XAUUSD (Vàng).

🛠 System Structure
Hệ thống được thiết kế theo kiến trúc Hybrid (Lai), tách biệt giữa huấn luyện, tính toán và thực thi:


Apply
BotVang_V10/
├── python/                 # AI Training Pipeline
│   ├── features_v10.py     # Feature Engineering & Robust Scaling
│   ├── train_v10.py        # Multi-class One-vs-Rest Training
│   └── ai_model_v10.txt    # Exported Weights & Scaler Params
├── cpp_dll/                 # High-Performance Inference Engine
│   ├── ai_engine_v10.cpp   # Multi-class Inference Engine (Optimized)
│   ├── ai_engine_v10.sln   # Visual Studio Solution
│   └── x64/Release/
│       └── ai_engine_v10.dll # Compiled Binary
├── mt5/                    # Trading Execution Layer
│   ├── Experts/
│   │   └── BotVang_V10.mq5 # Main EA Logic
│   ├── Libraries/
│   │   └── ai_engine_v10.dll # AI Engine DLL
│   └── Files/
│       └── ai_model_v10.txt   # Trained Model File
└── docs/                   # Documentation
└── readme.md               # Project Guide
🧠 Core Logic & Innovations (V10)
1. Multi-Class Symmetry Fix
Thay vì phân loại nhị phân (Buy/Not-Buy) dễ gây nhiễu, V10 sử dụng mô hình Multi-class One-vs-Rest với 3 lớp dự báo:

Buy (1) | Sell (-1) | Neutral (0)
Logic: Lệnh chỉ được thực thi khi xác suất của lớp Buy hoặc Sell vượt trội hoàn toàn so với lớp Neutral và đạt ngưỡng Confidence tối thiểu. Điều này loại bỏ hiện tượng vào lệnh sai trong vùng Sideway.
2. Robust Feature Engineering
ATR-Normalized Returns: Chuyển đổi lợi nhuận sang đơn vị ATR giúp AI hiểu biến động tương đối, tránh bị đánh lừa bởi các cú spike giá.
Robust Scaler: Sử dụng Median và Interquartile Range (IQR) thay vì Mean/Std để triệt tiêu ảnh hưởng của các nến tin tức cực đoan (outliers).
Session Encoding: Tích hợp dữ liệu phiên giao dịch (London/New York) để nhận diện đặc tính biến động theo thời gian.
3. Realistic PnL Simulation
Slippage Awareness: Trong huấn luyện, mỗi lệnh sai được tính là -1.3 đơn vị (thay vì -1.0) để mô phỏng chính xác chi phí Spread, Slippage và Commission thực tế của Vàng.
4. Professional Risk Management
Confidence-Based Lot Sizing: Khối lượng lệnh tự động điều chỉnh theo độ tự tin của AI ($\text{Prob} > 0.33$).
Multi-stage Exit: Chốt lời từng phần 3 bậc dựa trên ATR và Trailing Stop thích ứng.
Equity Guards: Bảo vệ tài khoản 3 lớp: Daily Loss $\rightarrow$ Weekly Loss $\rightarrow$ Floating Equity Drawdown.
🚀 Installation & Deployment
Step 1: Train the AI Model (Python)
Cài đặt thư viện:
Run
pip install numpy pandas scikit-learn
Chuẩn bị file dữ liệu XAUUSD_H1.csv (cột: open, high, low, close, tick_volume, spread).
Chạy huấn luyện:
Run
python python/train_v10.py
Copy file ai_model_v10.txt vào thư mục MQL5\Files\.
Step 2: Build the AI Engine (C++)
Mở ai_engine_v10.sln bằng Visual Studio 2022.
Chọn cấu hình: Release và nền tảng x64.
Nhấn Ctrl + Shift + B để Build.
Copy file ai_engine_v10.dll vào thư mục MQL5\Libraries\.
Step 3: Setup MetaTrader 5
Copy BotVang_V10.mq5 vào MQL5\Experts\.
Vào Tools $\rightarrow$ Options $\rightarrow$ Expert Advisors $\rightarrow$ Tích chọn "Allow DLL imports".
Kéo Bot vào biểu đồ XAUUSD, khung thời gian H1.
📊 Parameter Guide
| Input | Description | Recommended | | :--- | :--- | :--- | | inpModelPath | Đường dẫn file model trong thư mục /Files | ai_model_v10.txt | | inpRiskPct | % Rủi ro trên mỗi lệnh | 1.0% | | inpMaxEquityDD | Cắt toàn bộ lệnh khi sụt giảm vốn đạt % | 15.0% | | inpUseADXFilter | Chỉ trade khi thị trường có xu hướng (ADX > 20) | true | | inpConfidenceLot| Tự động tăng lot khi AI cực kỳ tự tin | true | | inpUsePartialClose| Chốt lời từng phần 3 giai đoạn | true |

⚠️ Critical Notes
Data Direction: Bot yêu cầu dữ liệu mảng theo thứ tự $\text{Cũ} \rightarrow \text{Mới}$. Điều này đã được xử lý tự động trong code V10.
Slippage: Kết quả backtest thường cao hơn thực tế. Hãy luôn sử dụng tài khoản Demo để kiểm tra độ trễ của Broker trước khi chạy Real.
Model Update: Nên huấn luyện lại model mỗi 30 ngày để cập nhật đặc tính giá mới nhất của thị trường.