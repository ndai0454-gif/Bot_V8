import os
import google.generativeai as genai
from dotenv import load_dotenv

load_dotenv()

class GeminiMacroFilter:
    def __init__(self):
        genai.configure(api_key=os.getenv("GEMINI_API_KEY"))
        self.model = genai.GenerativeModel("gemini-1.5-pro")

    def analyze_sentiment(self, news_text):
        """
        Phân tích tin tức và trả về BULLISH, BEARISH hoặc NEUTRAL
        """
        prompt = f"""
        You are a professional Gold (XAUUSD) analyst. 
        Analyze the following news and determine the short-term market sentiment.
        News: {news_text}
        Return ONLY one word: BULLISH, BEARISH, or NEUTRAL.
        """
        try:
            response = self.model.generate_content(prompt)
            return response.text.strip().upper()
        except Exception as e:
            print(f"Gemini Error: {e}")
            return "NEUTRAL"
