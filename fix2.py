import io

with io.open(r'd:\ws\answer\messenger\lib\l10n\app_localizations.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace("Reject __name__'s request?", "Reject __name__\\'s request?")

with io.open(r'd:\ws\answer\messenger\lib\l10n\app_localizations.dart', 'w', encoding='utf-8') as f:
    f.write(text)
