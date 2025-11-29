#!/bin/bash

# --- কনফিগারেশন ভ্যারিয়েবলস ---
PRITUNL_PORT="443" # Pritunl Web Admin Port
MONGODB_VERSION="7.0"
OS_VERSION=$(lsb_release -sc)

# --- নতুন ডিফল্ট ক্রেডেনশিয়ালস ---
DEFAULT_ADMIN_USER="openvpn"
DEFAULT_ADMIN_PASS="openvpn" 

# --- ১. ক্লিনার ফাংশন (পুরোনো ইনস্টলেশন এবং কনফিগারেশন মুছে ফেলা) ---
cleanup_old_installation() {
    echo "🧹 Checking for existing Pritunl/MongoDB/OpenVPN installations..."
    
    # সার্ভিস বন্ধ করা
    sudo systemctl stop pritunl 2>/dev/null
    sudo systemctl stop mongod 2>/dev/null
    sudo systemctl stop openvpn-server@server 2>/dev/null
    
    # প্যাকেজ রিমুভ করা
    echo "   - Removing old packages and configurations..."
    sudo apt purge -y pritunl mongodb-org openvpn easy-rsa apache2-utils 2>/dev/null
    sudo apt autoremove -y 2>/dev/null
    
    # MongoDB ডেটা এবং Pritunl কনফিগারেশন মুছে ফেলা
    sudo rm -rf /var/lib/mongodb 2>/dev/null
    sudo rm -rf /etc/pritunl.conf 2>/dev/null
    
    # রিপোজিটরি ফাইল পরিষ্কার করা
    sudo rm -f /etc/apt/sources.list.d/pritunl.list 2>/dev/null
    sudo rm -f /etc/apt/sources.list.d/mongodb-org-*.list 2>/dev/null

    # UFW ডিফল্ট রুলস সেট করা
    sudo ufw --force reset 2>/dev/null

    echo "   ✅ Previous installation completely removed. Starting fresh setup."
}

# --- ২. ক্লিনার ফাংশন কল করা ---
cleanup_old_installation

# --- ৩. প্রয়োজনীয় প্যাকেজ ইনস্টল করা ---
echo "⚙️  System update and installing prerequisites..."
sudo apt update -y
sudo apt install -y curl gnupg2 apt-transport-https ca-certificates net-tools ufw

# --- ৪. MongoDB এবং Pritunl রিপোজিটরি যোগ করা ---
echo "📡 Adding MongoDB and Pritunl repositories..."

# MongoDB 7.0
echo "deb https://repo.mongodb.org/apt/ubuntu $OS_VERSION/mongodb-org/$MONGODB_VERSION multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
wget -qO- https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/mongodb-org-7.0.gpg >/dev/null

# Pritunl Repository
echo "deb https://repo.pritunl.com/stable/apt $OS_VERSION main" | sudo tee /etc/apt/sources.list.d/pritunl.list
wget -qO- https://raw.githubusercontent.com/pritunl/pritunl-repo/master/key.gpg | sudo gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/pritunl.gpg >/dev/null

# --- ৫. মূল প্যাকেজ ইনস্টল করা ---
echo "📦 Installing Pritunl and MongoDB..."
sudo apt update -y
sudo apt install -y pritunl mongodb-org

# --- ৬. ফায়ারওয়াল কনফিগারেশন ---
echo "🔥 Configuring UFW Firewall..."
sudo ufw allow ssh
sudo ufw allow $PRITUNL_PORT/tcp 
sudo ufw allow 1194/udp
sudo ufw --force enable

# --- ৭. সার্ভিস চালু করা ---
echo "🚀 Starting services..."
sudo systemctl enable mongod pritunl
sudo systemctl start mongod pritunl

# সার্ভিস সম্পূর্ণভাবে চালু হওয়ার জন্য অপেক্ষা করা
sleep 10 

# --- ৮. স্বয়ংক্রিয় অ্যাডমিন ক্রেডেনশিয়াল সেট করা (নতুন ধাপ) ---
echo "🔑 Setting default admin username/password to $DEFAULT_ADMIN_USER..."
# ডিফল্ট অ্যাডমিন ইউজারনেম এবং পাসওয়ার্ড সেট করা
sudo pritunl set-default-user $DEFAULT_ADMIN_USER
echo "$DEFAULT_ADMIN_PASS" | sudo pritunl set-default-password

# --- ৯. ইনস্টলেশন পরবর্তী ধাপের তথ্য ---
PUBLIC_IP=$(curl -4s icanhazip.com)
PRITUNL_SETUP_KEY=$(sudo pritunl setup-key)

echo "=========================================================="
echo "✅ Pritunl (VPN Admin Panel) Installation Complete! (Auto-Configured)"
echo "----------------------------------------------------------"
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
