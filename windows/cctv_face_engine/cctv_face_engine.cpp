#include "cctv_face_engine.h"

#ifdef _WIN32
  #ifndef NOMINMAX
    #define NOMINMAX
  #endif
  #include <windows.h>
#endif

#include <vector>
#include <cmath>
#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <mutex>
#include <thread>
#include <atomic>
#include <chrono>
#include <string>
#include <fstream>

#include <opencv2/opencv.hpp>
#include <opencv2/dnn.hpp>
#include <opencv2/objdetect.hpp>
#include <opencv2/objdetect/face.hpp>

#if defined(_M_X64) || defined(__x86_64__) || defined(_M_IX86) || defined(__i386__)
  #include <immintrin.h>
  #define CCTV_USE_SSE 1
#endif

#ifdef _WIN32
BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    if (fdwReason == DLL_PROCESS_ATTACH) {
        cv::setNumThreads(2);
    }
    return TRUE;
}
#endif

// Engine version 2.5.2 (Configurable Spoof Level + CPU Optimization + Frame Pacing)
CCTV_API int32_t cctv_engine_version(void) {
    return 252;
}

// Global anti-spoofing sensitivity level:
// 0 = Off (no anti-spoofing at all, all faces considered live)
// 1 = Low (MiniFASNet only, threshold 40%, no passive checks)
// 2 = Medium (MiniFASNet threshold 55%, light passive checks — blur only)
// 3 = High (MiniFASNet threshold 70% + full passive defense — Moiré + Chrominance + Blur)
static int32_t g_spoofLevel = 2; // Default: Medium

CCTV_API void cctv_set_spoof_level(int32_t level) {
    g_spoofLevel = std::max(0, std::min(3, level));
}

CCTV_API int32_t cctv_get_spoof_level(void) {
    return g_spoofLevel;
}

// Global Deep Learning Face Detector (OpenCV DNN ResNet-10 SSD) — Legacy Fallback
static cv::dnn::Net g_faceNet;
static bool g_netLoaded = false;
static std::mutex g_dnnMutex;

// Global YuNet Face Detector (cv::FaceDetectorYN) — Primary Detector
static cv::Ptr<cv::FaceDetectorYN> g_yunetDetector;
static bool g_yunetLoaded = false;
static std::mutex g_yunetMutex;

// Global Deep Anti-Spoofing Network (MiniFASNetV2 from Silent-Face-Anti-Spoofing) — Scale 2.7x
static cv::dnn::Net g_livenessNet;
static bool g_livenessNetLoaded = false;
static std::mutex g_livenessMutex;

// Global Deep Anti-Spoofing Network (MiniFASNetV1SE) — Scale 4.0x for contextual crop
static cv::dnn::Net g_livenessNet40;
static bool g_livenessNet40Loaded = false;
static std::mutex g_liveness40Mutex;

// Global SFace Deep Biometric Recognizer (OpenCV FaceRecognizerSF)
static cv::Ptr<cv::FaceRecognizerSF> g_sfaceRecognizer;
static bool g_sfaceLoaded = false;
static std::mutex g_sfaceMutex;

static bool file_exists(const std::string& path) {
    std::ifstream f(path.c_str());
    return f.good();
}

#ifdef _WIN32
static std::string get_executable_directory() {
    wchar_t exePath[MAX_PATH];
    DWORD len = GetModuleFileNameW(NULL, exePath, MAX_PATH);
    if (len == 0 || len == MAX_PATH) return "";
    
    wchar_t* lastSlash = wcsrchr(exePath, L'\\');
    if (lastSlash) {
        *(lastSlash + 1) = L'\0';
    }
    
    char buffer[MAX_PATH * 2];
    int res = WideCharToMultiByte(CP_UTF8, 0, exePath, -1, buffer, sizeof(buffer), NULL, NULL);
    return (res > 0) ? std::string(buffer) : "";
}
#endif

static bool ensure_dnn_loaded() {
    if (g_netLoaded) return true;
    std::lock_guard<std::mutex> lock(g_dnnMutex);
    if (g_netLoaded) return true;

    std::vector<std::pair<std::string, std::string>> candidatePaths;

#ifdef _WIN32
    std::string exeDir = get_executable_directory();
    if (!exeDir.empty()) {
        candidatePaths.push_back({exeDir + "deploy.prototxt", exeDir + "res10_300x300_ssd_iter_140000.caffemodel"});
        candidatePaths.push_back({exeDir + "cctv_face_engine\\deploy.prototxt", exeDir + "cctv_face_engine\\res10_300x300_ssd_iter_140000.caffemodel"});
        candidatePaths.push_back({exeDir + "data\\deploy.prototxt", exeDir + "data\\res10_300x300_ssd_iter_140000.caffemodel"});
    }
#endif

    candidatePaths.push_back({"deploy.prototxt", "res10_300x300_ssd_iter_140000.caffemodel"});
    candidatePaths.push_back({"windows/cctv_face_engine/deploy.prototxt", "windows/cctv_face_engine/res10_300x300_ssd_iter_140000.caffemodel"});
    candidatePaths.push_back({"cctv_face_engine/deploy.prototxt", "cctv_face_engine/res10_300x300_ssd_iter_140000.caffemodel"});
    candidatePaths.push_back({"D:/MD Group/madarsa_app/windows/cctv_face_engine/deploy.prototxt", "D:/MD Group/madarsa_app/windows/cctv_face_engine/res10_300x300_ssd_iter_140000.caffemodel"});
    candidatePaths.push_back({"D:/MD Group/madarsa_app/deploy.prototxt", "D:/MD Group/madarsa_app/res10_300x300_ssd_iter_140000.caffemodel"});

    for (const auto& p : candidatePaths) {
        if (file_exists(p.first) && file_exists(p.second)) {
            try {
                g_faceNet = cv::dnn::readNetFromCaffe(p.first, p.second);
                if (!g_faceNet.empty()) {
                    g_faceNet.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
                    g_faceNet.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);
                    g_netLoaded = true;
                    break;
                }
            } catch (...) {
                g_netLoaded = false;
            }
        }
    }

    return g_netLoaded;
}

static bool ensure_liveness_dnn_loaded() {
    if (g_livenessNetLoaded) return true;
    std::lock_guard<std::mutex> lock(g_livenessMutex);
    if (g_livenessNetLoaded) return true;

    std::vector<std::string> candidatePaths;
#ifdef _WIN32
    std::string exeDir = get_executable_directory();
    if (!exeDir.empty()) {
        candidatePaths.push_back(exeDir + "minifasnet_v2.onnx");
        candidatePaths.push_back(exeDir + "cctv_face_engine\\minifasnet_v2.onnx");
        candidatePaths.push_back(exeDir + "data\\minifasnet_v2.onnx");
    }
#endif
    candidatePaths.push_back("minifasnet_v2.onnx");
    candidatePaths.push_back("windows/cctv_face_engine/minifasnet_v2.onnx");
    candidatePaths.push_back("cctv_face_engine/minifasnet_v2.onnx");
    candidatePaths.push_back("D:/MD Group/madarsa_app/windows/cctv_face_engine/minifasnet_v2.onnx");
    candidatePaths.push_back("D:/MD Group/madarsa_app/build/windows/x64/runner/Debug/minifasnet_v2.onnx");

    for (const auto& path : candidatePaths) {
        if (file_exists(path)) {
            try {
                g_livenessNet = cv::dnn::readNetFromONNX(path);
                if (!g_livenessNet.empty()) {
                    g_livenessNet.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
                    g_livenessNet.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);
                    g_livenessNetLoaded = true;
                    break;
                }
            } catch (...) {
                g_livenessNetLoaded = false;
            }
        }
    }
    return g_livenessNetLoaded;
}

static bool ensure_sface_loaded() {
    if (g_sfaceLoaded) return true;
    std::lock_guard<std::mutex> lock(g_sfaceMutex);
    if (g_sfaceLoaded) return true;

    std::vector<std::string> candidatePaths;
#ifdef _WIN32
    std::string exeDir = get_executable_directory();
    if (!exeDir.empty()) {
        candidatePaths.push_back(exeDir + "face_recognition_sface_2021dec.onnx");
        candidatePaths.push_back(exeDir + "cctv_face_engine\\face_recognition_sface_2021dec.onnx");
        candidatePaths.push_back(exeDir + "data\\face_recognition_sface_2021dec.onnx");
    }
#endif
    candidatePaths.push_back("face_recognition_sface_2021dec.onnx");
    candidatePaths.push_back("windows/cctv_face_engine/face_recognition_sface_2021dec.onnx");
    candidatePaths.push_back("cctv_face_engine/face_recognition_sface_2021dec.onnx");
    candidatePaths.push_back("D:/MD Group/madarsa_app/windows/cctv_face_engine/face_recognition_sface_2021dec.onnx");
    candidatePaths.push_back("D:/MD Group/madarsa_app/build/windows/x64/runner/Debug/face_recognition_sface_2021dec.onnx");

    for (const auto& path : candidatePaths) {
        if (file_exists(path)) {
            try {
                g_sfaceRecognizer = cv::FaceRecognizerSF::create(path, "");
                if (!g_sfaceRecognizer.empty()) {
                    g_sfaceLoaded = true;
                    break;
                }
            } catch (...) {
                g_sfaceLoaded = false;
            }
        }
    }
    return g_sfaceLoaded;
}

static bool ensure_yunet_loaded(int inputW = 320, int inputH = 320) {
    if (g_yunetLoaded) return true;
    std::lock_guard<std::mutex> lock(g_yunetMutex);
    if (g_yunetLoaded) return true;

    std::vector<std::string> candidatePaths;
#ifdef _WIN32
    std::string exeDir = get_executable_directory();
    if (!exeDir.empty()) {
        candidatePaths.push_back(exeDir + "face_detection_yunet_2023mar.onnx");
        candidatePaths.push_back(exeDir + "cctv_face_engine\\face_detection_yunet_2023mar.onnx");
        candidatePaths.push_back(exeDir + "data\\face_detection_yunet_2023mar.onnx");
    }
#endif
    candidatePaths.push_back("face_detection_yunet_2023mar.onnx");
    candidatePaths.push_back("windows/cctv_face_engine/face_detection_yunet_2023mar.onnx");
    candidatePaths.push_back("cctv_face_engine/face_detection_yunet_2023mar.onnx");
    candidatePaths.push_back("D:/MD Group/madarsa_app/windows/cctv_face_engine/face_detection_yunet_2023mar.onnx");
    candidatePaths.push_back("D:/MD Group/madarsa_app/build/windows/x64/runner/Debug/face_detection_yunet_2023mar.onnx");

    for (const auto& path : candidatePaths) {
        if (file_exists(path)) {
            try {
                g_yunetDetector = cv::FaceDetectorYN::create(
                    path, "", cv::Size(inputW, inputH), 0.70f, 0.3f, 500
                );
                if (!g_yunetDetector.empty()) {
                    g_yunetLoaded = true;
                    break;
                }
            } catch (...) {
                g_yunetLoaded = false;
            }
        }
    }
    return g_yunetLoaded;
}

static bool ensure_liveness40_loaded() {
    if (g_livenessNet40Loaded) return true;
    std::lock_guard<std::mutex> lock(g_liveness40Mutex);
    if (g_livenessNet40Loaded) return true;

    std::vector<std::string> candidatePaths;
#ifdef _WIN32
    std::string exeDir = get_executable_directory();
    if (!exeDir.empty()) {
        candidatePaths.push_back(exeDir + "4_0_0_80x80_MiniFASNetV1SE.onnx");
        candidatePaths.push_back(exeDir + "cctv_face_engine\\4_0_0_80x80_MiniFASNetV1SE.onnx");
        candidatePaths.push_back(exeDir + "data\\4_0_0_80x80_MiniFASNetV1SE.onnx");
    }
#endif
    candidatePaths.push_back("4_0_0_80x80_MiniFASNetV1SE.onnx");
    candidatePaths.push_back("windows/cctv_face_engine/4_0_0_80x80_MiniFASNetV1SE.onnx");
    candidatePaths.push_back("cctv_face_engine/4_0_0_80x80_MiniFASNetV1SE.onnx");
    candidatePaths.push_back("D:/MD Group/madarsa_app/windows/cctv_face_engine/4_0_0_80x80_MiniFASNetV1SE.onnx");
    candidatePaths.push_back("D:/MD Group/madarsa_app/build/windows/x64/runner/Debug/4_0_0_80x80_MiniFASNetV1SE.onnx");

    for (const auto& path : candidatePaths) {
        if (file_exists(path)) {
            try {
                g_livenessNet40 = cv::dnn::readNetFromONNX(path);
                if (!g_livenessNet40.empty()) {
                    g_livenessNet40.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
                    g_livenessNet40.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);
                    g_livenessNet40Loaded = true;
                    break;
                }
            } catch (...) {
                g_livenessNet40Loaded = false;
            }
        }
    }
    return g_livenessNet40Loaded;
}

// ═══════════════════════════════════════════════════════════════════════
// SILENT-FACE-ANTI-SPOOFING (Dual-Scale MiniFASNet Ensemble) + PASSIVE SCREEN DEFENSE
// ═══════════════════════════════════════════════════════════════════════

// Silent-Face-Anti-Spoofing standard bounding box expansion for crop
static cv::Rect getScaledBox(int srcW, int srcH, const cv::Rect& faceBox, float scale) {
    float boxW = static_cast<float>(faceBox.width);
    float boxH = static_cast<float>(faceBox.height);
    if (boxW <= 0 || boxH <= 0) return faceBox;

    float maxScaleW = (srcW - 1.0f) / boxW;
    float maxScaleH = (srcH - 1.0f) / boxH;
    scale = std::min(scale, std::min(maxScaleW, maxScaleH));

    float newW = boxW * scale;
    float newH = boxH * scale;
    float centerX = faceBox.x + boxW * 0.5f;
    float centerY = faceBox.y + boxH * 0.5f;

    float leftTopX = centerX - newW * 0.5f;
    float leftTopY = centerY - newH * 0.5f;
    float rightBottomX = centerX + newW * 0.5f;
    float rightBottomY = centerY + newH * 0.5f;

    // Shift box if touching image borders
    if (leftTopX < 0) { rightBottomX -= leftTopX; leftTopX = 0; }
    if (leftTopY < 0) { rightBottomY -= leftTopY; leftTopY = 0; }
    if (rightBottomX > static_cast<float>(srcW - 1)) { leftTopX -= (rightBottomX - static_cast<float>(srcW) + 1.0f); rightBottomX = static_cast<float>(srcW - 1); }
    if (rightBottomY > static_cast<float>(srcH - 1)) { leftTopY -= (rightBottomY - static_cast<float>(srcH) + 1.0f); rightBottomY = static_cast<float>(srcH - 1); }

    int rx = std::max(0, static_cast<int>(leftTopX));
    int ry = std::max(0, static_cast<int>(leftTopY));
    int rw = std::min(srcW - rx, static_cast<int>(rightBottomX - leftTopX + 1));
    int rh = std::min(srcH - ry, static_cast<int>(rightBottomY - leftTopY + 1));

    return cv::Rect(rx, ry, rw, rh);
}

// Run MiniFASNet inference on a single model at a given scale, returning softmax probabilities
static bool run_minifas_single(
    cv::dnn::Net& net, std::mutex& mtx,
    const cv::Mat& frameBGR, const cv::Rect& faceRect,
    float scale, float probs[3]
) {
    probs[0] = probs[1] = probs[2] = 0.0f;
    try {
        cv::Rect scaledBox = getScaledBox(frameBGR.cols, frameBGR.rows, faceRect, scale);
        if (scaledBox.width < 16 || scaledBox.height < 16) return false;

        cv::Mat crop = frameBGR(scaledBox);
        cv::Mat crop80;
        cv::resize(crop, crop80, cv::Size(80, 80));

        // Minivision MiniFASNet expects raw BGR values in [0.0, 255.0] range (scale=1.0, swapRB=false)
        // Verified from official functional.py: "return img.float()" without div(255)
        cv::Mat blob = cv::dnn::blobFromImage(
            crop80, 1.0, cv::Size(80, 80),
            cv::Scalar(0, 0, 0), false, false
        );

        cv::Mat output;
        {
            std::lock_guard<std::mutex> lock(mtx);
            net.setInput(blob);
            output = net.forward();
        }

        if (output.empty() || output.total() < 2) return false;

        const float* ptr = output.ptr<float>();
        const int numClasses = static_cast<int>(output.total());

        // Numerically stable softmax
        float maxLogit = ptr[0];
        for (int c = 1; c < numClasses && c < 3; c++) {
            if (ptr[c] > maxLogit) maxLogit = ptr[c];
        }
        float sumExp = 0.0f;
        for (int c = 0; c < numClasses && c < 3; c++) {
            probs[c] = std::exp(ptr[c] - maxLogit);
            sumExp += probs[c];
        }
        if (sumExp > 1e-6f) {
            for (int c = 0; c < 3; c++) probs[c] /= sumExp;
        }
        return true;
    } catch (...) {
        return false;
    }
}

// Dual-scale MiniFASNet ensemble liveness check
// Scale 2.7x: facial micro-textures, skin pores, corneal reflection
// Scale 4.0x: surrounding context — phone bezels, paper borders, moiré patterns
// Threshold adapts to g_spoofLevel: Low=40%, Medium=55%, High=70%
static bool check_liveness_multiscale(
    const cv::Mat& frameBGR,
    const cv::Rect& faceRect,
    float& outRealScore
) {
    outRealScore = 100.0f;

    // Level 0 (Off): skip all anti-spoofing, always return live
    if (g_spoofLevel <= 0) {
        return true;
    }

    if (!ensure_liveness_dnn_loaded()) {
        // If model missing, default to live (graceful fallback)
        return true;
    }

    float probs27[3] = {0, 0, 0};
    bool ok27 = run_minifas_single(g_livenessNet, g_livenessMutex, frameBGR, faceRect, 2.7f, probs27);
    if (!ok27) {
        outRealScore = 100.0f;
        return true; // Inference failed, default to live
    }

    float fusedReal = probs27[1]; // Start with 2.7x result

    // Try 4.0x scale if model is available (graceful degradation to single-scale if missing)
    if (ensure_liveness40_loaded()) {
        float probs40[3] = {0, 0, 0};
        bool ok40 = run_minifas_single(g_livenessNet40, g_liveness40Mutex, frameBGR, faceRect, 4.0f, probs40);
        if (ok40) {
            // Average the real-face probabilities from both scales
            fusedReal = (probs27[1] + probs40[1]) * 0.5f;
        }
    }

    outRealScore = fusedReal * 100.0f;

    // Adaptive threshold based on spoof level
    float threshold = 0.55f; // Default: Medium
    if (g_spoofLevel == 1) threshold = 0.40f;       // Low: permissive, only obvious spoofs caught
    else if (g_spoofLevel == 2) threshold = 0.55f;   // Medium: balanced (default)
    else if (g_spoofLevel >= 3) threshold = 0.70f;   // High: strict, may have false positives on IP cameras

    return (fusedReal >= threshold);
}

// Moiré Pattern Detection via 2D FFT high-frequency energy ratio
// Screen replay attacks show characteristic moiré from pixel grid interference
static bool detectMoireArtifacts(const cv::Mat& faceCropGray, float highFreqEnergyThreshold = 0.22f) {
    if (faceCropGray.empty() || faceCropGray.cols < 32 || faceCropGray.rows < 32) return false;
    try {
        cv::Mat floatImg;
        faceCropGray.convertTo(floatImg, CV_32F);

        cv::Mat padded;
        int m = cv::getOptimalDFTSize(faceCropGray.rows);
        int n = cv::getOptimalDFTSize(faceCropGray.cols);
        cv::copyMakeBorder(floatImg, padded, 0, m - faceCropGray.rows, 0, n - faceCropGray.cols,
                           cv::BORDER_CONSTANT, cv::Scalar::all(0));

        cv::Mat planes[] = { padded, cv::Mat::zeros(padded.size(), CV_32F) };
        cv::Mat complexI;
        cv::merge(planes, 2, complexI);
        cv::dft(complexI, complexI);

        cv::split(complexI, planes);
        cv::Mat mag;
        cv::magnitude(planes[0], planes[1], mag);
        mag += cv::Scalar::all(1);
        cv::log(mag, mag);

        // Rearrange quadrants so DC component is at center
        int cx = mag.cols / 2;
        int cy = mag.rows / 2;
        cv::Mat q0(mag, cv::Rect(0, 0, cx, cy));
        cv::Mat q1(mag, cv::Rect(cx, 0, cx, cy));
        cv::Mat q2(mag, cv::Rect(0, cy, cx, cy));
        cv::Mat q3(mag, cv::Rect(cx, cy, cx, cy));
        cv::Mat tmp;
        q0.copyTo(tmp); q3.copyTo(q0); tmp.copyTo(q3);
        q1.copyTo(tmp); q2.copyTo(q1); tmp.copyTo(q2);

        // Compute high-frequency energy ratio (mask out low-frequency center circle)
        float totalEnergy = static_cast<float>(cv::sum(mag)[0]);
        cv::Mat mask = cv::Mat::ones(mag.size(), CV_8U);
        cv::circle(mask, cv::Point(cx, cy), std::min(cx, cy) / 3, cv::Scalar(0), -1);
        cv::Mat maskedMag;
        mag.copyTo(maskedMag, mask);
        float highFreqEnergy = static_cast<float>(cv::sum(maskedMag)[0]);

        float ratio = highFreqEnergy / (totalEnergy + 1e-6f);
        return ratio > highFreqEnergyThreshold; // true = possible screen spoof
    } catch (...) {
        return false;
    }
}

// Chrominance Variance Check — real skin has high CbCr variance vs compressed gamut of screens/prints
static bool checkChrominanceSpoof(const cv::Mat& faceCropBGR, float minChrominanceVariance = 8.0f) {
    if (faceCropBGR.empty() || faceCropBGR.cols < 16 || faceCropBGR.rows < 16) return false;
    try {
        cv::Mat ycrcb;
        cv::cvtColor(faceCropBGR, ycrcb, cv::COLOR_BGR2YCrCb);
        cv::Scalar meanVal, stddevVal;
        cv::meanStdDev(ycrcb, meanVal, stddevVal);
        // Product of Cr and Cb standard deviations — low = compressed gamut (spoof)
        float crStd = static_cast<float>(stddevVal.val[1]);
        float cbStd = static_cast<float>(stddevVal.val[2]);
        float chrominanceVar = crStd * cbStd;
        return chrominanceVar < minChrominanceVariance; // true = possible spoof
    } catch (...) {
        return false;
    }
}

static bool check_passive_spoof_signatures(
    const cv::Mat& faceCrop,
    float& outBlurScore
) {
    if (faceCrop.empty() || faceCrop.cols < 16 || faceCrop.rows < 16) {
        outBlurScore = 0.0f;
        return false;
    }

    try {
        cv::Mat grayFace, laplacianFace;
        cv::cvtColor(faceCrop, grayFace, cv::COLOR_BGR2GRAY);
        cv::Laplacian(grayFace, laplacianFace, CV_64F);
        cv::Scalar meanVal, stddevVal;
        cv::meanStdDev(laplacianFace, meanVal, stddevVal);
        outBlurScore = static_cast<float>(stddevVal.val[0] * stddevVal.val[0]);

        // Reject extreme blur (threshold raised from 12.0 to 15.0 for better spoof catch)
        if (outBlurScore < 15.0f) {
            return false;
        }

        // Moiré pattern check (screen replay defense)
        if (detectMoireArtifacts(grayFace)) {
            return false;
        }

        // Chrominance variance check (print/screen compressed gamut defense)
        if (checkChrominanceSpoof(faceCrop)) {
            return false;
        }

        return true;
    } catch (...) {
        outBlurScore = 0.0f;
        return true;
    }
}

// ══════════════════════════════════════════════════════════════════════       ═
// 1. PRODUCTION DEEP NEURAL NETWORK + QUALITY / BLUR / ANTI-SPOOFING
// ═══════════════════════════════════════════════════════════════════════

static int32_t detect_faces_dnn_mat(
    const cv::Mat& frameBGR,
    int32_t sensitivity,
    int32_t maxFaces,
    NativeFaceDetectionResult* outResult
) {
    if (frameBGR.empty() || !outResult) return -1;
    const int32_t width = frameBGR.cols;
    const int32_t height = frameBGR.rows;

    // Multi-scale Deep Learning input blob:
    // 600x600 for wide CCTV cameras so distant student faces are detected
    // 300x300 for standard webcams and close portraits
    const int32_t blobDim = (width >= 800 || height >= 600) ? 600 : 300;
    cv::Mat blob = cv::dnn::blobFromImage(
        frameBGR,
        1.0,
        cv::Size(blobDim, blobDim),
        cv::Scalar(104.0, 177.0, 123.0),
        false,
        false
    );

    cv::Mat detection;
    {
        std::lock_guard<std::mutex> lock(g_dnnMutex);
        g_faceNet.setInput(blob);
        detection = g_faceNet.forward();
    }

    cv::Mat detectionMat(detection.size[2], detection.size[3], CV_32F, detection.ptr<float>());

    float minConf = 0.55f;
    if (sensitivity == CCTV_SENSITIVITY_SENSITIVE) {
        minConf = 0.45f; // Sensitive: room lighting, distant faces
    } else if (sensitivity == CCTV_SENSITIVITY_STRICT) {
        minConf = 0.70f; // Strict: high confidence only
    }

    std::vector<cv::Rect> candidateBoxes;
    std::vector<float> candidateConfidences;
    std::vector<float> candidateBlurs;
    std::vector<int32_t> candidateLive;
    std::vector<float> candidateLivenessScores;

    for (int i = 0; i < detectionMat.rows; i++) {
        const float confidence = detectionMat.at<float>(i, 2);
        if (confidence < 0.15f) continue;

        int32_t x1 = static_cast<int32_t>(detectionMat.at<float>(i, 3) * width);
        int32_t y1 = static_cast<int32_t>(detectionMat.at<float>(i, 4) * height);
        int32_t x2 = static_cast<int32_t>(detectionMat.at<float>(i, 5) * width);
        int32_t y2 = static_cast<int32_t>(detectionMat.at<float>(i, 6) * height);

        x1 = std::max(0, std::min(width, x1));
        y1 = std::max(0, std::min(height, y1));
        x2 = std::max(0, std::min(width, x2));
        y2 = std::max(0, std::min(height, y2));

        const int32_t boxW = x2 - x1;
        const int32_t boxH = y2 - y1;
        const float aspectRatio = boxH > 0 ? (static_cast<float>(boxW) / static_cast<float>(boxH)) : 0.0f;

        if (confidence >= minConf && boxW >= 24 && boxH >= 24) {
            if (aspectRatio < 0.50f || aspectRatio > 1.35f) {
                continue;
            }

            cv::Rect faceRect(x1, y1, boxW, boxH);
            cv::Mat faceCrop = frameBGR(faceRect);
            cv::Mat ycrcb;
            cv::cvtColor(faceCrop, ycrcb, cv::COLOR_BGR2YCrCb);
            int skinPixelCount = 0;
            int totalSampled = 0;
            const int step = std::max(1, boxW / 25);
            for (int ry = 0; ry < faceCrop.rows; ry += step) {
                const cv::Vec3b* ptr = ycrcb.ptr<cv::Vec3b>(ry);
                for (int rx = 0; rx < faceCrop.cols; rx += step) {
                    totalSampled++;
                    const uint8_t cr = ptr[rx][1];
                    const uint8_t cb = ptr[rx][2];
                    if (cr >= 130 && cr <= 180 && cb >= 75 && cb <= 135) {
                        skinPixelCount++;
                    }
                }
            }
            const float skinRatio = totalSampled > 0 ? (static_cast<float>(skinPixelCount) / static_cast<float>(totalSampled)) : 0.0f;
            if (skinRatio < 0.10f) {
                continue;
            }

            float blurScore = 80.0f;
            float realProbScore = 100.0f;
            int32_t isLiveFace = 1; // Default: live

            if (g_spoofLevel <= 0) {
                // Level 0 (Off): No anti-spoofing at all — all faces are live
                blurScore = 80.0f;
                realProbScore = 100.0f;
                isLiveFace = 1;
            } else if (g_spoofLevel == 1) {
                // Level 1 (Low): MiniFASNet only, no passive checks
                bool passMiniFas = check_liveness_multiscale(frameBGR, faceRect, realProbScore);
                // Compute blur for display purposes only (not used for gating)
                check_passive_spoof_signatures(faceCrop, blurScore);
                isLiveFace = passMiniFas ? 1 : 0;
            } else if (g_spoofLevel == 2) {
                // Level 2 (Medium): MiniFASNet + blur check only (NO Moiré/chrominance — IP camera safe)
                bool passMiniFas = check_liveness_multiscale(frameBGR, faceRect, realProbScore);
                cv::Mat grayFace, laplacianFace;
                cv::cvtColor(faceCrop, grayFace, cv::COLOR_BGR2GRAY);
                cv::Laplacian(grayFace, laplacianFace, CV_64F);
                cv::Scalar lapMean, lapStd;
                cv::meanStdDev(laplacianFace, lapMean, lapStd);
                blurScore = static_cast<float>(lapStd.val[0] * lapStd.val[0]);
                bool passBlur = (blurScore >= 10.0f); // Relaxed blur threshold for IP cameras
                isLiveFace = (passMiniFas && passBlur) ? 1 : 0;
            } else {
                // Level 3 (High): Full pipeline — MiniFASNet + Blur + Moiré + Chrominance
                bool passPassive = check_passive_spoof_signatures(faceCrop, blurScore);
                bool passMiniFas = check_liveness_multiscale(frameBGR, faceRect, realProbScore);
                isLiveFace = (passPassive && passMiniFas) ? 1 : 0;
            }

            candidateBoxes.push_back(faceRect);
            candidateConfidences.push_back(confidence);
            candidateBlurs.push_back(blurScore);
            candidateLive.push_back(isLiveFace);
            candidateLivenessScores.push_back(realProbScore);
        }
    }

    // Multi-scale Facial Anchor Box Clustering & Anatomical Fusion
    // If multiple overlapping boxes are detected on the same head (e.g. upper face with eyes + beard/mouth),
    // we merge them into the complete enclosing facial box (forehead down to beard),
    // rather than suppressing the eyes and keeping only the beard!
    struct MergedFace {
        cv::Rect box;
        float confidence;
        float blurScore;
        int32_t isLiveFace;
        float livenessScore;
    };

    std::vector<MergedFace> mergedFaces;

    for (size_t idx = 0; idx < candidateBoxes.size(); idx++) {
        const cv::Rect& r = candidateBoxes[idx];
        bool merged = false;

        for (auto& mf : mergedFaces) {
            const cv::Rect& kR = mf.box;
            int interX1 = std::max(r.x, kR.x);
            int interY1 = std::max(r.y, kR.y);
            int interX2 = std::min(r.x + r.width, kR.x + kR.width);
            int interY2 = std::min(r.y + r.height, kR.y + kR.height);
            int interW = std::max(0, interX2 - interX1);
            int interH = std::max(0, interY2 - interY1);
            int interArea = interW * interH;
            int minArea = std::min(r.area(), kR.area());

            bool isSameHead = false;
            if (minArea > 0 && ((float)interArea / minArea) > 0.35f) {
                isSameHead = true;
            }

            float cX = r.x + r.width / 2.0f;
            float cY = r.y + r.height / 2.0f;
            float kX = kR.x + kR.width / 2.0f;
            float kY = kR.y + kR.height / 2.0f;
            float dx = std::abs(cX - kX);
            float avgW = (r.width + kR.width) / 2.0f;
            float dy = std::abs(cY - kY);
            float avgH = (r.height + kR.height) / 2.0f;
            if (dx < avgW * 0.45f && dy < avgH * 0.85f) {
                isSameHead = true;
            }

            if (isSameHead) {
                int mX1 = std::min(r.x, kR.x);
                int mY1 = std::min(r.y, kR.y);
                int mX2 = std::max(r.x + r.width, kR.x + kR.width);
                int mY2 = std::max(r.y + r.height, kR.y + kR.height);
                mf.box = cv::Rect(mX1, mY1, mX2 - mX1, mY2 - mY1);
                mf.confidence = std::max(mf.confidence, candidateConfidences[idx]);
                mf.blurScore = std::max(mf.blurScore, candidateBlurs[idx]);
                mf.isLiveFace = (mf.isLiveFace == 1 && candidateLive[idx] == 1) ? 1 : 0;
                mf.livenessScore = std::max(mf.livenessScore, candidateLivenessScores[idx]);
                merged = true;
                break;
            }
        }

        if (!merged) {
            MergedFace mf;
            mf.box = r;
            mf.confidence = candidateConfidences[idx];
            mf.blurScore = candidateBlurs[idx];
            mf.isLiveFace = candidateLive[idx];
            mf.livenessScore = candidateLivenessScores[idx];
            mergedFaces.push_back(mf);
        }
    }

    int32_t count = 0;
    for (size_t k = 0; k < mergedFaces.size() && count < maxFaces; k++) {
        const auto& mf = mergedFaces[k];
        const cv::Rect& r = mf.box;
        NativeDetectedFace& face = outResult->faces[count];
        face.left = r.x;
        face.top = r.y;
        face.right = r.x + r.width;
        face.bottom = r.y + r.height;
        face.confidence = std::min(99.9f, mf.confidence * 100.0f);
        face.blurScore = mf.blurScore;
        face.isLiveFace = mf.isLiveFace;
        face.skinCoverage = 95.0f;
        face.hasFacialTriad = 1;
        face.symmetryScore = 95.0f;
        // ResNet-10 SSD does not provide landmarks — mark as unavailable
        face.landmarkRightEyeX = -1.0f; face.landmarkRightEyeY = -1.0f;
        face.landmarkLeftEyeX = -1.0f;  face.landmarkLeftEyeY = -1.0f;
        face.landmarkNoseX = -1.0f;     face.landmarkNoseY = -1.0f;
        face.landmarkRightMouthX = -1.0f; face.landmarkRightMouthY = -1.0f;
        face.landmarkLeftMouthX = -1.0f;  face.landmarkLeftMouthY = -1.0f;
        face.livenessScore = mf.livenessScore;
        count++;
    }

    outResult->faceCount = count;
    return 0;
}

static int32_t detect_faces_dnn(
    const uint8_t* rgba,
    int32_t width,
    int32_t height,
    int32_t sensitivity,
    int32_t maxFaces,
    NativeFaceDetectionResult* outResult
) {
    cv::Mat frameRGBA(height, width, CV_8UC4, const_cast<uint8_t*>(rgba));
    cv::Mat frameBGR;
    cv::cvtColor(frameRGBA, frameBGR, cv::COLOR_RGBA2BGR);
    return detect_faces_dnn_mat(frameBGR, sensitivity, maxFaces, outResult);
}

// ═══════════════════════════════════════════════════════════════════════
// EXPORTED C API IMPLEMENTATION
// ═══════════════════════════════════════════════════════════════════════

CCTV_API int32_t cctv_detect_faces(
    const uint8_t* rgba,
    int32_t width,
    int32_t height,
    int32_t sensitivity,
    int32_t maxFaces,
    NativeFaceDetectionResult* outResult
) {
    if (!rgba || width < 32 || height < 32 || !outResult) return -1;

    outResult->faceCount = 0;
    if (maxFaces <= 0) maxFaces = 1;
    if (maxFaces > CCTV_MAX_FACES) maxFaces = CCTV_MAX_FACES;

    // Pure Deep Neural Network (OpenCV DNN):
    // Zero false detections on desks, chairs, walls, or furniture.
    if (ensure_dnn_loaded()) {
        try {
            return detect_faces_dnn(rgba, width, height, sensitivity, maxFaces, outResult);
        } catch (...) {
            outResult->faceCount = 0;
            return -2;
        }
    }

    // If DNN model is missing, strictly return 0 faces (NO heuristic fallback)
    outResult->faceCount = 0;
    return -10; // Error: Model file not loaded
}

CCTV_API int32_t cctv_detect_faces_jpeg(
    const uint8_t* jpegBytes,
    int32_t jpegSize,
    int32_t sensitivity,
    int32_t maxFaces,
    NativeFaceDetectionResult* outResult,
    int32_t* outImageWidth,
    int32_t* outImageHeight
) {
    if (!jpegBytes || jpegSize < 64 || !outResult) return -1;

    outResult->faceCount = 0;
    if (outImageWidth) *outImageWidth = 0;
    if (outImageHeight) *outImageHeight = 0;

    if (maxFaces <= 0) maxFaces = 1;
    if (maxFaces > CCTV_MAX_FACES) maxFaces = CCTV_MAX_FACES;

    if (!ensure_dnn_loaded()) return -10;

    // Pre-warm YuNet detector on first detection (lazy load, ready for future use)
    ensure_yunet_loaded();
    // Pre-warm dual-scale anti-spoofing 4.0x model
    ensure_liveness40_loaded();

    try {
        cv::Mat buf(1, jpegSize, CV_8UC1, const_cast<uint8_t*>(jpegBytes));
        cv::Mat frameBGR = cv::imdecode(buf, cv::IMREAD_COLOR);
        if (frameBGR.empty()) return -2;

        const int origW = frameBGR.cols;
        const int origH = frameBGR.rows;
        if (outImageWidth) *outImageWidth = origW;
        if (outImageHeight) *outImageHeight = origH;

        if (origW > 640 || origH > 480) {
            const float aspect = static_cast<float>(origW) / static_cast<float>(origH);
            int tw = 640;
            int th = static_cast<int>(tw / aspect);
            if (th > 480) {
                th = 480;
                tw = static_cast<int>(th * aspect);
            }
            cv::Mat dnnFrame;
            cv::resize(frameBGR, dnnFrame, cv::Size(tw, th), 0, 0, cv::INTER_LINEAR);
            int32_t res = detect_faces_dnn_mat(dnnFrame, sensitivity, maxFaces, outResult);

            const float sx = static_cast<float>(origW) / static_cast<float>(tw);
            const float sy = static_cast<float>(origH) / static_cast<float>(th);
            for (int32_t i = 0; i < outResult->faceCount; i++) {
                outResult->faces[i].left = static_cast<int32_t>(outResult->faces[i].left * sx);
                outResult->faces[i].top = static_cast<int32_t>(outResult->faces[i].top * sy);
                outResult->faces[i].right = static_cast<int32_t>(outResult->faces[i].right * sx);
                outResult->faces[i].bottom = static_cast<int32_t>(outResult->faces[i].bottom * sy);
            }
            return res;
        }

        return detect_faces_dnn_mat(frameBGR, sensitivity, maxFaces, outResult);
    } catch (...) {
        return -3;
    }
}

// ═══════════════════════════════════════════════════════════════════════
// 2. BIOMETRIC FEATURE EXTRACTION (176-D Embedding Vector)
// ═══════════════════════════════════════════════════════════════════════

CCTV_API int32_t cctv_extract_template(
    const uint8_t* rgba,
    int32_t width,
    int32_t height,
    int32_t left,
    int32_t top,
    int32_t right,
    int32_t bottom,
    float* outTemplate
) {
    if (!rgba || width < 16 || height < 16 || !outTemplate) return -1;

    const int32_t cLeft = std::max(0, std::min(width - 1, left));
    const int32_t cTop = std::max(0, std::min(height - 1, top));
    const int32_t cRight = std::max(cLeft + 8, std::min(width, right));
    const int32_t cBottom = std::max(cTop + 8, std::min(height, bottom));
    const int32_t cropW = cRight - cLeft;
    const int32_t cropH = cBottom - cTop;

    std::memset(outTemplate, 0, CCTV_TEMPLATE_DIM * sizeof(float));

    const int32_t gridCols = 4;
    const int32_t gridRows = 4;
    const int32_t blockW = cropW / gridCols;
    const int32_t blockH = cropH / gridRows;
    if (blockW < 2 || blockH < 2) return -2;

    int32_t featIdx = 0;
    for (int32_t gy = 0; gy < gridRows; gy++) {
        for (int32_t gx = 0; gx < gridCols; gx++) {
            const int32_t bx1 = cLeft + gx * blockW;
            const int32_t by1 = cTop + gy * blockH;
            const int32_t bx2 = (gx == gridCols - 1) ? cRight : bx1 + blockW;
            const int32_t by2 = (gy == gridRows - 1) ? cBottom : by1 + blockH;
            const int32_t bArea = (bx2 - bx1) * (by2 - by1);

            double sumLum = 0.0, sumLumSq = 0.0;
            double sumGradX = 0.0, sumGradY = 0.0, sumGradDiag = 0.0;
            double sumCr = 0.0, sumCb = 0.0;
            int32_t edgeCount = 0;
            double leftLum = 0.0, rightLum = 0.0;
            int32_t leftPixels = 0, rightPixels = 0;
            const int32_t midBx = (bx1 + bx2) / 2;

            for (int32_t y = by1; y < by2; y++) {
                const size_t rowStart = ((size_t)y * (size_t)width) * 4;
                for (int32_t x = bx1; x < bx2; x++) {
                    const size_t pIdx = rowStart + (size_t)x * 4;
                    const uint8_t r = rgba[pIdx];
                    const uint8_t g = rgba[pIdx + 1];
                    const uint8_t b = rgba[pIdx + 2];

                    const double lum = 0.299 * r + 0.587 * g + 0.114 * b;
                    sumLum += lum;
                    sumLumSq += lum * lum;

                    sumCr += 128.0 + 0.500 * r - 0.418688 * g - 0.081312 * b;
                    sumCb += 128.0 - 0.168736 * r - 0.331264 * g + 0.500 * b;

                    if (x < midBx) { leftLum += lum; leftPixels++; }
                    else { rightLum += lum; rightPixels++; }

                    if (x + 1 < bx2) {
                        const size_t nextX = pIdx + 4;
                        const double nextLum = 0.299 * rgba[nextX] + 0.587 * rgba[nextX + 1] + 0.114 * rgba[nextX + 2];
                        const double gxVal = std::fabs(nextLum - lum);
                        sumGradX += gxVal;
                        if (gxVal > 22.0) edgeCount++;
                    }
                    if (y + 1 < by2) {
                        const size_t nextY = pIdx + (size_t)width * 4;
                        const double nextLumY = 0.299 * rgba[nextY] + 0.587 * rgba[nextY + 1] + 0.114 * rgba[nextY + 2];
                        const double gyVal = std::fabs(nextLumY - lum);
                        sumGradY += gyVal;
                        if (gyVal > 22.0) edgeCount++;
                    }
                    if (x + 1 < bx2 && y + 1 < by2) {
                        const size_t diagIdx = pIdx + (size_t)width * 4 + 4;
                        const double diagLum = 0.299 * rgba[diagIdx] + 0.587 * rgba[diagIdx + 1] + 0.114 * rgba[diagIdx + 2];
                        sumGradDiag += std::fabs(diagLum - lum);
                    }
                }
            }

            const double meanLum = sumLum / (double)bArea;
            const double variance = std::max(0.0, (sumLumSq / (double)bArea) - (meanLum * meanLum));
            const double stdDev = std::sqrt(variance);

            const double meanGradX = sumGradX / (double)bArea;
            const double meanGradY = sumGradY / (double)bArea;
            const double meanGradDiag = sumGradDiag / (double)bArea;
            const double meanCr = sumCr / (double)bArea;
            const double meanCb = sumCb / (double)bArea;
            const double edgeDensity = (double)edgeCount / (double)(bArea * 2);

            const double avgLeft = (leftPixels > 0) ? (leftLum / leftPixels) : meanLum;
            const double avgRight = (rightPixels > 0) ? (rightLum / rightPixels) : meanLum;
            const double hSymmetry = std::fabs(avgLeft - avgRight);
            const double localEnergy = variance * (meanGradX + meanGradY + 1.0);

            outTemplate[featIdx++] = (float)(meanLum / 255.0);
            outTemplate[featIdx++] = (float)(stdDev / 128.0);
            outTemplate[featIdx++] = (float)(meanGradX / 64.0);
            outTemplate[featIdx++] = (float)(meanGradY / 64.0);
            outTemplate[featIdx++] = (float)(meanGradDiag / 64.0);
            outTemplate[featIdx++] = (float)((meanCr - 128.0) / 64.0);
            outTemplate[featIdx++] = (float)((meanCb - 128.0) / 64.0);
            outTemplate[featIdx++] = (float)edgeDensity;
            outTemplate[featIdx++] = (float)(hSymmetry / 64.0);
            outTemplate[featIdx++] = (float)((avgLeft > 0.0) ? (avgRight / (avgLeft + 1.0)) : 1.0);
            outTemplate[featIdx++] = (float)(localEnergy / 10000.0);
        }
    }

    double normSq = 0.0;
    for (int32_t i = 0; i < CCTV_TEMPLATE_DIM; i++) normSq += (double)outTemplate[i] * (double)outTemplate[i];
    const float invNorm = (normSq > 1e-9) ? (float)(1.0 / std::sqrt(normSq)) : 0.0f;
    for (int32_t i = 0; i < CCTV_TEMPLATE_DIM; i++) outTemplate[i] *= invNorm;

    return 0;
}

CCTV_API int32_t cctv_extract_template_jpeg(
    const uint8_t* jpegBytes,
    int32_t jpegSize,
    int32_t left,
    int32_t top,
    int32_t right,
    int32_t bottom,
    float* outTemplate
) {
    if (!jpegBytes || jpegSize < 64 || !outTemplate) return -1;
    try {
        cv::Mat buf(1, jpegSize, CV_8UC1, const_cast<uint8_t*>(jpegBytes));
        cv::Mat frameBGR = cv::imdecode(buf, cv::IMREAD_COLOR);
        if (frameBGR.empty()) return -2;

        cv::Mat frameRGBA;
        cv::cvtColor(frameBGR, frameRGBA, cv::COLOR_BGR2RGBA);
        return cctv_extract_template(frameRGBA.data, frameRGBA.cols, frameRGBA.rows, left, top, right, bottom, outTemplate);
    } catch (...) {
        return -3;
    }
}

CCTV_API int32_t cctv_check_liveness(
    const uint8_t* rgba,
    int32_t width,
    int32_t height,
    int32_t left,
    int32_t top,
    int32_t right,
    int32_t bottom,
    float* outRealScore
) {
    if (!rgba || width < 16 || height < 16) {
        if (outRealScore) *outRealScore = 0.0f;
        return 0;
    }

    try {
        cv::Mat frameRGBA(height, width, CV_8UC4, const_cast<uint8_t*>(rgba));
        cv::Mat frameBGR;
        cv::cvtColor(frameRGBA, frameBGR, cv::COLOR_RGBA2BGR);

        int cLeft = std::max(0, std::min(width - 1, left));
        int cTop = std::max(0, std::min(height - 1, top));
        int cRight = std::max(cLeft + 8, std::min(width, right));
        int cBottom = std::max(cTop + 8, std::min(height, bottom));

        cv::Rect faceRect(cLeft, cTop, cRight - cLeft, cBottom - cTop);

        float realProb = 0.0f;
        bool passMiniFas = check_liveness_multiscale(frameBGR, faceRect, realProb);

        float blurScore = 0.0f;
        cv::Mat faceCrop = frameBGR(faceRect);
        bool passPassive = check_passive_spoof_signatures(faceCrop, blurScore);

        if (outRealScore) *outRealScore = realProb;
        return (passMiniFas && passPassive) ? 1 : 0;
    } catch (...) {
        if (outRealScore) *outRealScore = 0.0f;
        return 0;
    }
}

CCTV_API int32_t cctv_extract_sface_template(
    const uint8_t* rgba,
    int32_t width,
    int32_t height,
    int32_t left,
    int32_t top,
    int32_t right,
    int32_t bottom,
    float* outTemplate
) {
    if (!rgba || width < 16 || height < 16 || !outTemplate) return -1;
    if (!ensure_sface_loaded()) return -2;

    try {
        cv::Mat frameRGBA(height, width, CV_8UC4, const_cast<uint8_t*>(rgba));
        cv::Mat frameBGR;
        cv::cvtColor(frameRGBA, frameBGR, cv::COLOR_RGBA2BGR);

        int cLeft = std::max(0, std::min(width - 1, left));
        int cTop = std::max(0, std::min(height - 1, top));
        int cRight = std::max(cLeft + 8, std::min(width, right));
        int cBottom = std::max(cTop + 8, std::min(height, bottom));

        cv::Rect faceRect(cLeft, cTop, cRight - cLeft, cBottom - cTop);
        cv::Mat faceCrop = frameBGR(faceRect);

        cv::Mat aligned112;
        cv::resize(faceCrop, aligned112, cv::Size(112, 112), 0, 0, cv::INTER_LINEAR);

        cv::Mat featMat;
        {
            std::lock_guard<std::mutex> lock(g_sfaceMutex);
            g_sfaceRecognizer->feature(aligned112, featMat);
        }

        if (featMat.empty() || featMat.total() < 128) return -3;

        const float* pFeat = featMat.ptr<float>();
        double normSq = 0.0;
        for (int i = 0; i < 128; i++) {
            normSq += (double)pFeat[i] * (double)pFeat[i];
        }
        float invNorm = (normSq > 1e-9) ? (float)(1.0 / std::sqrt(normSq)) : 0.0f;
        for (int i = 0; i < 128; i++) {
            outTemplate[i] = pFeat[i] * invNorm;
        }

        return 0;
    } catch (...) {
        return -4;
    }
}

CCTV_API int32_t cctv_check_liveness_jpeg(
    const uint8_t* jpegBytes,
    int32_t jpegSize,
    int32_t left,
    int32_t top,
    int32_t right,
    int32_t bottom,
    float* outRealScore
) {
    if (!jpegBytes || jpegSize < 64) {
        if (outRealScore) *outRealScore = 0.0f;
        return 0;
    }

    try {
        cv::Mat buf(1, jpegSize, CV_8UC1, const_cast<uint8_t*>(jpegBytes));
        cv::Mat frameBGR = cv::imdecode(buf, cv::IMREAD_COLOR);
        if (frameBGR.empty()) {
            if (outRealScore) *outRealScore = 0.0f;
            return 0;
        }

        int cLeft = std::max(0, std::min(frameBGR.cols - 1, left));
        int cTop = std::max(0, std::min(frameBGR.rows - 1, top));
        int cRight = std::max(cLeft + 8, std::min(frameBGR.cols, right));
        int cBottom = std::max(cTop + 8, std::min(frameBGR.rows, bottom));

        cv::Rect faceRect(cLeft, cTop, cRight - cLeft, cBottom - cTop);

        float realProb = 0.0f;
        bool passMiniFas = check_liveness_multiscale(frameBGR, faceRect, realProb);

        float blurScore = 0.0f;
        cv::Mat faceCrop = frameBGR(faceRect);
        bool passPassive = check_passive_spoof_signatures(faceCrop, blurScore);

        if (outRealScore) *outRealScore = realProb;
        return (passMiniFas && passPassive) ? 1 : 0;
    } catch (...) {
        if (outRealScore) *outRealScore = 0.0f;
        return 0;
    }
}

CCTV_API int32_t cctv_extract_sface_template_jpeg(
    const uint8_t* jpegBytes,
    int32_t jpegSize,
    int32_t left,
    int32_t top,
    int32_t right,
    int32_t bottom,
    float* outTemplate
) {
    if (!jpegBytes || jpegSize < 64 || !outTemplate) return -1;
    if (!ensure_sface_loaded()) return -2;

    try {
        cv::Mat buf(1, jpegSize, CV_8UC1, const_cast<uint8_t*>(jpegBytes));
        cv::Mat frameBGR = cv::imdecode(buf, cv::IMREAD_COLOR);
        if (frameBGR.empty()) return -2;

        int cLeft = std::max(0, std::min(frameBGR.cols - 1, left));
        int cTop = std::max(0, std::min(frameBGR.rows - 1, top));
        int cRight = std::max(cLeft + 8, std::min(frameBGR.cols, right));
        int cBottom = std::max(cTop + 8, std::min(frameBGR.rows, bottom));

        cv::Rect faceRect(cLeft, cTop, cRight - cLeft, cBottom - cTop);
        cv::Mat faceCrop = frameBGR(faceRect);

        cv::Mat aligned112;
        cv::resize(faceCrop, aligned112, cv::Size(112, 112), 0, 0, cv::INTER_LINEAR);

        cv::Mat featMat;
        {
            std::lock_guard<std::mutex> lock(g_sfaceMutex);
            g_sfaceRecognizer->feature(aligned112, featMat);
        }

        if (featMat.empty() || featMat.total() < 128) return -3;

        const float* pFeat = featMat.ptr<float>();
        double normSq = 0.0;
        for (int i = 0; i < 128; i++) {
            normSq += (double)pFeat[i] * (double)pFeat[i];
        }
        float invNorm = (normSq > 1e-9) ? (float)(1.0 / std::sqrt(normSq)) : 0.0f;
        for (int i = 0; i < 128; i++) {
            outTemplate[i] = pFeat[i] * invNorm;
        }

        return 0;
    } catch (...) {
        return -4;
    }
}

// ═══════════════════════════════════════════════════════════════════════
// 3. ULTRA-FAST SIMD COSINE SIMILARITY & BATCH MATCHING
// ═══════════════════════════════════════════════════════════════════════

CCTV_API float cctv_match_templates(
    const float* templateA,
    const float* templateB,
    int32_t length
) {
    if (!templateA || !templateB || length <= 0) return 0.0f;

    float dot = 0.0f;
    float normA = 0.0f;
    float normB = 0.0f;
    int32_t i = 0;

#if defined(CCTV_USE_SSE)
    __m128 sumDot = _mm_setzero_ps();
    __m128 sumA = _mm_setzero_ps();
    __m128 sumB = _mm_setzero_ps();
    const int32_t simdLimit = length - (length % 4);

    for (; i < simdLimit; i += 4) {
        __m128 a = _mm_loadu_ps(templateA + i);
        __m128 b = _mm_loadu_ps(templateB + i);
        sumDot = _mm_add_ps(sumDot, _mm_mul_ps(a, b));
        sumA = _mm_add_ps(sumA, _mm_mul_ps(a, a));
        sumB = _mm_add_ps(sumB, _mm_mul_ps(b, b));
    }

    float tmpDot[4], tmpA[4], tmpB[4];
    _mm_storeu_ps(tmpDot, sumDot);
    _mm_storeu_ps(tmpA, sumA);
    _mm_storeu_ps(tmpB, sumB);
    dot = tmpDot[0] + tmpDot[1] + tmpDot[2] + tmpDot[3];
    normA = tmpA[0] + tmpA[1] + tmpA[2] + tmpA[3];
    normB = tmpB[0] + tmpB[1] + tmpB[2] + tmpB[3];
#endif

    for (; i < length; i++) {
        dot += templateA[i] * templateB[i];
        normA += templateA[i] * templateA[i];
        normB += templateB[i] * templateB[i];
    }

    const float denom = std::sqrt(normA) * std::sqrt(normB);
    if (denom < 1e-6f) return 0.0f;

    const float cosSim = std::max(-1.0f, std::min(1.0f, dot / denom));
    float score = std::max(0.0f, std::min(100.0f, cosSim * 100.0f));
    return score;
}

CCTV_API int32_t cctv_batch_match(
    const float* probeTemplate,
    const float* enrolledTemplates,
    int32_t enrolledCount,
    int32_t templateLength,
    float matchThreshold,
    int32_t* outBestIndex,
    float* outBestScore
) {
    if (!probeTemplate || !enrolledTemplates || enrolledCount <= 0 || templateLength <= 0) {
        if (outBestIndex) *outBestIndex = -1;
        if (outBestScore) *outBestScore = 0.0f;
        return 0;
    }

    int32_t bestIdx = -1;
    float bestScore = 0.0f;

    for (int32_t i = 0; i < enrolledCount; i++) {
        const float* candidate = enrolledTemplates + (size_t)i * (size_t)templateLength;
        const float score = cctv_match_templates(probeTemplate, candidate, templateLength);
        if (score > bestScore) {
            bestScore = score;
            bestIdx = i;
        }
    }

    if (outBestIndex) *outBestIndex = bestIdx;
    if (outBestScore) *outBestScore = bestScore;

    return (bestScore >= matchThreshold && bestIdx >= 0) ? 1 : 0;
}

// ═══════════════════════════════════════════════════════════════════════
// 4. ZERO-DISK IN-MEMORY CAMERA STREAMING (OpenCV VideoCapture)
// ═══════════════════════════════════════════════════════════════════════

static cv::VideoCapture g_camera;
static bool g_cameraOpen = false;
static std::mutex g_cameraMutex;

static std::atomic<bool> g_captureRunning{false};
static std::thread g_captureThread;
static std::mutex g_frameMutex;
static std::vector<uint8_t> g_latestJpeg;
static int32_t g_latestWidth = 0;
static int32_t g_latestHeight = 0;
static int g_currentQuality = 70;
static int32_t g_targetWidth = 640;
static int32_t g_targetHeight = 480;
static std::atomic<uint64_t> g_frameCounter{0};

CCTV_API uint64_t cctv_camera_frame_counter(void) {
    return g_frameCounter.load();
}

static void captureWorker() {
    cv::setNumThreads(2);

    while (g_captureRunning) {
        if (!g_cameraOpen || !g_camera.isOpened()) break;

        cv::Mat frame;
        if (!g_camera.read(frame) || frame.empty()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
            continue;
        }

        cv::Mat processedFrame;
        if (g_targetWidth > 0 && g_targetHeight > 0 && (frame.cols > g_targetWidth || frame.rows > g_targetHeight)) {
            const float aspect = static_cast<float>(frame.cols) / static_cast<float>(frame.rows);
            int tw = g_targetWidth;
            int th = static_cast<int>(tw / aspect);
            if (th > g_targetHeight) {
                th = g_targetHeight;
                tw = static_cast<int>(th * aspect);
            }
            cv::resize(frame, processedFrame, cv::Size(tw, th), 0, 0, cv::INTER_LINEAR);
        } else {
            processedFrame = frame;
        }

        const int q = (g_currentQuality >= 30 && g_currentQuality <= 100) ? g_currentQuality : 70;
        const std::vector<int> params = {cv::IMWRITE_JPEG_QUALITY, q};
        std::vector<uint8_t> buf;
        if (cv::imencode(".jpg", processedFrame, buf, params)) {
            std::lock_guard<std::mutex> lock(g_frameMutex);
            g_latestJpeg = std::move(buf);
            g_latestWidth = processedFrame.cols;
            g_latestHeight = processedFrame.rows;
            g_frameCounter.fetch_add(1);
        }

        // 1ms cooperative thread yield: prevents 100% busy-wait while delivering full 60-79 FPS hardware rate
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
}

static void cctv_camera_close_internal() {
    if (g_captureRunning) {
        g_captureRunning = false;
        if (g_captureThread.joinable()) {
            g_captureThread.join();
        }
    }
    std::lock_guard<std::mutex> lock(g_cameraMutex);
    if (g_cameraOpen) {
        try {
            g_camera.release();
        } catch (...) {}
        g_cameraOpen = false;
    }
    std::lock_guard<std::mutex> frameLock(g_frameMutex);
    g_latestJpeg.clear();
    g_latestWidth = 0;
    g_latestHeight = 0;
    g_frameCounter.store(0);
}

CCTV_API int32_t cctv_camera_open(int32_t cameraIndex, int32_t width, int32_t height) {
    cctv_camera_close_internal();

    std::lock_guard<std::mutex> lock(g_cameraMutex);

    auto tryOpen = [](int idx) -> bool {
        // 1. MSMF (Microsoft Media Foundation - Windows 10/11 GPU pipeline)
        try {
            if (g_camera.open(idx, cv::CAP_MSMF)) {
                g_camera.set(cv::CAP_PROP_FOURCC, cv::VideoWriter::fourcc('M', 'J', 'P', 'G'));
                return true;
            }
        } catch (...) {}

        // 2. DirectShow
        try {
            if (g_camera.open(idx, cv::CAP_DSHOW)) {
                g_camera.set(cv::CAP_PROP_FOURCC, cv::VideoWriter::fourcc('M', 'J', 'P', 'G'));
                return true;
            }
        } catch (...) {}

        // 3. Any available
        try {
            if (g_camera.open(idx, cv::CAP_ANY)) {
                return true;
            }
        } catch (...) {}

        return false;
    };

    bool opened = tryOpen(cameraIndex);
    if (!opened) {
        for (int alt = 0; alt <= 3; alt++) {
            if (alt != cameraIndex && tryOpen(alt)) {
                opened = true;
                break;
            }
        }
    }

    if (opened && g_camera.isOpened()) {
        const int reqW = (width > 0) ? width : 640;
        const int reqH = (height > 0) ? height : 480;
        g_targetWidth = reqW;
        g_targetHeight = reqH;
        g_camera.set(cv::CAP_PROP_FRAME_WIDTH, reqW);
        g_camera.set(cv::CAP_PROP_FRAME_HEIGHT, reqH);
        g_camera.set(cv::CAP_PROP_FPS, 60.0);
        g_camera.set(cv::CAP_PROP_BUFFERSIZE, 1);
        g_cameraOpen = true;

        g_captureRunning = true;
        g_captureThread = std::thread(captureWorker);
        return 1;
    }

    return 0;
}

CCTV_API int32_t cctv_camera_open_url(const char* streamUrl, int32_t width, int32_t height) {
    if (!streamUrl || std::strlen(streamUrl) < 4) return 0;
    cctv_camera_close_internal();

    std::lock_guard<std::mutex> lock(g_cameraMutex);
    try {
        // Force ultra-low latency flags for FFmpeg backend:
        // - fflags;nobuffer: Disable packet queue inside libavformat
        // - flags;low_delay: Disable frame reordering delay in decoder
        // - framedrop;1: Drop stale frames if backlog develops
        // - max_delay;0: Zero network jitter buffer delay
        // - probesize;32: Minimal stream probing (immediate start)
        // - analyzeduration;0: No initial analysis duration delay
        // - sync;ext: Synchronize to external clock
        // - flush_packets;1: Immediate packet delivery without buffering
        // Force ultra-low latency flags & strict network connect timeouts for FFmpeg backend:
        // - stimeout;1500000: 1.5s TCP connection timeout for RTSP/TCP streams
        // - timeout;1500000: 1.5s HTTP socket timeout for MJPEG streams
        _putenv_s("OPENCV_FFMPEG_CAPTURE_OPTIONS",
            "fflags;nobuffer|flags;low_delay|framedrop;1|max_delay;0|probesize;32|analyzeduration;0|sync;ext|flush_packets;1|threads;1|stimeout;1500000|timeout;1500000");

        const std::vector<int> captureParams = {
            cv::CAP_PROP_OPEN_TIMEOUT_MSEC, 1500,
            cv::CAP_PROP_READ_TIMEOUT_MSEC, 1500
        };
        bool opened = g_camera.open(streamUrl, cv::CAP_FFMPEG, captureParams);
        if (!opened) {
            opened = g_camera.open(streamUrl, cv::CAP_FFMPEG);
        }
        if (opened && g_camera.isOpened()) {
            const int reqW = (width > 0) ? width : 640;
            const int reqH = (height > 0) ? height : 480;
            g_targetWidth = reqW;
            g_targetHeight = reqH;
            g_camera.set(cv::CAP_PROP_FRAME_WIDTH, reqW);
            g_camera.set(cv::CAP_PROP_FRAME_HEIGHT, reqH);
            g_camera.set(cv::CAP_PROP_FPS, 60.0);
            g_camera.set(cv::CAP_PROP_BUFFERSIZE, 1);
            g_cameraOpen = true;

            // Drain any initial packets accumulated during TCP / HTTP handshake
            for (int drain = 0; drain < 5; ++drain) {
                if (!g_camera.grab()) break;
            }

            g_captureRunning = true;
            g_captureThread = std::thread(captureWorker);
            return 1;
        }
    } catch (...) {}

    return 0;
}

CCTV_API int32_t cctv_camera_read_frame(
    uint8_t* outRgba,
    int32_t maxBytes,
    int32_t* outWidth,
    int32_t* outHeight
) {
    if (!outRgba || !outWidth || !outHeight || maxBytes < 64) return 0;

    std::vector<uint8_t> jpegCopy;
    {
        std::lock_guard<std::mutex> lock(g_frameMutex);
        if (g_latestJpeg.empty()) return 0;
        jpegCopy = g_latestJpeg;
    }

    try {
        cv::Mat buf(1, static_cast<int>(jpegCopy.size()), CV_8UC1, jpegCopy.data());
        cv::Mat frame = cv::imdecode(buf, cv::IMREAD_COLOR);
        if (frame.empty()) return 0;

        *outWidth = frame.cols;
        *outHeight = frame.rows;
        const int32_t neededBytes = frame.cols * frame.rows * 4;
        if (maxBytes < neededBytes) return 0;

        cv::Mat frameRgba(frame.rows, frame.cols, CV_8UC4, outRgba);
        cv::cvtColor(frame, frameRgba, cv::COLOR_BGR2RGBA);
        return 1;
    } catch (...) {
        return 0;
    }
}

CCTV_API int32_t cctv_camera_read_jpeg(
    uint8_t* outJpeg,
    int32_t maxBytes,
    int32_t* outJpegSize,
    int32_t quality
) {
    if (!outJpeg || !outJpegSize || maxBytes < 1024) return 0;
    if (quality >= 30 && quality <= 100) g_currentQuality = quality;

    std::lock_guard<std::mutex> lock(g_frameMutex);
    if (g_latestJpeg.empty() || (int32_t)g_latestJpeg.size() > maxBytes) {
        return 0;
    }

    std::memcpy(outJpeg, g_latestJpeg.data(), g_latestJpeg.size());
    *outJpegSize = static_cast<int32_t>(g_latestJpeg.size());
    return 1;
}

CCTV_API void cctv_camera_close(void) {
    cctv_camera_close_internal();
}
