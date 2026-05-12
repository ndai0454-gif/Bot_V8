# 🏆 GoldBotV9 - AI-Powered Gold Trading System

![Version](https://img.shields.io/badge/Version-V9-gold) 
![Python](https://img.shields.io/badge/Python-3.12-blue) 
![MT5](https://img.shields.io/badge/Platform-MetaTrader%205-green)
![AI](https://img.shields.io/badge/AI-XGBoost%20%26%20Gemini-red)

GoldBotV9 là một hệ thống giao dịch tự động tiên tiến cho cặp **XAUUSD (Vàng)**. Hệ thống kết hợp giữa phân tích kỹ thuật Machine Learning, phân tích vĩ mô thông qua LLM (Gemini AI) và khả năng thực thi tốc độ cao trên nền tảng MetaTrader 5.

---

## 🏗 Kiến Trúc Hệ Thống (Architecture)

Hệ thống được thiết kế theo mô hình **Decoupled Architecture** (Tách rời Não bộ và Thực thi) để đảm bảo độ ổn định và hiệu suất tối đa.

### 1. Brain (Python AI Server)
Đóng vai trò là trung tâm điều khiển, xử lý dữ liệu và đưa ra quyết định.
- **Feature Engine**: Trích xuất đặc trưng từ giá OHLC, tính toán chỉ báo kỹ thuật (RSI, EMA, ATR...).
- **Trainer**: Huấn luyện mô hình XGBoost dựa trên dữ liệu real-time từ MT5.
- **Predictor**: Dự đoán xu hướng giá tiếp theo với độ tin cậy (Confidence Score).
- **Gemini Engine**: Phân tích tin tức vĩ mô và tâm lý thị trường để lọc tín hiệu.
- **FastAPI Server**: Cầu nối HTTP cung cấp tín hiệu cho MT5 với độ trễ cực thấp.

### 2. Execution (MQL5 EA)
Đóng vai trò là "tay chân", thực thi lệnh trực tiếp trên tài khoản giao dịch.
- **WebRequest**: Gửi yêu cầu lấy tín hiệu từ Python Server.
- **Order Management**: Quản lý vào lệnh, Stop Loss (SL), Take Profit (TP) và trailing stop.
- **Real-time Monitoring**: Theo dõi nến M15 và thực thi lệnh tức thì.

---

## 🛠 Luồng Hoạt Động (Workflow)

`MT5 Chart (XAUUSD)` $\xrightarrow{Request}$ `FastAPI Server` $\xrightarrow{Analyze}$ `XGBoost Model` $\rightarrow$ `Signal (BUY/SELL)` $\xrightarrow{Response}$ `MQL5 EA` $\rightarrow$ `Open Trade`

---

## 🚀 Hướng Dẫn Cài Đặt (Setup Guide)

### 📦 Yêu cầu hệ thống
- **Python**: 3.12 (Stable)
- **Platform**: MetaTrader 5 (MT5)
- **Thư viện chính**: `MetaTrader5`, `pandas_ta`, `xgboost`, `fastapi`, `uvicorn`, `google-generativeai`.

### ⚙️ Các bước triển khai

#### 1. Cấu hình Python Server
```bash
# Clone dự án
git clone https://github.com/ndai0454-gif/Bot_V8.git
cd GoldBotV9

# Tạo và kích hoạt môi trường ảo
python -m venv venv
.\venv\Scripts\activate

# Cài đặt dependencies
pip install -r requirements.txt

# Khởi động server
python main.py
```

#### 2. Cấu hình MetaTrader 5
1. Mở **Tools** $\rightarrow$ **Options** $\rightarrow$ **Expert Advisors**.
2. Tích chọn $\checkmark$ **Allow Algo Trading**.
3. Thêm URL vào danh sách WebRequest: `http://127.0.0.1:8000`.
4. Copy `BotVang_V9.mq5` vào thư mục `MQL5/Experts`.
5. Compile (F7) và gắn EA vào chart **XAUUSD, timeframe M15**.

---

## 📂 Cấu Trúc Thư Mục

```text
GoldBotV9/
├── ai/
│   ├── trainer.py          # Huấn luyện model
│   ├── predictor.py        # Dự đoán tín hiệu
│   ├── feature_engine.py   # Xử lý đặc trưng kỹ thuật
│   ├── models/             # Lưu trữ file .pkl
│   └── datasets/          # Lưu trữ dữ liệu lịch sử
├── api/
│   ├── webhook_server.py   # Server tiếp nhận request
│   ├── gemini_engine.py     # Phân tích vĩ mô AI
│   └── economic_calendar.py # Theo dõi tin tức kinh tế
├── core/
│   ├── execution_engine.py  # Quản lý thực thi lệnh
│   ├── risk_engine.py       # Quản lý rủi ro & Lot size
│   ├── trade_manager.py     # Quản lý vị thế
│   └── strategy.pyx         # Chiến thuật tối ưu (Cython)
├── mt5/
│   ├── BotVang_V9.mq5       # EA điều phối chính
│   └── ai_engine.cpp       # Cầu nối DLL (tùy chọn)
└── main.py                 # Điểm khởi chạy hệ thống
```

---

## ⚠️ Cảnh Báo Rủi Ro
*Giao dịch vàng (XAUUSD) tiềm ẩn rủi ro cao. Bot này là một công cụ hỗ trợ dựa trên AI và không đảm bảo lợi nhuận 100%. Hãy thử nghiệm kỹ trên tài khoản **DEMO** trước khi giao dịch thực tế.*

---
**Developed by [ndai0454-gif](https://github.com/ndai0454-gif)**
```

### 💡 Gợi ý thêm cho bạn:
1. **Thêm hình ảnh**: Nếu bạn có ảnh chụp màn hình Bot đang chạy hoặc biểu đồ tín hiệu, hãy tạo thư mục `img/` và chèn vào file MD bằng cú pháp `![Alt text](img/ten_anh.png)`.
2. **File `requirements.txt`**: Để người khác (hoặc chính bạn khi cài máy mới) cài nhanh, hãy tạo file `requirements.txt` bằng lệnh:
   ```powershell
   pip freeze > requirements.txt
