import io

with io.open(r'd:\ws\answer\messenger\lib\l10n\app_localizations.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace(r"\'", "'")

with io.open(r'd:\ws\answer\messenger\lib\l10n\app_localizations.dart', 'w', encoding='utf-8') as f:
    f.write(text)
