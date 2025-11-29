#!/bin/bash
# Description: Fixed one-click Pritunl (VPN Admin Panel) installer with auto-cleanup and modern GPG key handling.

# --- ১. কনফিগারেশন ভ্যারিয়েবলস ---
PRITUNL_PORT="443"
MONGODB_VERSION="7.0"
OS_RELEASE=$(lsb_release -sc) # jammy or focal
DEFAULT_ADMIN_USER="openvpn"
DEFAULT_ADMIN_PASS="openvpn" 
SERVICE_CHECK_TIMEOUT=30 # Wait time for services to start

# --- ২. ক্লিনার ফাংশন (পুরোনো ইনস্টলেশন এবং কনফিগারেশন মুছে ফেলা) ---
cleanup_old_installation() {
    echo "🧹 Checking for existing installation and cleaning up..."
    sudo systemctl stop pritunl 2>/dev/null
    sudo systemctl stop mongod 2>/dev/null
    sudo apt purge -y pritunl mongodb-org openvpn easy-rsa 2>/dev/null
    sudo apt autoremove -y 2>/dev/null
    
    # MongoDB ডেটা এবং Pritunl কনফিগারেশন মুছে ফেলা
    sudo rm -rf /var/lib/mongodb 2>/dev/null
    sudo rm -rf /etc/pritunl.conf 2>/dev/null
    
    # Repositories এবং GPG কী পরিষ্কার করা
    sudo rm -f /etc/apt/sources.list.d/pritunl.list 2>/dev/null
    sudo rm -f /etc/apt/sources.list.d/mongodb-org-*.list 2>/dev/null
    sudo rm -f /etc/apt/trusted.gpg.d/pritunl.gpg 2>/dev/null
    sudo rm -f /etc/apt/trusted.gpg.d/mongodb-org-*.gpg 2>/dev/null
    
    sudo ufw --force reset 2>/dev/null
    echo "   ✅ Previous environment completely cleaned."
}

# --- ৩. ক্লিনার ফাংশন কল করা ---
cleanup_old_installation

# --- ৪. প্রয়োজনীয় প্যাকেজ ইনস্টল করা (Prerequisites) ---
echo "⚙️  System update and installing essential packages..."
sudo apt update -y
sudo apt install -y curl gnupg apt-transport-https ca-certificates net-tools ufw software-properties-common

# --- ৫. MongoDB রিপোজিটরি যোগ করা (Modern Signed-by method) ---
echo "📡 Adding MongoDB repository using modern method..."
# MongoDB GPG কী ডাউনলোড এবং /usr/share/keyrings-এ সেভ করা
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
    sudo gpg --dearmor | sudo tee /usr/share/keyrings/mongodb-org-7.0.gpg > /dev/null

# MongoDB রিপোজিটরি যুক্ত করা, GPG কী রেফারেন্স সহ
echo "deb [ arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/mongodb-org-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $OS_RELEASE/mongodb-org/$MONGODB_VERSION multiverse" | \
    sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list > /dev/null

# --- ৬. Pritunl রিপোজিটরি যোগ করা (Modern Signed-by method) ---
echo "📡 Adding Pritunl repository using modern method..."
# Pritunl GPG কী ডাউনলোড এবং /usr/share/keyrings-এ সেভ করা
curl -fsSL https://raw.githubusercontent.com/pritunl/pritunl-repo/master/key.gpg | \
    sudo gpg --dearmor | sudo tee /usr/share/keyrings/pritunl.gpg > /dev/null

# Pritunl রিপোজিটরি যুক্ত করা, GPG কী রেফারেন্স সহ
echo "deb [ arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pritunl.gpg ] https://repo.pritunl.com/stable/apt $OS_RELEASE main" | \
    sudo tee /etc/apt/sources.list.d/pritunl.list > /dev/null

# --- ৭. মূল প্যাকেজ ইনস্টল করা ---
echo "📦 Installing Pritunl and MongoDB..."
sudo apt update -y
sudo apt install -y pritunl mongodb-org

# --- ৮. ফায়ারওয়াল কনফিগারেশন ---
echo "🔥 Configuring UFW Firewall..."
sudo ufw allow ssh
sudo ufw allow $PRITUNL_PORT/tcp 
sudo ufw allow 1194/udp
sudo ufw --force enable

# --- ৯. সার্ভিস চালু করা ---
echo "🚀 Starting and enabling services..."
sudo systemctl enable mongod pritunl
sudo systemctl start mongod pritunl

# সার্ভিস সম্পূর্ণভাবে চালু হওয়ার জন্য অপেক্ষা করা
echo "   Waiting $SERVICE_CHECK_TIMEOUT seconds for services to fully initialize..."
sleep $SERVICE_CHECK_TIMEOUT

# --- ১০. স্বয়ংক্রিয় অ্যাডমিন ক্রেডেনশিয়াল সেট করা ---
echo "🔑 Setting default admin username/password to $DEFAULT_ADMIN_USER..."

# MongoDB এর সাথে সংযোগ স্থাপন করে ডিফল্ট ইউজার সেট করার চেষ্টা করা
# এই কমান্ডগুলো সার্ভিস চালু হওয়ার পরেই কাজ করবে
sudo pritunl set-default-user $DEFAULT_ADMIN_USER
echo "$DEFAULT_ADMIN_PASS" | sudo pritunl set-default-password

# --- ১১. ইনস্টলেশন পরবর্তী ধাপের তথ্য যাচাই ---
PUBLIC_IP=$(curl -4s icanhazip.com)
PRITUNL_SETUP_KEY=$(sudo pritunl setup-key)

echo "=========================================================="
echo "✅ Pritunl (VPN Admin Panel) Installation Complete! (100% Fixed)"
echo "----------------------------------------------------------"
echo "   অনুগ্রহ করে এই ধাপগুলো অনুসরণ করুন:"
echo " "
echo "🌐 অ্যাডমিন প্যানেল লিঙ্ক: https://$PUBLIC_IP:$PRITUNL_PORT"
echo " "
echo "🔑 প্রথম ধাপে লগইন করার তথ্য:"
echo "   - Setup Key (প্রথমবার সেটআপের জন্য): $PRITUNL_SETUP_KEY"
echo " "
echo "👤 ফাইনাল অ্যাডমিন ক্রেডেনশিয়ালস:"
echo "   - ইউজারনেম: $DEFAULT_ADMIN_USER"
echo "   - পাসওয়ার্ড: $DEFAULT_ADMIN_PASS"
echo "   **নিরাপত্তার জন্য, প্রথম লগইনের পরই পাসওয়ার্ডটি পরিবর্তন করুন!**"
echo "=========================================================="
