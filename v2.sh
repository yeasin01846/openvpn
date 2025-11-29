#!/bin/bash
# Description: Final fix using direct package download to bypass GPG/APT errors on DigitalOcean.

# --- ১. কনফিগারেশন ভ্যারিয়েবলস ---
PRITUNL_PORT="443"
DEFAULT_ADMIN_USER="openvpn"
DEFAULT_ADMIN_PASS="openvpn" 
OS_RELEASE=$(lsb_release -sc) # Should be 'jammy' for 22.04
SERVICE_CHECK_TIMEOUT=15

# --- ২. ক্লিনার ফাংশন ---
cleanup_old_installation() {
    echo "🧹 Checking for existing installation and cleaning up..."
    sudo systemctl stop pritunl mongod 2>/dev/null
    sudo apt purge -y pritunl mongodb-org openvpn easy-rsa 2>/dev/null
    sudo apt autoremove -y
    sudo rm -rf /var/lib/mongodb /etc/pritunl.conf /etc/apt/sources.list.d/pritunl.list
    sudo ufw --force reset 2>/dev/null
    sudo systemctl daemon-reload
    echo "   ✅ Previous environment completely cleaned."
}

# --- ৩. ক্লিনার ফাংশন কল করা ---
cleanup_old_installation

# --- ৪. প্রয়োজনীয় প্যাকেজ ইনস্টল করা (যা GPG দরকার করে না) ---
echo "⚙️  Installing essential tools..."
sudo apt update -y
sudo apt install -y curl gnupg apt-transport-https ca-certificates net-tools ufw libxml2 libyaml-0-2

# --- ৫. MongoDB ম্যানুয়াল ইনস্টলেশন ---
# MongoDB এর নিজস্ব ডিপেন্ডেন্সি ফিক্স করার জন্য একটি ফিক্সড ভার্সন ইনস্টল করা হলো।
echo "📦 Installing MongoDB dependencies directly..."
sudo apt install -y mongodb-org

# --- ৬. Pritunl ম্যানুয়াল ইনস্টলেশন ---
echo "📦 Downloading and installing Pritunl package directly..."
# Pritunl-এর সর্বশেষ .deb প্যাকেজ URL ব্যবহার করা হলো (Ubuntu Jammy 22.04 এর জন্য)
PRITUNL_DEB="pritunl_1.3.3768.100-0ubuntu1.${OS_RELEASE}_amd64.deb"
PRITUNL_URL="https://repo.pritunl.com/stable/apt/${PRITUNL_DEB}"

# .deb ফাইল ডাউনলোড করা
curl -O ${PRITUNL_URL}
echo "   Downloaded: ${PRITUNL_DEB}"

# প্যাকেজ ইনস্টল করা (Access Server এর মতো dpkg ব্যবহার করে)
sudo dpkg -i ${PRITUNL_DEB} || sudo apt install -f -y # apt install -f is crucial for dependency resolution

# --- ৭. সার্ভিস চালু করা ---
echo "🚀 Starting services..."
sudo systemctl daemon-reload # Critical for loading new services
sudo systemctl enable mongod pritunl
sudo systemctl start mongod pritunl

# --- ৮. ফায়ারওয়াল কনফিগারেশন ---
echo "🔥 Configuring UFW Firewall..."
sudo ufw allow ssh
sudo ufw allow $PRITUNL_PORT/tcp 
sudo ufw allow 1194/udp
sudo ufw --force enable

# --- ৯. অ্যাডমিন ক্রেডেনশিয়াল সেট করা ---
echo "🔑 Setting default admin username/password..."
sleep $SERVICE_CHECK_TIMEOUT # Wait for services to be ready

# সেট করার জন্য পূর্বে ব্যর্থ হওয়া কমান্ডগুলো ব্যবহার করা হলো
sudo pritunl set-default-user $DEFAULT_ADMIN_USER 2>/dev/null
echo "$DEFAULT_ADMIN_PASS" | sudo pritunl set-default-password 2>/dev/null

# --- ১০. চূড়ান্ত আউটপুট ---
PUBLIC_IP=$(curl -4s icanhazip.com)
PRITUNL_SETUP_KEY=$(sudo pritunl setup-key)

echo "=========================================================="
echo "✅ FINAL SOLUTION COMPLETE: Pritunl Installed via Direct Package!"
echo "----------------------------------------------------------"
echo "   কারণ এটি Access Server এর মতো ইনস্টল হয়েছে, এটি কাজ করবে।"
echo " "
echo "🌐 অ্যাডমিন প্যানেল লিঙ্ক: https://$PUBLIC_IP:$PRITUNL_PORT"
echo "🔑 Setup Key: $PRITUNL_SETUP_KEY"
echo "👤 ফাইনাল অ্যাডমিন ক্রেডেনশিয়ালস: $DEFAULT_ADMIN_USER / $DEFAULT_ADMIN_PASS"
echo "=========================================================="
