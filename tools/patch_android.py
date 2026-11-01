import glob
import re

p = "android/app/src/main/AndroidManifest.xml"
s = open(p, encoding="utf-8").read()

META = (
    '<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" '
    'android:value="ca-app-pub-3940256099942544~3347511713"/>'
)

if "com.google.android.gms.ads.APPLICATION_ID" not in s:
    s = s.replace("</application>", "    " + META + "\n    </application>", 1)

if "android.permission.INTERNET" not in s:
    s = s.replace(
        "<application",
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
        1,
    )

s = re.sub(r'android:label="[^"]*"', 'android:label="GK Coins"', s, count=1)
open(p, "w", encoding="utf-8").write(s)

for g in glob.glob("android/app/build.gradle*"):
    t = open(g, encoding="utf-8").read()
    t2 = t.replace("flutter.minSdkVersion", "24")
    if t2 != t:
        open(g, "w", encoding="utf-8").write(t2)

print("patched OK")
print(s)
