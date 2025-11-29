#!/bin/bash

# --- কনফিগারেশন ভ্যারিয়েবলস ---
PRITUNL_PORT="443" # Pritunl Web Admin Port
MONGODB_VERSION="7.0"
OS_VERSION=$(lsb_release -sc)

# --- ১. ক্লিনার ফাংশন (পুরোনো ইনস্টলেশন এবং কনফিগারেশন মুছে ফেলা) ---
cleanup_old_installation() {
    echo "🧹 Checking for existing Pritunl/MongoDB/OpenVPN installations..."
    
    # Pritunl এবং MongoDB সার্ভিস বন্ধ করা
    sudo systemctl stop pritunl 2>/dev/null
    sudo systemctl stop mongod 2>/dev/null
    
    # OpenVPN CE সার্ভিস বন্ধ করা (যদি পুরাতন স্ক্রিপ্ট থেকে থাকে)
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

# --- ৩. প্রয়োজনীয় প্যাকেজ ইনস্টল করা (Prerequisites) ---
echo "⚙️  System update and installing prerequisites..."
sudo apt update -y
sudo apt install -y curl gnupg2 apt-transport-https ca-certificates net-tools ufw

# --- ৪. MongoDB এবং Pritunl রিপোজিটরি যোগ করা ---
echo "📡 Adding MongoDB and Pritunl repositories..."

# MongoDB 7.0 (Pritunl এর জন্য প্রয়োজন)
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
sudo ufw allow $PRITUNL_PORT/tcp # Pritunl Web UI
# OpenVPN ট্র্যাফিকের জন্য পোর্ট (Pritunl নিজেই সেটআপ করবে, তবে সাধারণত 1194 বা 443)
sudo ufw allow 1194/udp
sudo ufw --force enable

# --- ৭. সার্ভিস চালু করা ---
echo "🚀 Starting services..."
sudo systemctl enable mongod pritunl
sudo systemctl start mongod pritunl

# --- ৮. ইনস্টলেশন পরবর্তী ধাপের তথ্য ---
echo "=========================================================="
echo "✅ Pritunl (VPN Admin Panel) Installation Complete!"
echo "----------------------------------------------------------"
# Pritunl Setup Key প্রদর্শন করা
PRITUNL_SETUP_KEY=$(sudo pritunl setup-key)
echo "🔑 Pritunl Setup Key (প্রথম লগইন এর জন্য): $PRITUNL_SETUP_KEY"
echo " "
echo "🌐 পরবর্তী ধাপ:"
echo "   ১. আপনার ব্রাউজারে যান: https://$(curl -4s icanhazip.com):$PRITUNL_PORT"
echo "   ২. উপরের Setup Key টি ব্যবহার করে লগইন করুন।"
echo "   ৩. আপনাকে একটি নতুন ডিফল্ট পাসওয়ার্ড সেট করতে হবে। পাসওয়ার্ডটি নিতে এই কমান্ডটি ব্যবহার করুন:"
echo "      sudo pritunl default-password"
echo "   ৪. অ্যাডমিন প্যানেলে ঢুকে VPN সার্ভার (OpenVPN/WireGuard) এবং ইউজার তৈরি করুন।"
echo "=========================================================="
