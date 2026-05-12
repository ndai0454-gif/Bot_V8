from fastapi import FastAPI, Request, BackgroundTasks
import uvicorn
import logging

# Setup logging
logging.basicConfig(level=logging.INFO, filename="logs/webhook.log")

app = FastAPI()

# Biến tạm để lưu tín hiệu cho main.py đọc (Trong thực tế nên dùng Redis)
signal_queue = []

@app.post("/webhook")
async def tradingview_webhook(request: Request, background_tasks: BackgroundTasks):
    try:
        data = await request.json()
        logging.info(f"Signal Received: {data}")
        
        # Đưa tín hiệu vào hàng đợi
        signal_queue.append(data)
        
        return {"status": "success", "message": "Signal queued"}
    except Exception as e:
        logging.error(f"Webhook Error: {e}")
        return {"status": "error", "message": str(e)}

def get_next_signal():
    return signal_queue.pop(0) if signal_queue else None

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5000)
