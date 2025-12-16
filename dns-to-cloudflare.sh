#!/bin/bash

# dig から Cloudflare にインポート可能な BIND 形式のゾーンファイルを生成
# 使用法: ./dns-to-cloudflare.sh example.com

set -e

if [ -z "$1" ]; then
    echo "使用法: $0 <ドメイン名>"
    echo "例: $0 example.com"
    exit 1
fi

DOMAIN="$1"
OUTPUT_FILE="${DOMAIN}.zone"
DATE=$(date +%Y%m%d)

echo "ドメイン: $DOMAIN のDNSレコードを取得中..."
echo ""

# ゾーンファイルのヘッダーを作成
cat > "$OUTPUT_FILE" << EOF
; Zone file for $DOMAIN
; Generated on $(date)
; Import this file to Cloudflare DNS
;
\$ORIGIN $DOMAIN.
\$TTL 3600

EOF

# レコードを追加する関数
add_records() {
    local NAME="$1"
    local TYPE="$2"
    local LABEL="$3"
    
    RECORDS=$(dig +noall +answer "$NAME" "$TYPE" 2>/dev/null | grep -v "^;" || true)
    
    if [ -n "$RECORDS" ]; then
        echo "; $LABEL" >> "$OUTPUT_FILE"
        echo "$RECORDS" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        return 0
    fi
    return 1
}

# ===========================================
# メインドメインのレコード
# ===========================================
echo "[メインドメイン]"

# 基本レコードタイプ
RECORD_TYPES="A AAAA MX TXT CNAME NS CAA SRV"
for TYPE in $RECORD_TYPES; do
    printf "  %-10s ... " "$TYPE"
    if add_records "$DOMAIN" "$TYPE" "$TYPE Records"; then
        echo "✓"
    else
        echo "-"
    fi
done

# 追加レコードタイプ
EXTRA_TYPES="NAPTR TLSA SSHFP LOC HTTPS SVCB"
for TYPE in $EXTRA_TYPES; do
    printf "  %-10s ... " "$TYPE"
    if add_records "$DOMAIN" "$TYPE" "$TYPE Records"; then
        echo "✓"
    else
        echo "-"
    fi
done

# ===========================================
# サブドメイン検出
# ===========================================
echo ""
echo "[サブドメイン検出]"

DETECTED_SUBS=""

# ワイルドカードDNS検出（ランダムなサブドメインで確認）
RANDOM_SUB="xyzzy-nonexistent-$(date +%s)"
WILDCARD_IP=$(dig +short +time=2 +tries=1 "${RANDOM_SUB}.$DOMAIN" A 2>/dev/null | head -1 || true)
if [ -n "$WILDCARD_IP" ]; then
    echo "  ⚠ ワイルドカードDNS検出: *.$DOMAIN → $WILDCARD_IP"
    echo "    辞書スキャンはスキップします（誤検出防止）"
    HAS_WILDCARD=true
else
    HAS_WILDCARD=false
fi
echo ""

# 1. Certificate Transparency (crt.sh)
echo "  [1/4] crt.sh (Certificate Transparency)..."
CT_SUBS=$(curl -s --max-time 30 "https://crt.sh/?q=%25.$DOMAIN&output=json" 2>/dev/null | \
    grep -oP '"name_value"\s*:\s*"\K[^"]+' | \
    sed 's/\*\.//g' | \
    grep -v "^$DOMAIN$" | \
    grep -E "^[^.]+\.$DOMAIN$" | \
    sed "s/\.$DOMAIN$//" | \
    sort -u 2>/dev/null || true)
if [ -n "$CT_SUBS" ]; then
    CT_COUNT=$(echo "$CT_SUBS" | wc -l)
    echo "        → $CT_COUNT 件検出"
    DETECTED_SUBS="$DETECTED_SUBS"$'\n'"$CT_SUBS"
else
    echo "        → 0 件"
fi

# 2. DNSDumpster API (hackertarget)
echo "  [2/4] HackerTarget..."
HT_SUBS=$(curl -s --max-time 30 "https://api.hackertarget.com/hostsearch/?q=$DOMAIN" 2>/dev/null | \
    grep -v "error" | \
    cut -d',' -f1 | \
    grep -E "^[^.]+\.$DOMAIN$" | \
    sed "s/\.$DOMAIN$//" | \
    sort -u 2>/dev/null || true)
if [ -n "$HT_SUBS" ]; then
    HT_COUNT=$(echo "$HT_SUBS" | wc -l)
    echo "        → $HT_COUNT 件検出"
    DETECTED_SUBS="$DETECTED_SUBS"$'\n'"$HT_SUBS"
else
    echo "        → 0 件"
fi

# 3. DNS 共通サブドメイン辞書（ワイルドカードがない場合のみ）
echo "  [3/4] 共通サブドメイン辞書..."
if $HAS_WILDCARD; then
    echo "        → スキップ（ワイルドカード検出済み）"
else
    COMMON_SUBS="www mail ftp smtp pop pop3 imap webmail email mx mx1 mx2 mx3 ns ns1 ns2 ns3 dns dns1 dns2 api api2 cdn static assets img images media files download uploads blog news shop store cart secure portal admin administrator cpanel whm plesk panel dashboard manage app apps mobile m dev develop development stage staging test testing qa uat demo preview beta prod production live web www2 www3 old new backup bak dr vpn remote access gateway gw proxy cache lb load edge node server srv db database sql mysql postgres redis mongo elastic search es kafka queue mq rabbit nats ldap ad auth sso login signin oauth oidc cas saml identity id idp connect link go git gitlab github bitbucket svn repo code ci cd jenkins travis circle drone build deploy release artifact nexus maven npm registry docker k8s kube kubernetes container cloud aws azure gcp ibm oracle alibaba storage s3 blob backup archive log logs logging monitor monitoring metrics grafana kibana splunk alert alerts status health check ping trace apm sentry error errors report reports analytics stats statistics track tracking pixel ad ads adserver marketing campaign crm sales support help desk ticket tickets service services helpdesk zendesk freshdesk intercom chat bot chatbot slack teams discord community forum discuss board wiki docs documentation doc api-docs swagger redoc spec reference guide kb knowledge internal intranet extranet staff employee hr payroll finance billing invoice pay payment payments checkout cart order orders ship shipping track delivery fulfillment inventory erp sap oracle netsuite calendar meet meeting zoom webex teams video conference call voice voip sip pbx phone tel telephony fax print printer scan scanner iot device devices sensor sensors edge gateway hub home office remote work wfh guest visitor public private secure ssl tls cert certs certificate pki ca root intermediate ocsp crl"

    DICT_FOUND=""
    for SUB in $COMMON_SUBS; do
        # 高速チェック: A レコードのみ
        if dig +short +time=1 +tries=1 "${SUB}.$DOMAIN" A 2>/dev/null | grep -q "^[0-9]"; then
            DICT_FOUND="$DICT_FOUND $SUB"
        fi
    done
    if [ -n "$DICT_FOUND" ]; then
        DICT_COUNT=$(echo "$DICT_FOUND" | wc -w)
        echo "        → $DICT_COUNT 件検出"
        DETECTED_SUBS="$DETECTED_SUBS"$'\n'"$(echo $DICT_FOUND | tr ' ' '\n')"
    else
        echo "        → 0 件"
    fi
fi

# 4. MX/NS から推測
echo "  [4/4] MX/NSレコードから推測..."
MX_HOSTS=$(dig +short "$DOMAIN" MX 2>/dev/null | awk '{print $2}' | sed 's/\.$//' | grep "$DOMAIN$" | sed "s/\.$DOMAIN$//" || true)
NS_HOSTS=$(dig +short "$DOMAIN" NS 2>/dev/null | sed 's/\.$//' | grep "$DOMAIN$" | sed "s/\.$DOMAIN$//" || true)
INFERRED="$MX_HOSTS"$'\n'"$NS_HOSTS"
INFERRED=$(echo "$INFERRED" | grep -v "^$" | sort -u || true)
if [ -n "$INFERRED" ]; then
    INF_COUNT=$(echo "$INFERRED" | wc -l)
    echo "        → $INF_COUNT 件検出"
    DETECTED_SUBS="$DETECTED_SUBS"$'\n'"$INFERRED"
else
    echo "        → 0 件"
fi

# 重複を除去してソート
ALL_SUBS=$(echo "$DETECTED_SUBS" | grep -v "^$" | sort -u)
TOTAL_COUNT=$(echo "$ALL_SUBS" | grep -v "^$" | wc -l)
echo ""
echo "  合計: $TOTAL_COUNT 件のユニークなサブドメインを検出"
echo ""

# 検出されたサブドメインのDNSレコードを取得
echo "[サブドメインのレコード取得]"
SUB_FOUND=0
for SUB in $ALL_SUBS; do
    [ -z "$SUB" ] && continue
    
    # ワイルドカードがある場合、ワイルドカードIPと同じなら実際のレコードか確認
    if $HAS_WILDCARD; then
        SUB_IP=$(dig +short +time=1 +tries=1 "${SUB}.$DOMAIN" A 2>/dev/null | head -1 || true)
        if [ "$SUB_IP" = "$WILDCARD_IP" ]; then
            # CNAMEがあるか確認（ワイルドカードでない可能性）
            SUB_CNAME=$(dig +short +time=1 +tries=1 "${SUB}.$DOMAIN" CNAME 2>/dev/null | head -1 || true)
            if [ -z "$SUB_CNAME" ]; then
                # CT/HackerTargetで検出されたものはワイルドカードでも記録
                if echo "$CT_SUBS $HT_SUBS" | grep -qw "$SUB"; then
                    : # 続行
                else
                    continue  # スキップ
                fi
            fi
        fi
    fi
    
    FOUND=false
    for TYPE in A AAAA CNAME; do
        if add_records "${SUB}.$DOMAIN" "$TYPE" "${SUB} subdomain ($TYPE)"; then
            FOUND=true
        fi
    done
    if $FOUND; then
        printf "  %-30s ... ✓\n" "$SUB"
        ((SUB_FOUND++)) || true
    fi
done
echo "  レコード取得: $SUB_FOUND 件"

# ワイルドカード
echo ""
printf "  %-30s ... " "* (ワイルドカード)"
if add_records "*.$DOMAIN" "A" "Wildcard subdomain (A)" || \
   add_records "*.$DOMAIN" "AAAA" "Wildcard subdomain (AAAA)" || \
   add_records "*.$DOMAIN" "CNAME" "Wildcard subdomain (CNAME)"; then
    echo "✓"
else
    echo "-"
fi

# ===========================================
# メール関連レコード
# ===========================================
echo ""
echo "[メール認証]"

# SPF（TXTに含まれるが明示的に確認）
printf "  %-12s ... " "SPF"
if grep -q "v=spf1" "$OUTPUT_FILE" 2>/dev/null; then
    echo "✓ (TXTに含まれる)"
else
    echo "-"
fi

# DMARC
printf "  %-12s ... " "DMARC"
if add_records "_dmarc.$DOMAIN" "TXT" "DMARC Record"; then
    echo "✓"
else
    echo "-"
fi

# DKIM（一般的なセレクタ）
DKIM_SELECTORS="default google dkim mail k1 k2 s1 s2 selector1 selector2 mandrill mxvault protonmail zoho sendgrid mailchimp amazonses postmark sparkpost mailgun brevo sendinblue hubspot salesforce"

echo "  DKIM セレクタを確認中..."
for SELECTOR in $DKIM_SELECTORS; do
    if add_records "${SELECTOR}._domainkey.$DOMAIN" "TXT" "DKIM Record ($SELECTOR)"; then
        printf "    %-20s ... ✓\n" "$SELECTOR"
    fi
    # CNAME形式のDKIMも確認
    if add_records "${SELECTOR}._domainkey.$DOMAIN" "CNAME" "DKIM CNAME ($SELECTOR)"; then
        printf "    %-20s ... ✓ (CNAME)\n" "$SELECTOR"
    fi
done

# MTA-STS
printf "  %-12s ... " "MTA-STS"
if add_records "_mta-sts.$DOMAIN" "TXT" "MTA-STS Record"; then
    echo "✓"
else
    echo "-"
fi

# MTA-STS ポリシーホスト
printf "  %-12s ... " "mta-sts host"
if add_records "mta-sts.$DOMAIN" "A" "MTA-STS Host (A)" || \
   add_records "mta-sts.$DOMAIN" "AAAA" "MTA-STS Host (AAAA)" || \
   add_records "mta-sts.$DOMAIN" "CNAME" "MTA-STS Host (CNAME)"; then
    echo "✓"
else
    echo "-"
fi

# SMTP TLS Reporting
printf "  %-12s ... " "TLS-RPT"
if add_records "_smtp._tls.$DOMAIN" "TXT" "SMTP TLS Reporting"; then
    echo "✓"
else
    echo "-"
fi

# BIMI
printf "  %-12s ... " "BIMI"
if add_records "default._bimi.$DOMAIN" "TXT" "BIMI Record"; then
    echo "✓"
else
    echo "-"
fi

# ADSP (Author Domain Signing Practices) - 非推奨だが移行時に必要な場合あり
printf "  %-12s ... " "ADSP"
if add_records "_adsp._domainkey.$DOMAIN" "TXT" "ADSP Record"; then
    echo "✓"
else
    echo "-"
fi

# ===========================================
# メール自動設定
# ===========================================
echo ""
echo "[メール自動設定]"

# Autodiscover (Microsoft/Outlook)
printf "  %-12s ... " "autodiscover"
if add_records "autodiscover.$DOMAIN" "CNAME" "Autodiscover (Outlook)" || \
   add_records "autodiscover.$DOMAIN" "A" "Autodiscover (Outlook)"; then
    echo "✓"
else
    echo "-"
fi

# Autodiscover SRV
printf "  %-12s ... " "autodiscover SRV"
if add_records "_autodiscover._tcp.$DOMAIN" "SRV" "Autodiscover SRV"; then
    echo "✓"
else
    echo "-"
fi

# Autoconfig (Mozilla/Thunderbird)
printf "  %-12s ... " "autoconfig"
if add_records "autoconfig.$DOMAIN" "CNAME" "Autoconfig (Thunderbird)" || \
   add_records "autoconfig.$DOMAIN" "A" "Autoconfig (Thunderbird)"; then
    echo "✓"
else
    echo "-"
fi

# Exchange/Microsoft 365 SRV records
MS_SRV_RECORDS="_sip._tls _sipfederationtls._tcp _lyncdiscover._tcp"
for SRV in $MS_SRV_RECORDS; do
    if add_records "${SRV}.$DOMAIN" "SRV" "Microsoft 365 SRV ($SRV)"; then
        printf "  %-20s ... ✓\n" "$SRV"
    fi
done

# ===========================================
# 証明書・セキュリティ関連
# ===========================================
echo ""
echo "[セキュリティ・証明書]"

# ACME Challenge (Let's Encrypt)
printf "  %-12s ... " "ACME"
if add_records "_acme-challenge.$DOMAIN" "TXT" "ACME Challenge (Let's Encrypt)" || \
   add_records "_acme-challenge.$DOMAIN" "CNAME" "ACME Challenge CNAME"; then
    echo "✓"
else
    echo "-"
fi

# DANE/TLSA for mail
printf "  %-12s ... " "TLSA (mail)"
if add_records "_25._tcp.mail.$DOMAIN" "TLSA" "DANE TLSA for mail" || \
   add_records "_25._tcp.$DOMAIN" "TLSA" "DANE TLSA for MX"; then
    echo "✓"
else
    echo "-"
fi

# DANE/TLSA for web
printf "  %-12s ... " "TLSA (web)"
if add_records "_443._tcp.$DOMAIN" "TLSA" "DANE TLSA for HTTPS" || \
   add_records "_443._tcp.www.$DOMAIN" "TLSA" "DANE TLSA for www"; then
    echo "✓"
else
    echo "-"
fi

# ===========================================
# サービス検証レコード
# ===========================================
echo ""
echo "[サービス検証]"

# Google Site Verification
printf "  %-16s ... " "Google"
if grep -q "google-site-verification" "$OUTPUT_FILE" 2>/dev/null; then
    echo "✓ (TXTに含まれる)"
else
    echo "-"
fi

# Microsoft Domain Verification
printf "  %-16s ... " "Microsoft"
if grep -q "MS=" "$OUTPUT_FILE" 2>/dev/null; then
    echo "✓ (TXTに含まれる)"
else
    echo "-"
fi

# Facebook Domain Verification
printf "  %-16s ... " "Facebook"
if grep -q "facebook-domain-verification" "$OUTPUT_FILE" 2>/dev/null; then
    echo "✓ (TXTに含まれる)"
else
    echo "-"
fi

# Apple Domain Verification
printf "  %-16s ... " "Apple"
if grep -q "apple-domain-verification" "$OUTPUT_FILE" 2>/dev/null; then
    echo "✓ (TXTに含まれる)"
else
    echo "-"
fi

# Atlassian Domain Verification
printf "  %-16s ... " "Atlassian"
if grep -q "atlassian-domain-verification" "$OUTPUT_FILE" 2>/dev/null; then
    echo "✓ (TXTに含まれる)"
else
    echo "-"
fi

# ===========================================
# 完了
# ===========================================
echo ""
echo "============================================"
echo "完了！ファイルを生成しました: $OUTPUT_FILE"
echo "============================================"
echo ""

# 重複行を削除
sort -u "$OUTPUT_FILE" -o "${OUTPUT_FILE}.tmp"
# ヘッダーを保持しつつソート
head -8 "$OUTPUT_FILE" > "${OUTPUT_FILE}.sorted"
tail -n +9 "$OUTPUT_FILE" | sort -u >> "${OUTPUT_FILE}.sorted"
mv "${OUTPUT_FILE}.sorted" "$OUTPUT_FILE"
rm -f "${OUTPUT_FILE}.tmp"

# レコード数をカウント
RECORD_COUNT=$(grep -v "^;" "$OUTPUT_FILE" | grep -v "^\$" | grep -v "^$" | wc -l)
echo "取得したレコード数: $RECORD_COUNT"
echo ""

echo "--- Cloudflare へのインポート方法 ---"
echo "1. Cloudflare ダッシュボードにログイン"
echo "2. 対象ドメインを選択 → DNS → Records"
echo "3. 「Import and Export」をクリック"
echo "4. 「Import DNS records」で $OUTPUT_FILE をアップロード"
echo ""
echo "--- 生成されたゾーンファイル ---"
cat "$OUTPUT_FILE"
