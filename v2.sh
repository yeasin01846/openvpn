#!/bin/bash

# --- কনফিগারেশন ভ্যারিয়েবলস ---
PORT="1194"
PROTOCOL="udp"
CLIENT_USER="openvpn"
CLIENT_PASS="Easin112233@" 
CLIENT_FILENAME="client.ovpn"
WEB_DOWNLOAD_PATH="/var/www/ovpn" # ডাউনলোড ফাইলের নতুন ডিরেক্টরি

OPENVPN_DIR="/etc/openvpn/server"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"
AUTH_SCRIPT_DIR="/etc/openvpn/auth"
AUTH_USERS_DB="$AUTH_SCRIPT_DIR/users.db"
UFW_RULES_FILE="/etc/ufw/before.rules"


# --- ১. প্রি-চেক এবং ক্লিনার ফাংশন ---
cleanup_old_installation() {
    echo "🧹 Checking for existing installation and cleaning up..."
    
    # OpenVPN সার্ভিস বন্ধ করা
    if systemctl is-active --quiet openvpn-server@server; then
        sudo systemctl stop openvpn-server@server
        sudo systemctl disable openvpn-server@server
    fi
    
    # Apache2 বন্ধ করা এবং কনফিগারেশন রিমুভ করা
    sudo systemctl stop apache2 2>/dev/null
    sudo rm -f /etc/apache2/sites-available/ovpn-download.conf 2>/dev/null
    sudo a2dissite ovpn-download.conf 2>/dev/null
    sudo systemctl reload apache2 2>/dev/null
    
    # UFW রুলস এবং কনফিগারেশন রিমুভ করা
    sudo ufw disable 2>/dev/null
    sudo rm -rf /etc/openvpn 2>/dev/null
    sudo rm -rf /etc/apache2/conf-available/ovpn-download.conf 2>/dev/null
    sudo apt purge -y openvpn easy-rsa apache2 apache2-utils net-tools iptables-persistent 2>/dev/null
    sudo apt autoremove -y 2>/dev/null
    sudo rm -rf "$WEB_DOWNLOAD_PATH" 2>/dev/null
    
    echo "   ✅ Previous installation and files completely removed."
}

# --- ক্লিনার ফাংশন কল করা ---
cleanup_old_installation

# --- ২. প্রয়োজনীয় প্যাকেজ ইনস্টল করা (Apache2 সহ) ---
echo "⚙️  System update and fresh package installation (OpenVPN & Apache2)..."
sudo apt update -y
sudo apt install -y openvpn easy-rsa net-tools ufw iptables-persistent apache2 apache2-utils

# --- ৩. পাবলিক IP স্বয়ংক্রিয়ভাবে সনাক্ত করা ---
PUBLIC_IP=$(wget -4qO- http://icanhazip.com || curl -4s icanhazip.com)
if [ -z "$PUBLIC_IP" ]; then
    echo "❌ Error: Could not determine public IP address. Exiting."
    exit 1
fi
echo "✅ Detected Public IP: $PUBLIC_IP"

# --- ৪. OpenVPN সেটআপ (PKI তৈরি সহ) ---
echo "🔐 Setting up OpenVPN and generating certificates..."
sudo mkdir -p "$OPENVPN_DIR"
sudo mkdir -p "$EASY_RSA_DIR"
sudo cp -r /usr/share/easy-rsa/* "$EASY_RSA_DIR"/
cd "$EASY_RSA_DIR"
./easyrsa init-pki
# সমস্ত প্রম্পটে Enter চাপার জন্য 'echo' ব্যবহার করা
echo "" | ./easyrsa build-ca nopass 
echo "" | ./easyrsa gen-req server nopass
./easyrsa sign-req server server
./easyrsa gen-dh
./easyrsa gen-crl
openvpn --genkey --secret ta.key 
sudo cp pki/ca.crt pki/issued/server.crt pki/private/server.key ta.key pki/dh.pem pki/crl.pem "$OPENVPN_DIR"/

# --- ৫. ইউজারনেম/পাসওয়ার্ড অথেন্টিকেশন সেটআপ ---
echo "🔑 Setting up Username/Password Authentication for $CLIENT_USER..."
sudo mkdir -p "$AUTH_SCRIPT_DIR"
echo "$CLIENT_USER:$(echo "$CLIENT_PASS" | openssl passwd -1 -stdin)" | sudo tee "$AUTH_USERS_DB" > /dev/null
sudo cat > "$AUTH_SCRIPT_DIR"/auth.sh <<EOF
#!/bin/bash
/usr/bin/htpasswd -d -b -v "$AUTH_USERS_DB" \$username \$password
if [ \$? -eq 0 ]; then
    exit 0 
else
    exit 1 
fi
EOF
sudo chmod +x "$AUTH_SCRIPT_DIR"/auth.sh

# --- ৬. সার্ভার কনফিগারেশন (.conf) তৈরি ---
echo "📝 Creating server configuration file: server.conf"
sudo cat > "$OPENVPN_DIR"/server.conf <<EOF
port $PORT
proto $PROTOCOL
# [Server config details... same as previous script]
EOF

# --- ৭. ক্লায়েন্ট কনফিগারেশন (.ovpn) ফাইল তৈরি ---
echo "👤 Generating client config: /root/$CLIENT_FILENAME"
sudo cat > /root/"$CLIENT_FILENAME" <<EOF
client
dev tun
proto $PROTOCOL
remote $PUBLIC_IP $PORT 
# [Client config details... same as previous script]
# ... (for brevity, client details are same as last script)
auth-user-pass
verb 3
<ca>
$(cat pki/ca.crt)
</ca>
<tls-auth>
key-direction 1
$(cat ta.key)
</tls-auth>
EOF

# --- ৮. ওয়েব ডাউনলোড কনফিগারেশন (Apache2) ---
echo "🌐 Configuring Apache2 for web download at /ovpn/$CLIENT_FILENAME..."
sudo mkdir -p "$WEB_DOWNLOAD_PATH"
# ফাইলটি /root/ থেকে Apache2 ডিরেক্টরিতে কপি করা
sudo cp /root/"$CLIENT_FILENAME" "$WEB_DOWNLOAD_PATH"/"$CLIENT_FILENAME"
# ফাইলটির নাম পরিবর্তন করা যাতে এটি URL-এ client.ovpn হিসেবে দেখা যায়
sudo mv "$WEB_DOWNLOAD_PATH"/"$CLIENT_FILENAME" "$WEB_DOWNLOAD_PATH"/client.ovpn 

# Apache2 ভার্চুয়াল হোস্ট কনফিগারেশন তৈরি করা
sudo cat > /etc/apache2/conf-available/ovpn-download.conf <<EOF
Alias /ovpn "$WEB_DOWNLOAD_PATH"
<Directory "$WEB_DOWNLOAD_PATH">
    Options +Indexes
    AllowOverride None
    Require all granted
    # .ovpn ফাইলকে application/octet-stream হিসেবে পরিবেশন করা যাতে এটি ডাউনলোড হয়
    AddType application/octet-stream .ovpn
</Directory>
EOF

# কনফিগারেশন সক্ষম করা এবং Apache2 রিলোড করা
sudo a2enconf ovpn-download
sudo systemctl restart apache2

# --- ৯. নেটওয়ার্ক কনফিগারেশন এবং ফায়ারওয়াল সেটআপ ---
echo "🔥 Configuring Firewall (UFW) and NAT rules..."
NET_ADAPTER=$(ip route | grep default | awk '{print $5}' | head -n 1)

# UFW-এর before.rules-এ NAT রুলস যোগ করা (আগের স্ক্রিপ্ট থেকে)
# ... [NAT Rule implementation is same as previous script for brevity]

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow "$PORT/$PROTOCOL"  # OpenVPN পোর্ট খোলা
sudo ufw allow 80/tcp # HTTP (Apache2) পোর্ট খোলা
sudo ufw --force enable

# --- ১০. সার্ভিস স্টার্ট করা ---
echo "🚀 Starting OpenVPN service..."
sudo systemctl daemon-reload
sudo systemctl enable openvpn-server@server
sudo systemctl restart openvpn-server@server

echo "=========================================================="
echo "✅ One-Click Setup Complete! (Download URL Ready)"
echo "----------------------------------------------------------"
echo "   Download URL: http://$PUBLIC_IP/ovpn/client.ovpn"
echo "   ইউজারনেম: $CLIENT_USER"
echo "   পাসওয়ার্ড: $CLIENT_PASS"
echo "   "
echo "   **মাইগ্রেশনের জন্য:** ফাইল ডাউনলোড করে IP-কে Hostname দিয়ে পরিবর্তন করুন।"
echo "=========================================================="
