# Carlyle Auto (AI Tuner) 🏎️🔧

An advanced AI automotive assistant, OBD-II telemetry scanner, dyno modeling engine, and generative modification visualizer built with Flutter.

---

## ✨ Features

- **Multimodal AI Diagnostics**: Powered by Google Gemini to analyze mechanic descriptions, OBD-II error codes, dashboard warning lights, and audio engine recordings.
- **Live OBD-II Bluetooth Telemetry**: Real-time ELM327 Bluetooth streaming for RPM, boost pressure, coolant temperature, fuel trims, and throttle position.
- **Diagnostic Trouble Code (DTC) Clearing**: Detailed code analysis with repair difficulty ratings, estimated parts costs, and step-by-step DIY repair guides.
- **Virtual Dyno Simulation**: Dynamically calculates estimated horsepower and torque curves based on engine displacement, aspiration, and installed modifications.
- **Generative Mod Studio**: Visualizes cosmetic and performance styling modifications (suspension drops, wheel fitment, aero kits, wraps) on vehicle chassis.

---

## 🛠️ Architecture

- **Frontend**: Flutter (Mobile & Desktop)
- **AI Engine**: Google Gemini API via multimodal prompt pipelines
- **Hardware Integration**: `flutter_classic_bluetooth` for ELM327 OBD-II protocol communication
- **State Management**: Provider

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (v3.24+)
- OBD-II Bluetooth Adapter (ELM327 compatible)

### Development
```bash
flutter pub get
flutter run
```

---

## 📄 License

Proprietary / All Rights Reserved. Built by Archer Woods.
