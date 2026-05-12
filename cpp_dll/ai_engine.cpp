// =============================================================================
// ai_engine_v10.cpp — BotVang V10 | MULTI-CLASS & MEMORY OPTIMIZED
// =============================================================================
#include <algorithm>
#include <cmath>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <string>
#include <vector>
#include <windows.h>
#include <sstream>

#ifndef AI_API
#define AI_API extern "C" __declspec(dllexport)
#endif

namespace {

constexpr int kFeatureCount = 16;
const std::string kLogFileName = "ai_engine_v10_debug.csv";

// --- Cấu trúc Model cho 3 lớp (One-vs-Rest) ---
struct ModelClass {
    double bias = 0.0;
    double weights[kFeatureCount] = {};
};

struct Model {
    bool loaded = false;
    ModelClass buy;
    ModelClass sell;
    ModelClass neu;
    double scaler_median[kFeatureCount] = {};
    double scaler_iqr[kFeatureCount] = {};
    double thresholdBuy = 0.6; 
    double thresholdSell = 0.6;
    std::string metadata = "V10_MultiClass";
};

Model g_model;
Model g_model_b; // Hỗ trợ ensemble
double g_lastFeatures[kFeatureCount] = {};
CRITICAL_SECTION g_cs;
bool g_cs_init = false;

// --- UTILS ---
std::string trim(const std::string& s) {
    auto f = s.find_first_not_of(" \t\r\n");
    if (f == std::string::npos) return "";
    auto l = s.find_last_not_of(" \t\r\n");
    return s.substr(f, l - f + 1);
}

bool parseList(const std::string& text, double* out, int count) {
    std::stringstream ss(text);
    std::string item;
    int i = 0;
    while (std::getline(ss, item, ',') && i < count) {
        out[i++] = std::stod(trim(item));
    }
    return i == count;
}

double sigmoid(double z) {
    return 1.0 / (1.0 + std::exp(-std::clamp(z, -40.0, 40.0)));
}

double safeDiv(double num, double den) {
    return std::abs(den) < 1e-12 ? 0.0 : num / den;
}

int getGmtHour(time_t t) {
    struct tm gmt;
    gmtime_s(&gmt, &t);
    return gmt.tm_hour;
}

// --- MEMORY OPTIMIZATION: Log không dùng stringstream trong hot path ---
void logInference(double prob, const double* feat, int signal) {
    std::ofstream f(kLogFileName, std::ios::app);
    if (!f.is_open()) return;

    char timeBuf[32];
    time_t now = time(nullptr);
    struct tm tm_buf;
    localtime_s(&tm_buf, &now);
    strftime(timeBuf, sizeof(timeBuf), "%Y-%m-%d %H:%M:%S", &tm_buf);

    f << timeBuf;
    for (int i = 0; i < kFeatureCount; ++i) f << "," << feat[i];
    f << "," << prob << "," << signal << "\n";
}

// --- INDICATORS (Symmetry Fix: arr[0]=Oldest) ---

double computeAtr(const double* h, const double* l, const double* c, int count, int period = 14) {
    if (count < period + 1) return 1.0;
    double atr = 0.0;
    for (int i = 1; i <= period; ++i) {
        atr += std::max({h[i]-l[i], std::abs(h[i]-c[i-1]), std::abs(l[i]-c[i-1])});
    }
    atr /= period;
    double alpha = 1.0 / period;
    for (int i = period + 1; i < count; ++i) {
        double tr = std::max({h[i]-l[i], std::abs(h[i]-c[i-1]), std::abs(l[i]-c[i-1])});
        atr = alpha * tr + (1.0 - alpha) * atr;
    }
    return atr < 1e-12 ? 1.0 : atr;
}

double computeRsiWilder(const double* c, int count, int period = 14) {
    if (count <= period * 2) return 0.5;
    double gain = 0, loss = 0;
    for (int i = 1; i <= period; ++i) {
        double d = c[i] - c[i-1];
        if (d >= 0) gain += d; else loss -= d;
    }
    gain /= period; loss /= period;
    for (int i = period + 1; i < count; ++i) {
        double d = c[i] - c[i-1];
        gain = (gain * (period - 1) + (d >= 0 ? d : 0)) / period;
        loss = (loss * (period - 1) + (d < 0 ? -d : 0)) / period;
    }
    return (loss <= 1e-12) ? 1.0 : (100.0 - 100.0 / (1.0 + gain / loss)) / 100.0;
}

double computeBBPctB(const double* c, int count, int period = 20) {
    if (count < period) return 0.5;
    double mean = 0;
    for (int i = count - period; i < count; ++i) mean += c[i];
    mean /= period;
    double var = 0;
    for (int i = count - period; i < count; ++i) var += std::pow(c[i] - mean, 2);
    double std = std::sqrt(var / period);
    if (std < 1e-12) return 0.5;
    double lower = mean - 2.0 * std;
    double upper = mean + 2.0 * std;
    return std::clamp((c[count-1] - lower) / (upper - lower), 0.0, 1.0);
}

// --- FEATURE ENGINEERING (Symmetry Fix) ---
void computeFeatures(const double* o, const double* h, const double* l, const double* c, 
                     const long long* v, const int* s, int count, double* feat, time_t bar_time) {
    const int last = count - 1;
    double atr14 = computeAtr(h, l, c, count);

    feat[0] = safeDiv(c[last] - c[last-1], atr14);
    feat[1] = safeDiv(c[last] - c[last-3], atr14);
    feat[2] = safeDiv(c[last] - c[last-8], atr14);
    feat[3] = safeDiv(h[last] - l[last], atr14);
    feat[4] = safeDiv(c[last] - o[last], c[last]);

    double emaF = c[0], emaS = c[0];
    const double aF = 2.0/9.0, aS = 2.0/22.0;
    for (int i = 1; i < count; ++i) {
        emaF = aF * c[i] + (1.0 - aF) * emaF;
        emaS = aS * c[i] + (1.0 - aS) * emaS;
    }
    feat[5] = safeDiv(c[last] - emaF, c[last]);
    feat[6] = safeDiv(c[last] - emaS, c[last]);
    feat[7] = computeRsiWilder(c, count);
    feat[8] = computeBBPctB(c, count);

    double vMean = 0;
    int vWin = std::min(120, count);
    for (int i = count - vWin; i < count; ++i) vMean += (double)v[i];
    vMean /= vWin;
    double vVar = 0;
    for (int i = count - vWin; i < count; ++i) vVar += std::pow((double)v[i] - vMean, 2);
    double vStd = std::sqrt(vVar / vWin);
    feat[9] = safeDiv((double)v[last] - vMean, vStd);
    feat[10] = safeDiv((double)s[last], c[last]);

    int hour = getGmtHour(bar_time);
    feat[11] = (hour >= 7 && hour < 13) ? 1.0 : 0.0; // London
    feat[12] = (hour >= 13 && hour < 17) ? 1.0 : 0.0; // NY

    feat[13] = feat[7] * feat[9];
    feat[14] = (feat[5] - feat[6]) * feat[3];
    feat[15] = (feat[7] - 0.5) * feat[3];
}

double get_prob(const ModelClass& mc, const double* raw) {
    double z = mc.bias;
    for (int i = 0; i < kFeatureCount; ++i) {
        double norm = (raw[i] - g_model.scaler_median[i]) / (g_model.scaler_iqr[i] + 1e-12);
        z += norm * mc.weights[i];
    }
    return sigmoid(z);
}

// =============================================================================
// EXPORTED API
// =============================================================================

AI_API int __stdcall AI_PredictSignal(
    const double* o, const double* h, const double* l, const double* c,
    const long long* v, const int* s, int count, long long bar_time) 
{
    if (!g_model.loaded) return 0;
    double features[kFeatureCount];
    computeFeatures(o, h, l, c, v, s, count, features, (time_t)bar_time);

    double pB = get_prob(g_model.buy, features);
    double pS = get_prob(g_model.sell, features);
    double pN = get_prob(g_model.neu, features);

    if (pB > pS && pB > pN && pB >= g_model.thresholdBuy) return 1;
    if (pS > pB && pS > pN && pS >= g_model.thresholdSell) return -1;
    return 0;
}

AI_API double __stdcall AI_GetSignalConfidence(
    const double* o, const double* h, const double* l, const double* c,
    const long long* v, const int* s, int count, long long bar_time) 
{
    if (!g_model.loaded) return 0.33;
    double features[kFeatureCount];
    computeFeatures(o, h, l, c, v, s, count, features, (time_t)bar_time);
    double pB = get_prob(g_model.buy, features);
    double pS = get_prob(g_model.sell, features);
    double pN = get_prob(g_model.neu, features);
    return std::max({pB, pS, pN});
}

AI_API int __stdcall AI_LoadModel(const wchar_t* pathW) {
    std::string path = "";
    if (pathW) {
        int sz = WideCharToMultiByte(CP_UTF8, 0, pathW, -1, nullptr, 0, nullptr, nullptr);
        if (sz > 1) { path.resize(sz - 1); WideCharToMultiByte(CP_UTF8, 0, pathW, -1, &path[0], sz, nullptr, nullptr); }
    }
    std::ifstream f(path);
    if (!f.is_open()) return 0;

    Model m;
    std::string line;
    while (std::getline(f, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;
        auto eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string k = trim(line.substr(0, eq)), v = trim(line.substr(eq + 1));
        try {
            if (k == "buy_bias") m.buy.bias = std::stod(v);
            else if (k == "buy_weights") parseList(v, m.buy.weights, kFeatureCount);
            else if (k == "sell_bias") m.sell.bias = std::stod(v);
            else if (k == "sell_weights") parseList(v, m.sell.weights, kFeatureCount);
            else if (k == "neu_bias") m.neu.bias = std::stod(v);
            else if (k == "neu_weights") parseList(v, m.neu.weights, kFeatureCount);
            else if (k == "scaler_median") parseList(v, m.scaler_median, kFeatureCount);
            else if (k == "scaler_iqr") parseList(v, m.scaler_iqr, kFeatureCount);
            else if (k == "threshold_buy") m.thresholdBuy = std::stod(v);
            else if (k == "threshold_sell") m.thresholdSell = std::stod(v);
        } catch (...) {}
    }
    m.loaded = true;
    if (g_cs_init) EnterCriticalSection(&g_cs);
    g_model = m;
    if (g_cs_init) LeaveCriticalSection(&g_cs);
    return 1;
}

AI_API int __stdcall AI_LoadModelB(const wchar_t* pathW) {
    // Tương tự AI_LoadModel nhưng gán vào g_model_b
    return AI_LoadModel(pathW); // Simplified for this example
}

AI_API int __stdcall AI_IsModelLoaded() { return g_model.loaded ? 1 : 0; }
AI_API int __stdcall AI_GetFeatureCount() { return kFeatureCount; }
AI_API double __stdcall AI_GetThresholdBuy() { return g_model.thresholdBuy; }
AI_API double __stdcall AI_GetThresholdSell() { return g_model.thresholdSell; }

AI_API double __stdcall AI_GetFeature(int idx) {
    if (idx < 0 || idx >= kFeatureCount) return 0.0;
    return g_lastFeatures[idx];
}

AI_API void __stdcall AI_GetModelMeta(wchar_t* buf, int len) {
    if (!buf) return;
    std::string meta = "V10_MultiClass_SymmetryFix";
    MultiByteToWideChar(CP_UTF8, 0, meta.c_str(), -1, buf, len);
}

AI_API double __stdcall DynamicSL(double atr, int regime) {
    return (regime == 1) ? atr * 2.5 : atr * 2.5; // Có thể tùy chỉnh theo regime
}

AI_API double __stdcall DynamicTP(double atr, int regime) {
    return (regime == 1) ? atr * 4.0 : atr * 4.0; 
}

} // namespace

BOOL APIENTRY DllMain(HMODULE h, DWORD r, LPVOID p) {
    if (r == DLL_PROCESS_ATTACH) {
        InitializeCriticalSection(&g_cs);
        g_cs_init = true;
    } else if (r == DLL_PROCESS_DETACH && g_cs_init) {
        DeleteCriticalSection(&g_cs);
    }
    return TRUE;
}
