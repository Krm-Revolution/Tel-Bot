#!/data/data/com.termux/files/usr/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${CYAN}[✓]${NC} $1"
}

check_dependencies() {
    print_message "Checking dependencies..."
    
    if ! command -v python3 &> /dev/null; then
        print_error "Python3 not found. Installing..."
        pkg install python -y
    fi
    
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        print_error "pip not found. Installing..."
        pkg install python-pip -y
    fi
    
    if ! command -v git &> /dev/null; then
        print_error "Git not found. Installing..."
        pkg install git -y
    fi
    
    print_success "Dependencies checked"
}

create_requirements_file() {
    print_message "Creating requirements.txt..."
    
    cat > requirements.txt << 'EOF'
aiohttp>=3.8.0
python-telegram-bot>=20.0
Pillow>=9.0.0
requests>=2.28.0
EOF
    
    print_success "requirements.txt created"
    print_warning "Please run: pip install -r requirements.txt"
}

create_bot_script() {
    print_message "Creating Telegram bot script..."
    
    cat > bot.py << 'EOF'
import asyncio
import json
import time
import random
import re
import os
import base64
import logging
import sqlite3
import signal
import sys
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any, Tuple
from aiohttp import ClientSession, FormData
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, ContextTypes, filters
from telegram.constants import ParseMode
from telegram.error import BadRequest, TimedOut, NetworkError

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    stream=sys.stdout
)
logger = logging.getLogger(__name__)

ADMIN_USERNAME: str = "Totoong_bryl_john"
ADMIN_IDS: set = set()

class Database:
    def __init__(self) -> None:
        self.conn = sqlite3.connect('bot_database.db', check_same_thread=False)
        self.cursor = self.conn.cursor()
        self.init_database()
    
    def init_database(self) -> None:
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                user_id INTEGER PRIMARY KEY,
                username TEXT,
                first_name TEXT,
                last_name TEXT,
                balance INTEGER DEFAULT 1000,
                total_won INTEGER DEFAULT 0,
                total_lost INTEGER DEFAULT 0,
                games_played INTEGER DEFAULT 0,
                last_daily TIMESTAMP,
                join_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS game_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                game_type TEXT,
                bet_amount INTEGER,
                result TEXT,
                win_amount INTEGER,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS jackpot (
                id INTEGER PRIMARY KEY,
                amount INTEGER DEFAULT 10000
            )
        ''')
        
        self.cursor.execute("SELECT COUNT(*) FROM jackpot")
        if self.cursor.fetchone()[0] == 0:
            self.cursor.execute("INSERT INTO jackpot (amount) VALUES (10000)")
        
        self.conn.commit()
    
    def get_user(self, user_id: int) -> Optional[Tuple]:
        self.cursor.execute("SELECT * FROM users WHERE user_id = ?", (user_id,))
        return self.cursor.fetchone()
    
    def create_user(self, user_id: int, username: str, first_name: str, last_name: str) -> None:
        self.cursor.execute('''
            INSERT INTO users (user_id, username, first_name, last_name, balance, join_date)
            VALUES (?, ?, ?, ?, 1000, CURRENT_TIMESTAMP)
        ''', (user_id, username, first_name, last_name))
        self.conn.commit()
    
    def update_balance(self, user_id: int, amount: int) -> None:
        self.cursor.execute("UPDATE users SET balance = balance + ? WHERE user_id = ?", (amount, user_id))
        self.conn.commit()
    
    def update_stats(self, user_id: int, won: bool, bet: int, win_amount: int) -> None:
        if won:
            self.cursor.execute("UPDATE users SET total_won = total_won + ?, games_played = games_played + 1 WHERE user_id = ?", (win_amount, user_id))
        else:
            self.cursor.execute("UPDATE users SET total_lost = total_lost + ?, games_played = games_played + 1 WHERE user_id = ?", (bet, user_id))
        self.conn.commit()
    
    def add_game_history(self, user_id: int, game_type: str, bet: int, result: str, win_amount: int) -> None:
        self.cursor.execute('''
            INSERT INTO game_history (user_id, game_type, bet_amount, result, win_amount)
            VALUES (?, ?, ?, ?, ?)
        ''', (user_id, game_type, bet, result, win_amount))
        self.conn.commit()
    
    def get_top_users(self, limit: int = 10, order_by: str = 'balance') -> List[Tuple]:
        self.cursor.execute(f'''
            SELECT user_id, username, first_name, balance, total_won, total_lost, games_played
            FROM users
            ORDER BY {order_by} DESC
            LIMIT ?
        ''', (limit,))
        return self.cursor.fetchall()
    
    def get_total_users(self) -> int:
        self.cursor.execute("SELECT COUNT(*) FROM users")
        return self.cursor.fetchone()[0]
    
    def get_jackpot(self) -> int:
        self.cursor.execute("SELECT amount FROM jackpot WHERE id = 1")
        return self.cursor.fetchone()[0]
    
    def update_jackpot(self, amount: int) -> None:
        self.cursor.execute("UPDATE jackpot SET amount = amount + ? WHERE id = 1", (amount,))
        self.conn.commit()
    
    def reset_jackpot(self) -> None:
        self.cursor.execute("UPDATE jackpot SET amount = 10000 WHERE id = 1")
        self.conn.commit()
    
    def get_daily_bonus_available(self, user_id: int) -> bool:
        self.cursor.execute("SELECT last_daily FROM users WHERE user_id = ?", (user_id,))
        result = self.cursor.fetchone()
        if not result or not result[0]:
            return True
        try:
            last_daily = datetime.fromisoformat(result[0].replace('Z', '+00:00'))
        except:
            last_daily = datetime.now()
        return datetime.now() - last_daily > timedelta(hours=24)
    
    def claim_daily(self, user_id: int) -> None:
        self.cursor.execute("UPDATE users SET last_daily = CURRENT_TIMESTAMP WHERE user_id = ?", (user_id,))
        self.conn.commit()
    
    def get_user_stats(self, user_id: int) -> Optional[Dict[str, Any]]:
        self.cursor.execute('''
            SELECT balance, total_won, total_lost, games_played, join_date
            FROM users WHERE user_id = ?
        ''', (user_id,))
        result = self.cursor.fetchone()
        if result:
            return {
                'balance': result[0],
                'total_won': result[1],
                'total_lost': result[2],
                'games_played': result[3],
                'join_date': result[4]
            }
        return None
    
    def admin_give_coins(self, user_id: int, amount: int) -> None:
        self.cursor.execute("UPDATE users SET balance = balance + ? WHERE user_id = ?", (amount, user_id))
        self.conn.commit()
    
    def admin_reset_user(self, user_id: int) -> None:
        self.cursor.execute("UPDATE users SET balance = 1000, total_won = 0, total_lost = 0, games_played = 0 WHERE user_id = ?", (user_id,))
        self.conn.commit()
    
    def get_all_users(self) -> List[Tuple]:
        self.cursor.execute("SELECT user_id, username, first_name, balance FROM users ORDER BY balance DESC")
        return self.cursor.fetchall()

class OperaAriaConversation:
    def __init__(self, refresh_token: Optional[str] = None) -> None:
        self.access_token: Optional[str] = None
        self.refresh_token: Optional[str] = refresh_token
        self.encryption_key: str = self._generate_encryption_key()
        self.expires_at: float = 0
        self.conversation_id: Optional[str] = None
        self.is_first_request: bool = True
        self.message_history: List[Dict[str, str]] = []
    
    def is_token_expired(self) -> bool:
        return time.time() >= self.expires_at
    
    def update_token(self, access_token: str, expires_in: int) -> None:
        self.access_token = access_token
        self.expires_at = time.time() + expires_in - 60
    
    @staticmethod
    def _generate_encryption_key() -> str:
        random_bytes = os.urandom(32)
        return base64.b64encode(random_bytes).decode('utf-8')
    
    def add_message(self, role: str, content: str) -> None:
        self.message_history.append({"role": role, "content": content})
        if len(self.message_history) > 20:
            self.message_history = self.message_history[-20:]
    
    def clear_history(self) -> None:
        self.message_history = []
        self.is_first_request = True
        self.conversation_id = None

class OperaAriaAPI:
    api_endpoint: str = "https://composer.opera-api.com/api/v1/a-chat"
    token_endpoint: str = "https://oauth2.opera-api.com/oauth2/v1/token/"
    signup_endpoint: str = "https://auth.opera.com/account/v2/external/anonymous/signup"
    upload_endpoint: str = "https://composer.opera-api.com/api/v1/images/upload"
    check_status_endpoint: str = "https://composer.opera-api.com/api/v1/images/check-status/"
    
    def __init__(self) -> None:
        self.user_conversations: Dict[int, OperaAriaConversation] = {}
    
    def get_or_create_conversation(self, user_id: int) -> OperaAriaConversation:
        if user_id not in self.user_conversations:
            self.user_conversations[user_id] = OperaAriaConversation()
        return self.user_conversations[user_id]
    
    async def _generate_refresh_token(self, session: ClientSession) -> str:
        headers = {
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36 OPR/89.0.0.0",
            "Content-Type": "application/x-www-form-urlencoded",
        }
        data = {
            "client_id": "ofa-client",
            "client_secret": "N9OscfA3KxlJASuIe29PGZ5RpWaMTBoy",
            "grant_type": "client_credentials",
            "scope": "anonymous_account"
        }
        async with session.post(self.token_endpoint, headers=headers, data=data) as response:
            response.raise_for_status()
            anonymous_token_data = await response.json()
            anonymous_access_token = anonymous_token_data["access_token"]
        
        headers = {
            "User-Agent": "Mozilla 5.0 (Linux; Android 14) com.opera.browser OPR/89.5.4705.84314",
            "Authorization": f"Bearer {anonymous_access_token}",
            "Accept": "application/json",
            "Content-Type": "application/json; charset=utf-8",
        }
        data = {"client_id": "ofa", "service": "aria"}
        async with session.post(self.signup_endpoint, headers=headers, json=data) as response:
            response.raise_for_status()
            signup_data = await response.json()
            auth_token = signup_data["token"]
        
        headers = {
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36 OPR/89.0.0.0",
            "Content-Type": "application/x-www-form-urlencoded",
        }
        data = {
            "auth_token": auth_token,
            "client_id": "ofa",
            "device_name": "GPT4FREE",
            "grant_type": "auth_token",
            "scope": "ALL"
        }
        async with session.post(self.token_endpoint, headers=headers, data=data) as response:
            response.raise_for_status()
            final_token_data = await response.json()
            return final_token_data["refresh_token"]
    
    async def get_access_token(self, session: ClientSession, conversation: OperaAriaConversation) -> str:
        if not conversation.refresh_token:
            conversation.refresh_token = await self._generate_refresh_token(session)
        
        if conversation.access_token and not conversation.is_token_expired():
            return conversation.access_token
        
        headers = {
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36 OPR/89.0.0.0"
        }
        data = {
            "client_id": "ofa",
            "grant_type": "refresh_token",
            "refresh_token": conversation.refresh_token,
            "scope": "shodan:aria user:read"
        }
        async with session.post(self.token_endpoint, headers=headers, data=data) as response:
            response.raise_for_status()
            result = await response.json()
            conversation.update_token(
                access_token=result["access_token"],
                expires_in=result.get("expires_in", 3600)
            )
            return result["access_token"]
    
    async def check_upload_status(self, session: ClientSession, access_token: str, image_id: str, max_attempts: int = 30) -> None:
        headers = {
            "Authorization": f"Bearer {access_token}",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36 OPR/89.0.0.0",
        }
        url = f"{self.check_status_endpoint}{image_id}"
        for _ in range(max_attempts):
            async with session.get(url, headers=headers) as response:
                response.raise_for_status()
                result = await response.json()
                if result.get("status") == "ok":
                    return
                if result.get("status") == "failed":
                    raise Exception(f"Image upload failed for {image_id}")
                await asyncio.sleep(0.5)
        raise Exception(f"Timeout waiting for image upload status for {image_id}")
    
    async def upload_media(self, session: ClientSession, access_token: str, media_data: bytes, filename: str) -> str:
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Origin": "opera-aria://ui",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36 OPR/89.0.0.0",
        }
        form_data = FormData()
        if not filename:
            filename = str(int(time.time() * 1000))
        
        form_data.add_field('image_file', media_data, filename=filename)
        
        async with session.post(self.upload_endpoint, headers=headers, data=form_data) as response:
            response.raise_for_status()
            result = await response.json()
            image_id = result.get("image_id")
            if not image_id:
                raise Exception("No image_id returned from upload")
            await self.check_upload_status(session, access_token, image_id)
            return image_id
    
    @staticmethod
    def extract_image_urls(text: str) -> List[str]:
        pattern = r'!\[\]\((https?://[^\)]+)\)'
        urls = re.findall(pattern, text)
        return [url.replace(r'\/', '/') for url in urls]
    
    async def send_message(self, user_id: int, message: str, image_data: Optional[bytes] = None) -> Tuple[str, List[str]]:
        conversation = self.get_or_create_conversation(user_id)
        
        async with ClientSession() as session:
            access_token = await self.get_access_token(session, conversation)
            
            media_attachments = []
            if image_data:
                try:
                    filename = f"image_{int(time.time())}.jpg"
                    image_id = await self.upload_media(session, access_token, image_data, filename)
                    media_attachments.append(image_id)
                except Exception as e:
                    logger.error(f"Failed to upload image: {e}")
            
            headers = {
                "Accept": "text/event-stream",
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
                "Origin": "opera-aria://ui",
                "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36 OPR/89.0.0.0",
                "X-Opera-Timezone": "+03:00",
                "X-Opera-UI-Language": "en"
            }
            
            formatted_messages = []
            for msg in conversation.message_history:
                formatted_messages.append(msg)
            formatted_messages.append({"role": "user", "content": message})
            
            prompt = ""
            for msg in formatted_messages:
                role = "User" if msg["role"] == "user" else "Assistant"
                prompt += f"{role}: {msg['content']}\n"
            prompt += "Assistant: "
            
            data = {
                "query": prompt,
                "stream": True,
                "linkify": True,
                "linkify_version": 3,
                "sia": True,
                "media_attachments": media_attachments,
                "encryption": {"key": conversation.encryption_key}
            }
            
            if not conversation.is_first_request and conversation.conversation_id:
                data["conversation_id"] = conversation.conversation_id
            
            full_response = ""
            all_image_urls = []
            
            async with session.post(self.api_endpoint, headers=headers, json=data) as response:
                response.raise_for_status()
                
                async for line in response.content:
                    if not line:
                        continue
                    decoded = line.decode('utf-8').strip()
                    if not decoded.startswith('data: '):
                        continue
                    
                    content = decoded[6:]
                    if content == '[DONE]':
                        break
                    
                    try:
                        json_data = json.loads(content)
                        if 'message' in json_data:
                            message_chunk = json_data['message']
                            image_urls = self.extract_image_urls(message_chunk)
                            if image_urls:
                                all_image_urls.extend(image_urls)
                            else:
                                full_response += message_chunk
                        
                        if 'conversation_id' in json_data and json_data['conversation_id']:
                            conversation.conversation_id = json_data['conversation_id']
                    
                    except json.JSONDecodeError:
                        continue
            
            conversation.is_first_request = False
            conversation.add_message("user", message)
            conversation.add_message("assistant", full_response)
            
            return full_response, all_image_urls

class GamblingGames:
    def __init__(self, db: Database) -> None:
        self.db = db
    
    async def slots(self, user_id: int, bet: int) -> Tuple[str, int, bool]:
        user = self.db.get_user(user_id)
        if user[4] < bet:
            return "❌ Insufficient balance!", 0, False
        
        emojis = ["🍒", "🍋", "🍊", "🍇", "💎", "7️⃣"]
        result = [random.choice(emojis) for _ in range(3)]
        
        win_amount = 0
        if result[0] == result[1] == result[2]:
            if result[0] == "7️⃣":
                win_amount = bet * 10
            elif result[0] == "💎":
                win_amount = bet * 5
            else:
                win_amount = bet * 3
        elif result[0] == result[1] or result[1] == result[2] or result[0] == result[2]:
            win_amount = bet * 2
        
        message = f"🎰 *Slots Result:*\n`{' '.join(result)}`\n"
        
        if win_amount > 0:
            message += f"🎉 You won {win_amount} coins!"
            self.db.update_balance(user_id, win_amount - bet)
            self.db.update_stats(user_id, True, bet, win_amount)
            self.db.add_game_history(user_id, "slots", bet, "win", win_amount)
            return message, win_amount - bet, True
        else:
            message += f"😢 You lost {bet} coins!"
            self.db.update_balance(user_id, -bet)
            self.db.update_stats(user_id, False, bet, 0)
            self.db.add_game_history(user_id, "slots", bet, "lose", 0)
            return message, -bet, False
    
    async def dice(self, user_id: int, bet: int, guess: int) -> Tuple[str, int, bool]:
        if guess < 1 or guess > 6:
            return "❌ Guess must be between 1 and 6!", 0, False
        
        user = self.db.get_user(user_id)
        if user[4] < bet:
            return "❌ Insufficient balance!", 0, False
        
        roll = random.randint(1, 6)
        
        if roll == guess:
            win_amount = bet * 6
            message = f"🎲 *Dice rolled:* {roll}\n🎉 Perfect guess! You won {win_amount} coins!"
            self.db.update_balance(user_id, win_amount - bet)
            self.db.update_stats(user_id, True, bet, win_amount)
            self.db.add_game_history(user_id, "dice", bet, "win", win_amount)
            return message, win_amount - bet, True
        else:
            message = f"🎲 *Dice rolled:* {roll}\n😢 Wrong guess! You lost {bet} coins!"
            self.db.update_balance(user_id, -bet)
            self.db.update_stats(user_id, False, bet, 0)
            self.db.add_game_history(user_id, "dice", bet, "lose", 0)
            return message, -bet, False
    
    async def coinflip(self, user_id: int, bet: int, choice: str) -> Tuple[str, int, bool]:
        user = self.db.get_user(user_id)
        if user[4] < bet:
            return "❌ Insufficient balance!", 0, False
        
        choice = choice.lower()
        if choice not in ['heads', 'tails', 'h', 't']:
            return "❌ Choose heads or tails!", 0, False
        
        result = random.choice(['heads', 'tails'])
        choice_full = 'heads' if choice in ['heads', 'h'] else 'tails'
        
        if choice_full == result:
            win_amount = bet * 2
            message = f"🪙 *Coin flip:* {result.upper()}!\n🎉 You won {win_amount} coins!"
            self.db.update_balance(user_id, win_amount - bet)
            self.db.update_stats(user_id, True, bet, win_amount)
            self.db.add_game_history(user_id, "coinflip", bet, "win", win_amount)
            return message, win_amount - bet, True
        else:
            message = f"🪙 *Coin flip:* {result.upper()}!\n😢 You lost {bet} coins!"
            self.db.update_balance(user_id, -bet)
            self.db.update_stats(user_id, False, bet, 0)
            self.db.add_game_history(user_id, "coinflip", bet, "lose", 0)
            return message, -bet, False
    
    async def roulette(self, user_id: int, bet: int, bet_type: str, bet_value: str) -> Tuple[str, int, bool]:
        user = self.db.get_user(user_id)
        if user[4] < bet:
            return "❌ Insufficient balance!", 0, False
        
        number = random.randint(0, 36)
        color = 'red' if number in [1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36] else 'black' if number != 0 else 'green'
        is_even = number % 2 == 0 if number != 0 else False
        
        win = False
        multiplier = 0
        
        if bet_type == 'number':
            if str(number) == bet_value:
                win = True
                multiplier = 35
        elif bet_type == 'color':
            if color == bet_value:
                win = True
                multiplier = 2
        elif bet_type == 'evenodd':
            if (bet_value == 'even' and is_even) or (bet_value == 'odd' and not is_even and number != 0):
                win = True
                multiplier = 2
        
        if win:
            win_amount = bet * multiplier
            message = f"🎡 *Roulette:* {number} {color.upper()}\n🎉 You won {win_amount} coins!"
            self.db.update_balance(user_id, win_amount - bet)
            self.db.update_stats(user_id, True, bet, win_amount)
            self.db.add_game_history(user_id, "roulette", bet, "win", win_amount)
            return message, win_amount - bet, True
        else:
            message = f"🎡 *Roulette:* {number} {color.upper()}\n😢 You lost {bet} coins!"
            self.db.update_balance(user_id, -bet)
            self.db.update_stats(user_id, False, bet, 0)
            self.db.add_game_history(user_id, "roulette", bet, "lose", 0)
            return message, -bet, False
    
    async def jackpot_spin(self, user_id: int, bet: int) -> Tuple[str, int, bool]:
        user = self.db.get_user(user_id)
        if user[4] < bet:
            return "❌ Insufficient balance!", 0, False
        
        jackpot = self.db.get_jackpot()
        self.db.update_jackpot(bet // 2)
        
        if random.random() < 0.001:
            win_amount = jackpot
            message = f"🎰🎰🎰 *JACKPOT!!!* 🎰🎰🎰\n💎 You won {win_amount} coins! 💎"
            self.db.update_balance(user_id, win_amount - bet)
            self.db.update_stats(user_id, True, bet, win_amount)
            self.db.add_game_history(user_id, "jackpot", bet, "win", win_amount)
            self.db.reset_jackpot()
            return message, win_amount - bet, True
        else:
            message = f"🎰 *Jackpot spin...* No luck this time! Lost {bet} coins.\n💰 Current jackpot: {jackpot + bet//2} coins"
            self.db.update_balance(user_id, -bet)
            self.db.update_stats(user_id, False, bet, 0)
            self.db.add_game_history(user_id, "jackpot", bet, "lose", 0)
            return message, -bet, False
    
    async def crash(self, user_id: int, bet: int, auto_cashout: Optional[float] = None) -> Tuple[str, int, bool]:
        user = self.db.get_user(user_id)
        if user[4] < bet:
            return "❌ Insufficient balance!", 0, False
        
        crash_point = random.expovariate(1/2) + 1
        
        if auto_cashout:
            if auto_cashout <= 1:
                return "❌ Auto cashout must be greater than 1.0x!", 0, False
            
            if crash_point >= auto_cashout:
                win_amount = int(bet * auto_cashout)
                message = f"📈 *CRASH:* Crashed at {crash_point:.2f}x\n✅ Auto-cashed out at {auto_cashout:.2f}x!\n🎉 You won {win_amount} coins!"
                self.db.update_balance(user_id, win_amount - bet)
                self.db.update_stats(user_id, True, bet, win_amount)
                self.db.add_game_history(user_id, "crash", bet, "win", win_amount)
                return message, win_amount - bet, True
            else:
                message = f"📈 *CRASH:* Crashed at {crash_point:.2f}x\n💥 Crashed before your auto-cashout at {auto_cashout:.2f}x!\n😢 You lost {bet} coins!"
                self.db.update_balance(user_id, -bet)
                self.db.update_stats(user_id, False, bet, 0)
                self.db.add_game_history(user_id, "crash", bet, "lose", 0)
                return message, -bet, False
        
        return f"📈 *CRASH:* Game started! Use /cashout to collect your winnings!", 0, False

opera_api = OperaAriaAPI()
db = Database()
gambling = GamblingGames(db)
active_crash_games: Dict[int, Dict[str, Any]] = {}

def get_main_keyboard() -> ReplyKeyboardMarkup:
    keyboard = [
        [KeyboardButton("🎰 Slots"), KeyboardButton("🎲 Dice")],
        [KeyboardButton("🪙 Coin Flip"), KeyboardButton("🎡 Roulette")],
        [KeyboardButton("💰 Balance"), KeyboardButton("🏆 Top Players")],
        [KeyboardButton("🤖 AI Chat"), KeyboardButton("❓ Help")]
    ]
    return ReplyKeyboardMarkup(keyboard, resize_keyboard=True)

async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    logger.error(f"Exception while handling an update: {context.error}")

async def check_admin(user_id: int, username: Optional[str]) -> bool:
    if username and username.lower() == ADMIN_USERNAME.lower():
        ADMIN_IDS.add(user_id)
        return True
    return user_id in ADMIN_IDS

def admin_only(func):
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        user_id = update.effective_user.id
        username = update.effective_user.username
        if not await check_admin(user_id, username):
            await update.message.reply_text("⛔ This command is for admins only!")
            return
        return await func(update, context)
    return wrapper

async def safe_callback_answer(query) -> None:
    try:
        await query.answer()
    except (BadRequest, TimedOut, NetworkError):
        pass

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user = update.effective_user
    if not db.get_user(user.id):
        db.create_user(user.id, user.username or "Unknown", user.first_name or "", user.last_name or "")
    
    welcome_message = (
        "🎮 *WELCOME TO OPERA AI CASINO BOT* 🎮\n\n"
        "🤖 *AI Commands:*\n"
        "/ask - Chat with Opera AI\n"
        "/new - Start new conversation\n"
        "/history - View chat history\n\n"
        "🎰 *Casino Games:*\n"
        "/slots [bet] - Play slot machine\n"
        "/dice [bet] [1-6] - Guess the dice roll\n"
        "/coinflip [bet] [heads/tails] - Flip a coin\n"
        "/roulette [bet] [number/color/evenodd] [value]\n"
        "/jackpot [bet] - Try to win the jackpot!\n"
        "/crash [bet] [auto_cashout] - Play crash game\n\n"
        "💰 *Economy:*\n"
        "/balance - Check your balance\n"
        "/daily - Claim daily bonus (500 coins)\n"
        "/top - View top players\n"
        "/stats - View your statistics\n\n"
        "🎲 *Start with 1000 coins! Good luck!* 🍀"
    )
    
    await update.message.reply_text(
        welcome_message, 
        parse_mode=ParseMode.MARKDOWN, 
        reply_markup=get_main_keyboard()
    )

async def ask_ai(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        await update.message.reply_text("❌ Please provide a question!\nUsage: /ask [your question]")
        return
    
    question = ' '.join(context.args)
    processing_msg = await update.message.reply_text("🤔 *AI is thinking...*", parse_mode=ParseMode.MARKDOWN)
    
    try:
        response, image_urls = await opera_api.send_message(update.effective_user.id, question)
        
        if image_urls:
            for url in image_urls[:5]:
                try:
                    await update.message.reply_photo(url)
                except:
                    pass
        
        if response:
            await processing_msg.edit_text(f"🤖 *AI Response:*\n\n{response}", parse_mode=ParseMode.MARKDOWN)
        else:
            await processing_msg.edit_text("❌ No response received. Please try again.")
    except Exception as e:
        await processing_msg.edit_text(f"❌ Error: {str(e)[:100]}")

async def slots_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    if not context.args:
        await update.message.reply_text("❌ Usage: /slots [bet_amount]")
        return
    
    try:
        bet = int(context.args[0])
        if bet < 10:
            await update.message.reply_text("❌ Minimum bet is 10 coins!")
            return
        if bet > 10000:
            await update.message.reply_text("❌ Maximum bet is 10000 coins!")
            return
        
        message, net_change, won = await gambling.slots(user_id, bet)
        
        keyboard = [[InlineKeyboardButton("🎰 Play Again", callback_data=f'slots_{bet}')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
    except ValueError:
        await update.message.reply_text("❌ Invalid bet amount!")

async def dice_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if len(context.args) < 2:
        await update.message.reply_text("❌ Usage: /dice [bet] [guess 1-6]")
        return
    
    try:
        bet = int(context.args[0])
        guess = int(context.args[1])
        
        if bet < 10:
            await update.message.reply_text("❌ Minimum bet is 10 coins!")
            return
        
        message, net_change, won = await gambling.dice(update.effective_user.id, bet, guess)
        
        keyboard = [[InlineKeyboardButton("🎲 Roll Again", callback_data=f'dice_{bet}')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
    except ValueError:
        await update.message.reply_text("❌ Invalid bet or guess!")

async def coinflip_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if len(context.args) < 2:
        await update.message.reply_text("❌ Usage: /coinflip [bet] [heads/tails]")
        return
    
    try:
        bet = int(context.args[0])
        choice = context.args[1]
        
        if bet < 10:
            await update.message.reply_text("❌ Minimum bet is 10 coins!")
            return
        
        message, net_change, won = await gambling.coinflip(update.effective_user.id, bet, choice)
        
        keyboard = [[InlineKeyboardButton("🪙 Flip Again", callback_data=f'coinflip_{bet}')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
    except ValueError:
        await update.message.reply_text("❌ Invalid bet amount!")

async def roulette_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if len(context.args) < 3:
        await update.message.reply_text("❌ Usage: /roulette [bet] [number/color/evenodd] [value]")
        return
    
    try:
        bet = int(context.args[0])
        bet_type = context.args[1].lower()
        bet_value = context.args[2].lower()
        
        if bet < 10:
            await update.message.reply_text("❌ Minimum bet is 10 coins!")
            return
        
        message, net_change, won = await gambling.roulette(update.effective_user.id, bet, bet_type, bet_value)
        
        keyboard = [[InlineKeyboardButton("🎡 Spin Again", callback_data=f'roulette_{bet}')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        
        await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
    except ValueError:
        await update.message.reply_text("❌ Invalid bet amount!")

async def jackpot_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        await update.message.reply_text("❌ Usage: /jackpot [bet]")
        return
    
    try:
        bet = int(context.args[0])
        if bet < 50:
            await update.message.reply_text("❌ Minimum bet for jackpot is 50 coins!")
            return
        
        jackpot_amount = db.get_jackpot()
        message, net_change, won = await gambling.jackpot_spin(update.effective_user.id, bet)
        
        if not won:
            keyboard = [[InlineKeyboardButton("🎰 Spin for Jackpot!", callback_data=f'jackpot_{bet}')]]
            reply_markup = InlineKeyboardMarkup(keyboard)
            await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
        else:
            await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN)
    except ValueError:
        await update.message.reply_text("❌ Invalid bet amount!")

async def crash_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    
    if not context.args:
        await update.message.reply_text("❌ Usage: /crash [bet] [auto_cashout]")
        return
    
    try:
        bet = int(context.args[0])
        auto_cashout = float(context.args[1]) if len(context.args) > 1 else None
        
        if bet < 10:
            await update.message.reply_text("❌ Minimum bet is 10 coins!")
            return
        
        if user_id in active_crash_games:
            await update.message.reply_text("❌ You already have an active crash game! Use /cashout to collect.")
            return
        
        message, net_change, won = await gambling.crash(user_id, bet, auto_cashout)
        
        if "Use /cashout" in message:
            active_crash_games[user_id] = {"bet": bet, "start_time": time.time()}
            keyboard = [[InlineKeyboardButton("💰 CASHOUT NOW!", callback_data='crash_cashout')]]
            reply_markup = InlineKeyboardMarkup(keyboard)
            await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
        else:
            await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN)
    except ValueError:
        await update.message.reply_text("❌ Invalid bet or cashout multiplier!")

async def cashout_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    
    if user_id not in active_crash_games:
        await update.message.reply_text("❌ No active crash game! Start one with /crash")
        return
    
    game_data = active_crash_games[user_id]
    elapsed = time.time() - game_data["start_time"]
    multiplier = 1.0 + (elapsed * 0.1)
    
    crash_point = random.expovariate(1/2) + 1
    
    if crash_point >= multiplier:
        win_amount = int(game_data["bet"] * multiplier)
        db.update_balance(user_id, win_amount - game_data["bet"])
        db.update_stats(user_id, True, game_data["bet"], win_amount)
        db.add_game_history(user_id, "crash", game_data["bet"], "win", win_amount)
        
        message = f"📈 *CRASH:* Crashed at {crash_point:.2f}x\n✅ Cashed out at {multiplier:.2f}x!\n🎉 You won {win_amount} coins!"
    else:
        db.update_balance(user_id, -game_data["bet"])
        db.update_stats(user_id, False, game_data["bet"], 0)
        db.add_game_history(user_id, "crash", game_data["bet"], "lose", 0)
        
        message = f"📈 *CRASH:* Crashed at {crash_point:.2f}x\n💥 Too late! You lost {game_data['bet']} coins!"
    
    del active_crash_games[user_id]
    await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN)

async def balance_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    user = db.get_user(user_id)
    
    if not user:
        await update.message.reply_text("❌ You're not registered! Use /start to register.")
        return
    
    stats = db.get_user_stats(user_id)
    jackpot = db.get_jackpot()
    
    message = (
        f"💰 *Your Balance*\n\n"
        f"💵 Balance: {user[4]} coins\n"
        f"📊 Total Won: {stats['total_won']} coins\n"
        f"📉 Total Lost: {stats['total_lost']} coins\n"
        f"🎮 Games Played: {stats['games_played']}\n"
        f"📅 Joined: {stats['join_date'][:10]}\n\n"
        f"🎰 Current Jackpot: {jackpot} coins"
    )
    
    await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN)

async def daily_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    user = db.get_user(user_id)
    
    if not user:
        await update.message.reply_text("❌ You're not registered! Use /start to register.")
        return
    
    if db.get_daily_bonus_available(user_id):
        bonus = 500
        db.update_balance(user_id, bonus)
        db.claim_daily(user_id)
        await update.message.reply_text(f"✅ You claimed your daily bonus of {bonus} coins!\n💰 New balance: {user[4] + bonus} coins")
    else:
        await update.message.reply_text("⏰ You already claimed your daily bonus! Come back tomorrow.")

async def top_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    top_users = db.get_top_users(10)
    
    if not top_users:
        await update.message.reply_text("❌ No users found!")
        return
    
    message = "🏆 *TOP 10 PLAYERS* 🏆\n\n"
    
    for i, user in enumerate(top_users, 1):
        medal = "🥇" if i == 1 else "🥈" if i == 2 else "🥉" if i == 3 else f"{i}."
        name = user[2] if user[2] else f"@{user[1]}" if user[1] else f"User {user[0]}"
        message += f"{medal} {name}: {user[3]} coins\n"
    
    message += f"\n👥 Total Players: {db.get_total_users()}"
    
    await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN)

async def stats_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    total_users = db.get_total_users()
    jackpot = db.get_jackpot()
    
    message = (
        f"📊 *BOT STATISTICS*\n\n"
        f"👥 Total Users: {total_users}\n"
        f"🎰 Current Jackpot: {jackpot} coins\n"
        f"🤖 AI Model: Opera Aria\n"
        f"🎮 Games Available: 6\n\n"
        f"*Top Winners:*\n"
    )
    
    top_winners = db.get_top_users(3, 'total_won')
    for i, user in enumerate(top_winners, 1):
        name = user[2] or f"@{user[1]}" or f"User {user[0]}"
        message += f"{i}. {name}: Won {user[4]} coins\n"
    
    await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN)

async def users_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    all_users = db.get_all_users()
    total_users = len(all_users)
    
    message = f"👥 *REGISTERED USERS* ({total_users})\n\n"
    
    for user in all_users[:20]:
        name = user[2] or f"@{user[1]}" or f"User {user[0]}"
        message += f"• {name}: {user[3]} coins\n"
    
    if total_users > 20:
        message += f"\n... and {total_users - 20} more users"
    
    await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN)

async def new_chat(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    if user_id in opera_api.user_conversations:
        opera_api.user_conversations[user_id].clear_history()
    await update.message.reply_text("🆕 *New conversation started!*", parse_mode=ParseMode.MARKDOWN)

async def show_history(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    conversation = opera_api.get_or_create_conversation(user_id)
    
    if not conversation.message_history:
        await update.message.reply_text("📭 No conversation history yet.")
        return
    
    history_text = "*📜 Conversation History:*\n\n"
    for i, msg in enumerate(conversation.message_history[-10:], 1):
        role_emoji = "👤" if msg["role"] == "user" else "🤖"
        content = msg["content"][:100] + "..." if len(msg["content"]) > 100 else msg["content"]
        history_text += f"{i}. {role_emoji} {content}\n\n"
    
    await update.message.reply_text(history_text, parse_mode=ParseMode.MARKDOWN)

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    help_text = (
        "📚 *HELP MENU*\n\n"
        "🎰 *Games:* /slots, /dice, /coinflip, /roulette, /jackpot, /crash\n"
        "💰 *Economy:* /balance, /daily, /top, /stats\n"
        "🤖 *AI:* /ask, /new, /history\n"
        "👑 *Admin:* /give, /reset, /broadcast, /addcoins, /admin"
    )
    await update.message.reply_text(help_text, parse_mode=ParseMode.MARKDOWN)

async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    text = update.message.text
    user_id = update.effective_user.id
    
    if text == "🎰 Slots":
        await update.message.reply_text("Enter bet amount: /slots [amount]")
    elif text == "🎲 Dice":
        await update.message.reply_text("Enter bet and guess: /dice [bet] [1-6]")
    elif text == "🪙 Coin Flip":
        await update.message.reply_text("Enter bet and choice: /coinflip [bet] [heads/tails]")
    elif text == "🎡 Roulette":
        await update.message.reply_text("Enter: /roulette [bet] [number/color/evenodd] [value]")
    elif text == "💰 Balance":
        await balance_command(update, context)
    elif text == "🏆 Top Players":
        await top_command(update, context)
    elif text == "🤖 AI Chat":
        await update.message.reply_text("Send me a message and I'll respond with AI!")
    elif text == "❓ Help":
        await help_command(update, context)
    else:
        processing_msg = await update.message.reply_text("🤔 *Thinking...*", parse_mode=ParseMode.MARKDOWN)
        
        try:
            response, image_urls = await opera_api.send_message(user_id, text)
            
            if image_urls:
                for url in image_urls[:5]:
                    try:
                        await update.message.reply_photo(url)
                    except:
                        pass
            
            if response:
                await processing_msg.edit_text(response, parse_mode=ParseMode.MARKDOWN)
            else:
                await processing_msg.edit_text("❌ No response received. Please try again.")
        
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            await processing_msg.edit_text(f"❌ Error: {str(e)[:100]}")

async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    user_id = update.effective_user.id
    caption = update.message.caption or "What's in this image?"
    
    processing_msg = await update.message.reply_text("🖼 *Analyzing image...*", parse_mode=ParseMode.MARKDOWN)
    
    try:
        photo_file = await update.message.photo[-1].get_file()
        
        import io
        image_bytes = io.BytesIO()
        await photo_file.download_to_memory(image_bytes)
        image_data = image_bytes.getvalue()
        
        response, image_urls = await opera_api.send_message(user_id, caption, image_data)
        
        if image_urls:
            for url in image_urls[:5]:
                try:
                    await update.message.reply_photo(url)
                except:
                    pass
        
        if response:
            await processing_msg.edit_text(response, parse_mode=ParseMode.MARKDOWN)
        else:
            await processing_msg.edit_text("❌ No analysis received. Please try again.")
    
    except Exception as e:
        logger.error(f"Error processing image: {e}")
        await processing_msg.edit_text(f"❌ Error analyzing image: {str(e)[:100]}")

@admin_only
async def give_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if len(context.args) < 2:
        await update.message.reply_text("❌ Usage: /give [user_id] [amount]")
        return
    
    try:
        target_id = int(context.args[0])
        amount = int(context.args[1])
        
        if not db.get_user(target_id):
            await update.message.reply_text("❌ User not found!")
            return
        
        db.admin_give_coins(target_id, amount)
        await update.message.reply_text(f"✅ Gave {amount} coins to user {target_id}")
    except ValueError:
        await update.message.reply_text("❌ Invalid user ID or amount!")

@admin_only
async def reset_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        await update.message.reply_text("❌ Usage: /reset [user_id]")
        return
    
    try:
        target_id = int(context.args[0])
        
        if not db.get_user(target_id):
            await update.message.reply_text("❌ User not found!")
            return
        
        db.admin_reset_user(target_id)
        await update.message.reply_text(f"✅ Reset user {target_id}'s stats to default")
    except ValueError:
        await update.message.reply_text("❌ Invalid user ID!")

@admin_only
async def broadcast_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        await update.message.reply_text("❌ Usage: /broadcast [message]")
        return
    
    message = ' '.join(context.args)
    users = db.get_all_users()
    
    success = 0
    failed = 0
    
    for user in users:
        try:
            await context.bot.send_message(user[0], f"📢 *BROADCAST*\n\n{message}", parse_mode=ParseMode.MARKDOWN)
            success += 1
            await asyncio.sleep(0.05)
        except:
            failed += 1
    
    await update.message.reply_text(f"✅ Broadcast sent!\nSuccess: {success}\nFailed: {failed}")

@admin_only
async def addcoins_command(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not context.args:
        await update.message.reply_text("❌ Usage: /addcoins [amount]")
        return
    
    try:
        amount = int(context.args[0])
        users = db.get_all_users()
        
        for user in users:
            db.admin_give_coins(user[0], amount)
        
        await update.message.reply_text(f"✅ Added {amount} coins to {len(users)} users!")
    except ValueError:
        await update.message.reply_text("❌ Invalid amount!")

@admin_only
async def admin_panel(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    total_users = db.get_total_users()
    jackpot = db.get_jackpot()
    
    message = (
        f"👑 *ADMIN PANEL*\n\n"
        f"👥 Total Users: {total_users}\n"
        f"🎰 Jackpot: {jackpot} coins\n"
        f"🤖 AI Status: Online\n\n"
        f"*Admin Commands:*\n"
        f"/give [id] [amount] - Give coins\n"
        f"/reset [id] - Reset user\n"
        f"/broadcast [msg] - Message all\n"
        f"/addcoins [amount] - Give to all\n"
    )
    
    keyboard = [
        [InlineKeyboardButton("📊 View All Users", callback_data='admin_users')],
        [InlineKeyboardButton("🎰 Reset Jackpot", callback_data='admin_reset_jackpot')]
    ]
    reply_markup = InlineKeyboardMarkup(keyboard)
    
    await update.message.reply_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)

async def button_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    await safe_callback_answer(query)
    
    user_id = update.effective_user.id
    data = query.data
    
    if data.startswith('slots_'):
        bet = int(data.split('_')[1])
        message, net_change, won = await gambling.slots(user_id, bet)
        keyboard = [[InlineKeyboardButton("🎰 Play Again", callback_data=f'slots_{bet}')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        try:
            await query.edit_message_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
        except BadRequest:
            await query.message.reply_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
    
    elif data.startswith('dice_'):
        bet = int(data.split('_')[1])
        await query.edit_message_text(f"Enter your guess (1-6):\nBet: {bet} coins")
        context.user_data['dice_bet'] = bet
    
    elif data.startswith('coinflip_'):
        bet = int(data.split('_')[1])
        keyboard = [
            [InlineKeyboardButton("Heads", callback_data=f'coinflip_choice_{bet}_heads'),
             InlineKeyboardButton("Tails", callback_data=f'coinflip_choice_{bet}_tails')]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(f"Choose heads or tails!\nBet: {bet} coins", reply_markup=reply_markup)
    
    elif data.startswith('coinflip_choice_'):
        parts = data.split('_')
        bet = int(parts[2])
        choice = parts[3]
        message, net_change, won = await gambling.coinflip(user_id, bet, choice)
        keyboard = [[InlineKeyboardButton("🪙 Flip Again", callback_data=f'coinflip_{bet}')]]
        reply_markup = InlineKeyboardMarkup(keyboard)
        try:
            await query.edit_message_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
        except BadRequest:
            await query.message.reply_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
    
    elif data.startswith('roulette_'):
        bet = int(data.split('_')[1])
        keyboard = [
            [InlineKeyboardButton("Number", callback_data=f'roulette_type_{bet}_number'),
             InlineKeyboardButton("Color", callback_data=f'roulette_type_{bet}_color')],
            [InlineKeyboardButton("Even/Odd", callback_data=f'roulette_type_{bet}_evenodd')]
        ]
        reply_markup = InlineKeyboardMarkup(keyboard)
        await query.edit_message_text(f"Choose bet type!\nBet: {bet} coins", reply_markup=reply_markup)
    
    elif data.startswith('roulette_type_'):
        parts = data.split('_')
        bet = int(parts[2])
        bet_type = parts[3]
        context.user_data['roulette_bet'] = bet
        context.user_data['roulette_type'] = bet_type
        await query.edit_message_text(f"Enter your {bet_type}:\nBet: {bet} coins")
    
    elif data.startswith('jackpot_'):
        bet = int(data.split('_')[1])
        message, net_change, won = await gambling.jackpot_spin(user_id, bet)
        if not won:
            keyboard = [[InlineKeyboardButton("🎰 Spin for Jackpot!", callback_data=f'jackpot_{bet}')]]
            reply_markup = InlineKeyboardMarkup(keyboard)
            try:
                await query.edit_message_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
            except BadRequest:
                await query.message.reply_text(message, parse_mode=ParseMode.MARKDOWN, reply_markup=reply_markup)
        else:
            try:
                await query.edit_message_text(message, parse_mode=ParseMode.MARKDOWN)
            except BadRequest:
                await query.message.reply_text(message, parse_mode=ParseMode.MARKDOWN)
    
    elif data == 'crash_cashout':
        if user_id in active_crash_games:
            game_data = active_crash_games[user_id]
            elapsed = time.time() - game_data["start_time"]
            multiplier = 1.0 + (elapsed * 0.1)
            
            crash_point = random.expovariate(1/2) + 1
            
            if crash_point >= multiplier:
                win_amount = int(game_data["bet"] * multiplier)
                db.update_balance(user_id, win_amount - game_data["bet"])
                db.update_stats(user_id, True, game_data["bet"], win_amount)
                db.add_game_history(user_id, "crash", game_data["bet"], "win", win_amount)
                
                message = f"📈 *CRASH:* Crashed at {crash_point:.2f}x\n✅ Cashed out at {multiplier:.2f}x!\n🎉 You won {win_amount} coins!"
            else:
                db.update_balance(user_id, -game_data["bet"])
                db.update_stats(user_id, False, game_data["bet"], 0)
                db.add_game_history(user_id, "crash", game_data["bet"], "lose", 0)
                
                message = f"📈 *CRASH:* Crashed at {crash_point:.2f}x\n💥 Too late! You lost {game_data['bet']} coins!"
            
            del active_crash_games[user_id]
            try:
                await query.edit_message_text(message, parse_mode=ParseMode.MARKDOWN)
            except BadRequest:
                await query.message.reply_text(message, parse_mode=ParseMode.MARKDOWN)
    
    elif data == 'admin_users':
        if not await check_admin(user_id, update.effective_user.username):
            await query.edit_message_text("⛔ Admin only!")
            return
        
        users = db.get_all_users()[:20]
        message = f"👥 *All Users* ({len(users)} shown)\n\n"
        for user in users:
            name = user[2] or f"@{user[1]}" or f"User {user[0]}"
            message += f"• {name} (ID: {user[0]}): {user[3]} coins\n"
        
        await query.edit_message_text(message, parse_mode=ParseMode.MARKDOWN)
    
    elif data == 'admin_reset_jackpot':
        if not await check_admin(user_id, update.effective_user.username):
            await query.edit_message_text("⛔ Admin only!")
            return
        
        db.reset_jackpot()
        await query.edit_message_text("✅ Jackpot reset to 10000 coins!")

async def main() -> None:
    print("\n" + "="*60)
    print("🎮 TELEGRAM CASINO BOT WITH OPERA AI 🎮")
    print("="*60 + "\n")
    
    token_file = "token.txt"
    bot_token = None
    
    if os.path.exists(token_file):
        with open(token_file, 'r') as f:
            bot_token = f.read().strip()
        print(f"✅ Token loaded from {token_file}")
    else:
        print("🔑 YOUR TOKEN: ", end="")
        bot_token = input().strip()
        with open(token_file, 'w') as f:
            f.write(bot_token)
        print(f"✅ Token saved to {token_file}")
    
    print("\n🚀 Starting enhanced casino bot...")
    print(f"👑 Admin: @{ADMIN_USERNAME}")
    
    application = Application.builder().token(bot_token).build()
    application.add_error_handler(error_handler)
    
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("ask", ask_ai))
    application.add_handler(CommandHandler("slots", slots_command))
    application.add_handler(CommandHandler("dice", dice_command))
    application.add_handler(CommandHandler("coinflip", coinflip_command))
    application.add_handler(CommandHandler("roulette", roulette_command))
    application.add_handler(CommandHandler("jackpot", jackpot_command))
    application.add_handler(CommandHandler("crash", crash_command))
    application.add_handler(CommandHandler("cashout", cashout_command))
    application.add_handler(CommandHandler("balance", balance_command))
    application.add_handler(CommandHandler("daily", daily_command))
    application.add_handler(CommandHandler("top", top_command))
    application.add_handler(CommandHandler("stats", stats_command))
    application.add_handler(CommandHandler("users", users_command))
    application.add_handler(CommandHandler("new", new_chat))
    application.add_handler(CommandHandler("history", show_history))
    application.add_handler(CommandHandler("help", help_command))
    application.add_handler(CommandHandler("give", give_command))
    application.add_handler(CommandHandler("reset", reset_command))
    application.add_handler(CommandHandler("broadcast", broadcast_command))
    application.add_handler(CommandHandler("addcoins", addcoins_command))
    application.add_handler(CommandHandler("admin", admin_panel))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))
    application.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    application.add_handler(CallbackQueryHandler(button_callback))
    
    print("✅ Bot is running! Press Ctrl+C to stop.\n")
    
    try:
        await application.initialize()
        await application.start()
        await application.updater.start_polling(allowed_updates=Update.ALL_TYPES)
        
        stop_event = asyncio.Event()
        
        def signal_handler() -> None:
            stop_event.set()
        
        loop = asyncio.get_running_loop()
        loop.add_signal_handler(signal.SIGINT, signal_handler)
        loop.add_signal_handler(signal.SIGTERM, signal_handler)
        
        await stop_event.wait()
        
    except Exception as e:
        logger.error(f"Error running bot: {e}")
    finally:
        print("\n🛑 Shutting down bot...")
        try:
            await application.updater.stop()
            await application.stop()
            await application.shutdown()
        except:
            pass
        print("👋 Bot stopped successfully!")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\n👋 Bot stopped by user.")
    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
EOF
    
    print_success "Bot script created"
}

main() {
    clear
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     TELEGRAM CASINO BOT WITH OPERA AI - FULL EDITION      ║"
    echo "║                    Admin: @Totoong_bryl_john              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    print_message "Starting setup process..."
    echo ""
    
    check_dependencies
    
    echo ""
    print_message "Creating requirements.txt..."
    create_requirements_file
    
    echo ""
    print_message "Creating bot script..."
    create_bot_script
    
    chmod +x bot.py
    
    echo ""
    print_success "Setup completed successfully!"
    echo ""
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✨ Setup Complete!${NC}"
    echo ""
    print_warning "Please install Python packages manually:"
    echo "  pip install -r requirements.txt"
    echo ""
    print_info "After installation, run the bot with:"
    echo "  python3 bot.py"
    echo ""
    echo -e "${PURPLE}👑 Admin: @Totoong_bryl_john${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

if [ -f "token.txt" ]; then
    print_info "Found existing token file"
fi

main
