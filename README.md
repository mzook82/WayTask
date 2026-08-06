# WayTask

> **Your intelligent shopping companion.**

*Shopping, powered by location and AI.*

WayTask is an AI-powered location-aware shopping companion for iOS.

Instead of simply managing shopping lists, WayTask proactively helps users discover nearby products, stores, restaurants, and services through intelligent shopping lists, real-time location, interactive maps, camera recognition, and AI-powered recommendations.

---

# 🚀 Vision

Shopping should be effortless.

WayTask transforms shopping from a passive task into a proactive experience.

Rather than expecting users to remember where and when to shop, WayTask remembers for them—delivering the right recommendation at the right place and the right time.

---

# ❓ Why WayTask?

Traditional shopping list apps stop after helping users write a list.

WayTask goes much further.

It understands:

- 📍 Where you are
- 🛍️ What you need
- ❤️ What you like
- 🤖 What AI can recommend
- 🗺️ Which nearby places are relevant

The result is a smarter, faster, and more personalized shopping experience.

---

# ✨ Core Features

## 📝 Smart Shopping Lists

- Multiple shopping lists
- Intelligent product suggestions
- Categories
- Favorites
- Quick Add
- Completion tracking

---

## 🗺️ Interactive Map

- Nearby stores
- Product locations
- Store recommendations
- Restaurant suggestions
- Beautiful Apple Maps experience
- Smart filtering

---

## 📷 Camera

- Live camera preview
- Photo capture
- Import from Photos
- Barcode scanning
- Open Food Facts barcode lookup
- Secure-proxy AI product recognition (disabled until approved staging Auth)
- AI Vision mode
- Manual fallback when recognition is unavailable
- User review before saving recognized products

---

## 🔔 Smart Notifications

Receive notifications when:

- You're close to a store selling products from your shopping list.
- A nearby place matches your interests.
- A new store opens nearby.
- A recommended product becomes relevant.

Current notification foundation includes:

- Saved-store priority
- Geofence monitoring
- Smart Nearby Detection
- Product names from confirmed shopping-list items
- Notification tap flow into Map / Trip Map Mode

---

## 🌟 Discover

Discover places based on your interests.

Examples:

- Coffee shops
- Restaurants
- Electronics
- Fashion
- Grocery stores
- New businesses nearby

---

## 🤖 AI Assistant

Current AI foundation:

- Protocol-based secure AI recognition authority
- Authenticated, rate-limited staging Edge Function contract for Gemini
- No Gemini credential or direct Gemini endpoint in iOS
- Open Food Facts with explicit secure-AI enrichment for unknown barcodes
- AI Vision mode for product photos
- Structured JSON product recognition
- Search keywords support for future matching
- Manual fallback when confidence is low or AI is unavailable
- Client and server kill switches OFF by default

Future AI capabilities include:

### 🛒 Shopping Assistant

- Smart shopping suggestions
- Frequently purchased items
- Personalized recommendations

### 🍳 Recipe Assistant

- Suggest recipes
- Complete missing ingredients
- Meal planning

### 👕 Fashion Assistant

- Clothing recommendations
- Matching outfits
- Style suggestions

### 🎁 Gift Assistant

- Birthday reminders
- Gift ideas
- Calendar integration
- Personalized suggestions

### 🧠 Predictive Shopping

- Predict forgotten items
- Learn shopping habits
- Seasonal recommendations

---

# 🛠 Technology

WayTask is built using native Apple technologies.

- SwiftUI
- SwiftData
- MapKit
- CoreLocation
- AVFoundation
- Vision Framework
- PhotosUI
- UserNotifications
- Supabase Edge Functions (staging secure-AI boundary)
- Git
- GitHub

---

# 🏗 Architecture

The project follows a modular architecture.

```
SwiftUI Views
        │
        ▼
ViewModels
        │
        ▼
Services
        │
        ▼
Models
        │
        ▼
System Frameworks
(MapKit • Vision • CoreLocation • AVFoundation)
```

Business logic is separated from UI to keep the project scalable and maintainable.

---

# 📈 Development Status

Current Progress

## ✅ Completed

- Product List redesign
- Shared Design System
- Camera Foundation
- Camera UX improvements
- Barcode scanning
- Open Food Facts product lookup
- Secure Gemini proxy/client boundary
- AI Vision mode
- Built-artifact credential scanner and bundled-secret removal
- AI review flow
- AI search keywords support
- Interactive Map Foundation
- Store Bottom Sheet
- Store Search Service
- Buying Options
- Store Ranking
- Shopping Trip Planner
- Shopping Mode
- Smart Nearby Detection
- Geofence Notification Foundation
- GitHub Repository
- Project Documentation

---

## 🚧 In Progress

- Sprint 19.2 AI persistence and learning foundation
- Persisting AI search keywords
- AI result editing polish
- Staging Auth token integration and proxy deployment validation

---

## ⏳ Planned

- AI Learning Loop
- AI-powered recommendations
- Price comparison
- Online shopping providers
- Indoor navigation
- AI Shopping Assistant
- Recipe Assistant
- Gift Assistant
- Outfit Recommendations

---

# 🛣 Roadmap

## Version 1.0

- Smart Shopping Lists
- Interactive Map
- Camera
- Nearby Store Discovery
- Product Recognition
- Smart Notifications
- Barcode scanning
- Open Food Facts lookup
- Secure-proxy AI enrichment after approved staging configuration
- Shopping Mode
- Shopping Trip Planner

---

## Version 2.0

- AI Shopping Assistant
- AI Recipe Assistant
- AI Gift Assistant
- AI Fashion Assistant
- AI Learning from accepted, edited, and rejected suggestions
- Persisted AI search keywords
- Personalized Buying Options

---

## Version 3.0

- Apple Intelligence Integration
- Indoor Navigation
- AR Navigation
- Price Comparison
- Shared Shopping Lists

---

# 📚 Documentation

Additional documentation is available in the `docs` directory.

| Document | Description |
|----------|-------------|
| INDEX | Documentation entry point |
| PRD | Product Requirements Document |
| ROADMAP | Product roadmap |
| ARCHITECTURE | Technical architecture |
| AI_ROADMAP | AI vision and future plans |
| AI_PRODUCT_RECOGNITION | Secure AI and product recognition flow |
| DEVELOPMENT_GUIDE | Development workflow |

---

# Recent Progress

## WT-032A.1 security remediation

- Removed the direct Gemini iOS client, key loader, `Info.plist` key expansion,
  and `Secrets.plist` Copy Bundle Resources membership.
- Added a signed-in, rate-limited, fixed-schema staging proxy contract; all
  cloud/account/sync/secure-AI features remain OFF by default.
- Added Debug/Release built-product and tracked-source secret scanners.
- See `docs/WT-032A/17_GEMINI_CREDENTIAL_REMEDIATION.md` for proof, prerequisites,
  privacy/cost controls, and the required Google Cloud rotation checklist.

## Sprint 19.1

Historical state (superseded by WT-032A.1):

- Gemini Vision is the active AI product recognition provider.
- `Secrets.plist` is the primary API key source through `SecretsManager`.
- AI Vision mode calls Gemini for product-photo recognition.
- Barcode mode uses Open Food Facts first, then Gemini fallback when lookup fails.
- Recognized AI products require user review before saving.
- Manual product entry remains available when Gemini is unavailable, fails, or returns low confidence.
- Gemini returns product name, brand, category, confidence, description, and search keywords.
- Search keywords are available on `ProductCandidate` for future matching.
- Notifications now use confirmed shopping-list product names rather than keyword-only labels.

Historical planned work at that point:

- Persist AI search keywords to SwiftData safely.
- Add migration support for keyword storage.
- Add tests for `SecretsManager` and Gemini response parsing.
- Improve edit-before-save behavior for AI suggestions.
- Start AI learning from accepted, edited, and rejected suggestions.
| SPRINTS | Sprint history |
| CHANGELOG | Version history |
| UI_IDEAS | UI inspiration and future concepts |

---

# 🔄 Development Workflow

Every feature follows the same workflow.

```
Planning
    ↓
Documentation
    ↓
Implementation
    ↓
Build
    ↓
Quality Assurance
    ↓
Git Commit
    ↓
Git Push
```

---

# 🌍 Long-Term Vision

WayTask is evolving from a shopping list application into an AI-powered shopping companion.

The long-term vision is to combine:

- Artificial Intelligence
- Location Intelligence
- Computer Vision
- Personalized Recommendations
- Navigation
- Smart Automation

to make shopping simpler, faster, and more enjoyable.

---

# 📄 License

Private project.

Copyright © 2026 WayTask.

All rights reserved.
