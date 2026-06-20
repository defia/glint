import os, json, re, glob

SRC = "ghostty/zig-out/share/ghostty/themes"
GHOSTTY_DEFAULT = ["1d1f21","cc6666","b5bd68","f0c674","81a2be","b294bb","8abeb7","c5c8c6",
                   "666666","d54e53","b9ca4a","e7c547","7aa6da","c397d8","70c0b1","eaeaea"]

def kebab(name):
    s = name.lower()
    s = s.replace("+", "-plus")
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-")

def norm_hex(v):
    v = v.strip().lstrip("#").lower()
    if len(v) == 3:  # #rgb -> rrggbb
        v = "".join(c*2 for c in v)
    return v if re.fullmatch(r"[0-9a-f]{6}", v or "") else None

def parse(path):
    bg=fg=cur=sb=sf=None
    pal = [None]*16
    for line in open(path, encoding="utf-8", errors="ignore"):
        line=line.strip()
        if not line or "=" not in line: continue
        key, _, rest = line.partition("=")
        key = key.strip()
        rest = rest.strip()
        if key == "palette":
            # rest like "0=#hex" or "0 = #hex"
            idx, _, col = rest.partition("=")
            try: i = int(idx.strip())
            except: continue
            if 0 <= i < 16:
                h = norm_hex(col)
                if h: pal[i] = h
        elif key == "background": bg = norm_hex(rest)
        elif key == "foreground": fg = norm_hex(rest)
        elif key == "cursor-color": cur = norm_hex(rest)
        elif key == "selection-background": sb = norm_hex(rest)
        elif key == "selection-foreground": sf = norm_hex(rest)
    if not bg or not fg: return None
    # fill palette gaps with ghostty default
    pal = [pal[i] or GHOSTTY_DEFAULT[i] for i in range(16)]
    cur = cur or fg
    sb = sb or pal[8]
    sf = sf or bg
    return bg,fg,cur,sb,sf,pal

def luminance(hex6):
    r=int(hex6[0:2],16)/255; g=int(hex6[2:4],16)/255; b=int(hex6[4:6],16)/255
    return 0.2126*r+0.7152*g+0.0722*b

out=[]
seen=set()
for path in sorted(glob.glob(os.path.join(SRC,"*"))):
    name = os.path.basename(path)
    r = parse(path)
    if not r: 
        print("SKIP (no bg/fg):", name); continue
    bg,fg,cur,sb,sf,pal = r
    tid = kebab(name)
    if tid in seen: 
        print("DUP id, skip:", name); continue
    seen.add(tid)
    out.append({"id":tid,"name":name,"dark":luminance(bg)<0.5,
                "bg":bg,"fg":fg,"cur":cur,"sb":sb,"sf":sf,"pal":pal})

os.makedirs("Glint/Resources", exist_ok=True)
with open("Glint/Resources/themes.json","w",encoding="utf-8") as f:
    json.dump(out, f, separators=(",",":"), ensure_ascii=False)
print(f"\nWROTE {len(out)} themes -> Glint/Resources/themes.json")
print("size:", os.path.getsize("Glint/Resources/themes.json"), "bytes")
print("dark:", sum(1 for t in out if t['dark']), "light:", sum(1 for t in out if not t['dark']))
print("sample:", json.dumps(out[0], ensure_ascii=False)[:200])
