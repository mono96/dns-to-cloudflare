# dns-to-cloudflare

dig を使って既存のDNSレコードを取得し、Cloudflare にインポート可能な BIND 形式のゾーンファイルを生成するスクリプト。

## 特徴

- **包括的なレコード取得**: A, AAAA, MX, TXT, CNAME, NS, CAA, SRV, NAPTR, TLSA, SSHFP, LOC, HTTPS, SVCB
- **サブドメイン自動検出**: Certificate Transparency、HackerTarget、辞書スキャン、MX/NS推測の4つの方法を併用
- **ワイルドカードDNS対応**: 誤検出を防止
- **メール認証レコード**: SPF, DKIM, DMARC, MTA-STS, BIMI, ADSP, TLS-RPT
- **メール自動設定**: Autodiscover, Autoconfig, Microsoft 365 SRV
- **セキュリティレコード**: ACME Challenge, DANE/TLSA

## 必要なもの

- bash
- dig (dnsutils / bind-utils)
- curl

```bash
# Ubuntu/Debian
sudo apt install dnsutils curl

# macOS (digは標準インストール済み)
brew install curl

# CentOS/RHEL
sudo yum install bind-utils curl
```

## 使い方

```bash
# ダウンロード
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/dns-to-cloudflare/main/dns-to-cloudflare.sh
chmod +x dns-to-cloudflare.sh

# 実行
./dns-to-cloudflare.sh example.com
```

## 出力例

```
ドメイン: example.com のDNSレコードを取得中...

[メインドメイン]
  A          ... ✓
  AAAA       ... ✓
  MX         ... ✓
  TXT        ... ✓
  ...

[サブドメイン検出]
  [1/4] crt.sh (Certificate Transparency)...
        → 12 件検出
  [2/4] HackerTarget...
        → 5 件検出
  [3/4] 共通サブドメイン辞書...
        → 8 件検出
  [4/4] MX/NSレコードから推測...
        → 2 件検出

  合計: 15 件のユニークなサブドメインを検出

[サブドメインのレコード取得]
  www                            ... ✓
  mail                           ... ✓
  api                            ... ✓
  ...

============================================
完了！ファイルを生成しました: example.com.zone
============================================
```

## Cloudflare へのインポート

1. [Cloudflare ダッシュボード](https://dash.cloudflare.com/) にログイン
2. 対象ドメインを選択
3. **DNS** → **Records** に移動
4. **Import and Export** をクリック
5. **Import DNS records** で生成された `.zone` ファイルをアップロード

## 取得するレコード一覧

### メインドメイン

| カテゴリ | レコードタイプ |
|---------|---------------|
| 基本 | A, AAAA, MX, TXT, CNAME, NS, CAA, SRV |
| 拡張 | NAPTR, TLSA, SSHFP, LOC, HTTPS, SVCB |

### メール関連

| レコード | 説明 |
|---------|------|
| SPF | TXTレコード内 (v=spf1) |
| DKIM | 20種類以上のセレクタを確認 |
| DMARC | _dmarc.domain.com |
| ADSP | _adsp._domainkey.domain.com |
| MTA-STS | _mta-sts.domain.com |
| TLS-RPT | _smtp._tls.domain.com |
| BIMI | default._bimi.domain.com |

### サブドメイン検出方法

| 方法 | 説明 | SSL証明書不要 |
|------|------|--------------|
| crt.sh | Certificate Transparency ログ | × |
| HackerTarget | Passive DNS データベース | ✓ |
| 辞書スキャン | 300+の一般的なサブドメイン名 | ✓ |
| MX/NS推測 | MX/NSレコードから抽出 | ✓ |

## 注意事項

- **ワイルドカードDNS**: 自動検出して辞書スキャンをスキップし、誤検出を防止
- **レート制限**: crt.sh や HackerTarget には API 制限があります
- **プライベートサブドメイン**: 外部から観測されていないサブドメインは検出できない場合があります
- **AXFR**: ゾーン転送は通常無効化されているため使用していません

## ライセンス

MIT License
