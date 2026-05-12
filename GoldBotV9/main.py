import time
from api.webhook_server import get_next_signal
from api.gemini_engine import GeminiMacroFilter
from core.execution_engine import ExecutionEngine
from core.risk_engine import RiskEngine # Giả định bạn đã tạo file này

def run_bot():
    print("GoldBot V9 is running...")
    macro_filter = GeminiMacroFilter()
    executor = ExecutionEngine()
    
    while True:
        signal = get_next_signal()
        if signal:
            print(f"Processing signal for {signal['symbol']}...")
            
            # 1. Lấy tin tức giả định (Thay bằng API news thực tế)
            news_data = "US CPI data is higher than expected, USD strengthening"
            sentiment = macro_filter.analyze_sentiment(news_data)
            print(f"Gemini Sentiment: {sentiment}")

            # 2. Lọc tín hiệu (Ví dụ: Chỉ BUY khi Gemini BULLISH hoặc NEUTRAL)
            if signal['action'] == "BUY" and sentiment in ["BULLISH", "NEUTRAL"]:
                # Tính Lot từ Risk Engine (Giả định)
                lot = 0.01 
                executor.open_trade(signal['symbol'], "BUY", lot, 1900, 2000)
                print("Trade Executed!")
            elif signal['action'] == "SELL" and sentiment in ["BEARISH", "NEUTRAL"]:
                lot = 0.01
                executor.open_trade(signal['symbol'], "SELL", lot, 2100, 1900)
                print("Trade Executed!")
            else:
                print("Signal rejected by Gemini Macro Filter.")
        
        time.sleep(1)

if __name__ == "__main__":
    run_bot()
