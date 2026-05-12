# GoldBotV9/core/risk_engine.py

class RiskEngine:
    def __init__(self):
        print("RiskEngine initialized.")

    def check_risk(self, symbol, lot):
        return True

    def calculate_lot_size(self, balance, risk_percent=1.0):
        return 0.01