/// 個人情報の自動削除。
///
/// 氏名・ID・生年月日・住所・電話番号など、個人を特定できる部分を見つけて削除する。
/// 検査値（7桁未満の数値）や年齢・性別は残す。Web版（engine.js の scrubPII）と同じ規則。
library;

const piiMark = '［削除］';

const _sep = r'(?:\s*[:：=]\s*|\s+|(?=[A-Za-z0-9]))';
const _nameChars = r'[一-鿿々゠-ヿー]'; // 漢字・カタカナ（ひらがなは文章と区別しにくいので除く）

/// 敬称の前にあっても氏名ではない語。
final _notAName = RegExp(
    r'^(患者|ご?家族|ご?本人|お?母|お?父|お?祖母|お?祖父|奥|娘|息子|お?子|皆|利用者|医師|看護師|先生|主治医|担当|職員|業者|お客|相手|他|隣|ナース|ヘルパー|ドクター|ケアマネ|ドライバー|救急隊|隊員|家人|妻|夫|兄|弟|姉|妹|孫)$');

final List<(RegExp, bool)> _rules = [
  // 見出し付きのもの。見出しの種類ごとに、後ろの「値」だけを消す（文章の続きは残す）
  // 氏名（姓と名の2語まで）
  (RegExp(r'(?:氏\s*名|患者\s*名|お?名\s*前|フリガナ|ふりがな|ﾌﾘｶﾞﾅ|カナ氏名|ローマ字)(?:\s*[:：=]\s*|\s+)[^\s、，,;；。？?（）()0-9]+(?:[ 　][^\s、，,;；。？?（）()0-9]+)?'), false),
  // ID・各種番号（英数字とハイフンの1語）
  (
    RegExp(
        '(?<![A-Za-z])(?:患者\\s*ID|患者\\s*番号|PID|ID|カルテ\\s*(?:番号|No\\.?|NO)?|診察券\\s*(?:番号)?|保険証\\s*(?:番号)?|被保険者\\s*(?:番号|記号)?|記号番号|受付\\s*番号|入院\\s*番号|マイナンバー)(?![A-Za-z])$_sep[A-Za-z0-9\\-‐−ー]*\\d[A-Za-z0-9\\-‐−ー]*',
        caseSensitive: false),
    false
  ),
  // 生年月日
  (RegExp(r'(?:生年月日|誕生日)(?:\s*[:：=]\s*|\s+)[0-9MTSHR明治大正昭和平成令和年月日/.\-‐]+[0-9日]生?'), false),
  // 電話番号（見出し付き）
  (RegExp(r'(?<![A-Za-z])(?:電話\s*(?:番号)?|TEL|携帯)(?![A-Za-z])(?:\s*[:：=]\s*|\s+|(?=[0-9]))[0-9\-‐−ー()（） ]{6,}[0-9]', caseSensitive: false), false),
  // メール・住所（区切りまで）
  (RegExp(r'(?:メール|E-?mail|住\s*所)(?:\s*[:：=]\s*|\s+)[^\n、，,;；。？?]+', caseSensitive: false), false),
  // メールアドレス
  (RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+'), false),
  // 電話番号（0X-XXXX-XXXX、090XXXXXXXX）
  (RegExp(r'(?<!\d)0\d{1,4}[-‐−ー(（]\d{1,4}[-‐−ー)）]\d{3,4}(?!\d)|(?<!\d)0[789]0\d{8}(?!\d)'), false),
  // 郵便番号
  (RegExp(r'〒?\s*(?<!\d)\d{3}[-‐−ー]\d{4}(?!\d)'), false),
  // 生年月日（〜生、〜生まれ）
  (RegExp(r'((明治|大正|昭和|平成|令和|[MTSHR])\s*\d{1,2}|(19|20)\d\d)\s*[/.\-年]\s*\d{1,2}\s*[/.\-月]\s*\d{1,2}\s*日?\s*(生まれ|生)'), false),
  // 住所（都道府県＋市区町村〜番地）
  (RegExp(r'[一-鿿]{2,3}[都道府県][一-鿿぀-ヿー]{1,8}[市区町村郡][一-鿿぀-ヿー\d０-９\-‐−ー丁目番地号の]*'), false),
  // 7桁以上の番号（ID・カルテ番号など。検査値は7桁未満）
  (RegExp(r'(?<![\d.])\d{7,}(?![\d.])'), false),
  // 敬称の付いた氏名（山田太郎様、山田 さん、ヤマダ殿）
  (RegExp('($_nameChars{1,8})(\\s?$_nameChars{0,8})\\s?(様|さま|さん|殿|氏|くん|君|ちゃん)(?![\\u4E00-\\u9FFF])'), true),
];

/// 削除結果。
class PiiResult {
  const PiiResult(this.text, this.removed);
  final String text;

  /// 削除した箇所の数。
  final int removed;
}

/// [text] から個人情報と思われる部分を削除する。
PiiResult scrubPII(String text) {
  var t = text;
  var removed = 0;
  for (final (re, honorific) in _rules) {
    t = t.replaceAllMapped(re, (m) {
      if (honorific && _notAName.hasMatch('${m[1]}${m[2] ?? ''}'.replaceAll(RegExp(r'\s'), ''))) return m[0]!;
      removed++;
      return piiMark;
    });
  }
  t = t.replaceAll(RegExp('(${RegExp.escape(piiMark)}\\s*)+'), piiMark);
  return PiiResult(t, removed);
}

bool hasPII(String text) => scrubPII(text).removed > 0;
