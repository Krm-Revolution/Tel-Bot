# 🎮 Telegram Casino Bot with Opera AI

A feature-rich Telegram bot that combines Opera AI chat capabilities with a complete casino gaming system, economy, rankings, and admin controls.

![Version](https://img.shields.io/badge/version-2.0.0-blue)
![Python](https://img.shields.io/badge/python-3.8+-green)
![License](https://img.shields.io/badge/license-MIT-orange)
![Platform](https://img.shields.io/badge/platform-Termux%20%7C%20Linux-lightgrey)

## 📋 Table of Contents
- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Usage](#-usage)
- [Commands](#-commands)
- [Admin System](#-admin-system)
- [Database Structure](#-database-structure)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)

## ✨ Features

### 🤖 AI Capabilities
- **Opera Aria Integration** - Full AI chat functionality
- **Image Analysis** - Send images for AI analysis
- **Conversation Memory** - Maintains context across messages
- **Auto Token Refresh** - Handles API authentication automatically

### 🎰 Casino Games
| Game | Description | Multiplier |
|------|-------------|------------|
| 🎰 Slots | Classic 3-reel slot machine | Up to 10x |
| 🎲 Dice | Guess the dice roll (1-6) | 6x |
| 🪙 Coin Flip | Heads or tails | 2x |
| 🎡 Roulette | Numbers, colors, even/odd | Up to 35x |
| 💎 Jackpot | Progressive jackpot system | Variable |
| 📈 Crash | Cash out before crash | Variable |

### 💰 Economy System
- Starting balance: **1,000 coins**
- Daily bonus: **500 coins**
- Win/Loss tracking
- Complete game history
- Progressive jackpot pool
- Balance persistence

### 🏆 Rankings & Statistics
- Top 10 players leaderboard
- Individual player statistics
- Total registered users count
- Win/Loss ratios
- Games played counter

### 👑 Admin Controls
- Give coins to specific users
- Reset user statistics
- Broadcast messages to all users
- Add coins to all users globally
- View all registered users
- Reset jackpot manually

## 📦 Prerequisites

### For Termux (Android)
- Android 5.0 or higher
- Termux installed from [F-Droid](https://f-droid.org/en/packages/com.termux/)
- Stable internet connection
- At least 500MB free storage

### For Linux
- Python 3.8 or higher
- pip3 package manager
- Git
- Internet connection

## 🚀 Installation

### Step 1: Clone or Create Script

#### Option A: Using Git (Recommended)
```bash
# Clone the repository
git clone https://github.com/yourusername/telegram-casino-bot.git
cd telegram-casino-bot

# Make script executable
chmod +x telbot.sh
