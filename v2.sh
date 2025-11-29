#!/bin/bash

# --- কনফিগারেশন ভ্যারিয়েবলস (স্থির) ---
PORT="1194"
PROTOCOL="udp"
CLIENT_USER="openvpn"
CLIENT_PASS="Easin112233@" 

OPENVPN_DIR="/etc/openvpn/server"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"
AUTH_SCRIPT_DIR="/etc/openvpn/auth"
AUTH_USERS_DB="$AUTH_SCRIPT_DIR/users.db"
UFW_RULES_FILE="/etc/ufw/before.rules"

# --- প্রি-চেক এবং ক্লিনার ফাংশন ---
cleanup_old_installation() {
    echo "🧹 Checking for existing OpenVPN installation..."
    
    # OpenVPN সার্ভিস বন্ধ করা
    if systemctl is-active --quiet openvpn-server@server; then
        echo "   - Stopping existing OpenVPN service."
        sudo systemctl stop openvpn-server@server
        sudo systemctl disable openvpn-server@server
    fi

    # UFW রুলস রিমুভ করা
    echo "   - Cleaning UFW rules and NAT modifications."
    sudo ufw disable 2>/dev/null
    
    # NAT রুলস রিমুভ করা (/etc/ufw/before.rules থেকে)
    if [ -f "$UFW_RULES_FILE" ] && grep -q "*nat" "$UFW_RULES_FILE"; then
        # NAT Block টি সম্পূর্ণরূপে রিমুভ করা হচ্ছে
        sudo sed -i '/^# START OPENVPN RULES/,/^# END OPENVPN RULES/{/^# START OPENVPN RULES/!{/^# END OPENVPN RULES/!d}}' "$UFW_RULES_FILE"
        sudo sed -i '/^# START OPENVPN RULES/,/^# END OPENVPN RULES/d' "$UFW_RULES_FILE"
        # নতুন করে NAT রুল যোগ করার জন্য প্রস্তুত করা 
        sudo sed -i '/^# Rules that should be run before the ufw command/a # START OPENVPN RULES' "$UFW_RULES_FILE"
        sudo sed -i '/^# START OPENVPN RULES/a # END OPENVPN RULES' "$UFW_RULES_FILE"
        # যদি কোনো NAT rule leftover থাকে, সেটি রিমুভ করা
        sudo sed -i '/^:POSTROUTING ACCEPT/d' "$UFW_RULES_FILE"
        sudo sed -i '/^-A POSTROUTING -s 10.8.0.0\/24/d' "$UFW_RULES_FILE"
        sudo sed -i '/^\*nat/d' "$UFW_RULES_FILE"
        sudo sed -i '/^COMMIT/d' "$UFW_RULES_FILE"
        
        # iptables NAT রুল ফ্লাশ করা
        sudo iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -j MASQUERADE 2>/dev/null
        sudo iptables -t nat -F 2>/dev/null
        sudo netfilter-persistent save 2>/dev/null
    fi
    
    # কনফিগারেশন ফাইল ডিরেক্টরি রিমুভ করা
    if [ -d "/etc/openvpn" ]; then
        echo "   - Removing OpenVPN configuration directories."
        sudo rm -rf /etc/openvpn
    fi
    if [ -d "$EASY_RSA_DIR" ]; then
        sudo rm -rf "$EASY_RSA_DIR"
    fi
    
    # প্যাকেজ রিমুভ করা
    echo "   - Removing OpenVPN and related packages."
    sudo apt purge -y openvpn easy-rsa apache2-utils net-tools iptables-persistent 2>/dev/null
    sudo apt autoremove -y
    
    echo "   ✅ Previous installation completely removed."
}

# --- ১. ক্লিনার ফাংশন কল করা ---
cleanup_old_installation

# --- ২. প্রয়োজনীয় প্যাকেজ ইনস্টল করা ---
echo "⚙️  System update and fresh package installation..."
sudo apt update -y
sudo apt install -y openvpn easy-rsa net-tools ufw iptables-persistent apache2-utils

# --- ৩. পাবলিক IP স্বয়ংক্রিয়ভাবে সনাক্ত করা ---
PUBLIC_IP=$(wget -4qO- http://icanhazip.com || curl -4s icanhazip.com)
if [ -z "$PUBLIC_IP" ]; then
    echo "❌ Error: Could not determine public IP address. Exiting."
    exit 1
fi
echo "✅ Detected Public IP: $PUBLIC_IP"

# --- ৪. OpenVPN এবং Easy-RSA ডিরেক্টরি সেটআপ ---
echo "📁 Setting up OpenVPN and Easy-RSA directories..."
sudo mkdir -p "$OPENVPN_DIR"
sudo mkdir -p "$EASY_RSA_DIR"
sudo cp -r /usr/share/easy-rsa/* "$EASY_RSA_DIR"/

# --- ৫. PKI (Public Key Infrastructure) তৈরি করা ---
echo "🔐 Generating PKI: CA, Server Certs, DH parameters..."
cd "$EASY_RSA_DIR"
./easyrsa init-pki
./easyrsa build-ca nopass 
./easyrsa gen-req server nopass
./easyrsa sign-req server server
./easyrsa gen-dh
./easyrsa gen-crl
openvpn --genkey --secret ta.key 

# ফাইলগুলি OpenVPN ডিরেক্টরিতে কপি করা
echo "📦 Copying files to OpenVPN server directory..."
sudo cp pki/ca.crt pki/issued/server.crt pki/private/server.key ta.key "$OPENVPN_DIR"/
sudo cp pki/dh.pem "$OPENVPN_DIR"/
sudo cp pki/crl.pem "$OPENVPN_DIR"/

# --- ৬. ইউজারনেম/পাসওয়ার্ড অথেন্টিকেশন সেটআপ ---
echo "🔑 Setting up Username/Password Authentication for $CLIENT_USER..."
sudo mkdir -p "$AUTH_SCRIPT_DIR"

# ইউজারনেম এবং পাসওয়ার্ড হ্যাশ তৈরি করে DB ফাইলে যোগ করা
echo "$CLIENT_USER:$(echo "$CLIENT_PASS" | openssl passwd -1 -stdin)" | sudo tee "$AUTH_USERS_DB" > /dev/null

# সার্ভার সাইডে অথেন্টিকেশন স্ক্রিপ্ট তৈরি
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

# --- ৭. সার্ভার কনফিগারেশন (.conf) ফাইল তৈরি করা ---
echo "📝 Creating server configuration file: server.conf"
sudo cat > "$OPENVPN_DIR"/server.conf <<EOF
port $PORT
proto $PROTOCOL
dev tun
sndbuf 0
rcvbuf 0
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA256
cipher AES-256-GCM
tls-server
tls-auth ta.key 0
username-as-common-name
plugin /usr/lib/openvpn/openvpn-plugin-auth-pam.so "$AUTH_SCRIPT_DIR/auth.sh" silent
verify-client-cert none 
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1" 
push "dhcp-option DNS 1.0.0.1"
keepalive 10 120
persist-key
persist-tun
status openvpn-status.log
verb 3
crl-verify crl.pem
explicit-exit-notify
EOF

# --- ৮. ক্লায়েন্ট কনফিগারেশন (.ovpn) ফাইল তৈরি করা ---
echo "👤 Generating client config: $CLIENT_USER.ovpn"
# ক্লায়েন্ট ফাইলে স্বয়ংক্রিয়ভাবে পাবলিক IP ব্যবহার করা হচ্ছে
sudo cat > /root/"$CLIENT_USER".ovpn <<EOF
client
dev tun
proto $PROTOCOL
remote $PUBLIC_IP $PORT 
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
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

# --- ৯. নেটওয়ার্ক কনফিগারেশন (IP Forwarding) ---
echo "📡 Enabling IP Forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
# যদি ফাইলে না থাকে, তবে যোগ করা
IP_FORWARD_CONF="/etc/sysctl.conf"
if ! grep -q "net.ipv4.ip_forward = 1" "$IP_FORWARD_CONF"; then
    echo "net.ipv4.ip_forward = 1" | sudo tee -a "$IP_FORWARD_CONF"
fi

# --- ১০. ফায়ারওয়াল সেটআপ (UFW এবং NAT) ---
echo "🔥 Configuring Firewall and NAT rules..."
NET_ADAPTER=$(ip route | grep default | awk '{print $5}' | head -n 1)

# UFW-এর before.rules-এ NAT রুলস যোগ করা
echo "Adding NAT rules to UFW before.rules..."

# নতুন করে NAT ব্লক যোগ করা
sudo sed -i '/# END OPENVPN RULES/i\
*nat\
:POSTROUTING ACCEPT [0:0]\
-A POSTROUTING -s 10.8.0.0/24 -o '"$NET_ADAPTER"' -j MASQUERADE\
COMMIT' "$UFW_RULES_FILE"

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow "$PORT/$PROTOCOL"
sudo ufw --force enable

# --- ১১. সার্ভিস স্টার্ট করা ---
echo "🚀 Starting OpenVPN service..."
sudo systemctl daemon-reload
sudo systemctl enable openvpn-server@server
sudo systemctl restart openvpn-server@server

echo "=========================================================="
echo "✅ One-Click OpenVPN Setup Complete! (Auto-Cleaned & Fresh)"
echo "----------------------------------------------------------"
echo "   সার্ভার IP: $PUBLIC_IP"
echo "   ক্লায়েন্ট ফাইল: /root/$CLIENT_USER.ovpn"
echo "   ইউজারনেম: $CLIENT_USER"
echo "   পাসওয়ার্ড: $CLIENT_PASS"
echo "   "
echo "   **পরবর্তী ধাপ:** ক্লায়েন্ট ফাইল ডাউনলোড করুন এবং ফাইলটির ভেতরে"
echo "   'remote $PUBLIC_IP $PORT' লাইনটি পরিবর্তন করে আপনার হোস্টনেম (যেমন: 'remote vpn.mydomain.com $PORT') দিয়ে দিন।"
echo "=========================================================="
