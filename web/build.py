#!/usr/bin/env python3
"""web/index.html에 Gaegu 글꼴(필요한 글자만)과 효과음·배경음을 넣어 dist/sempan.html(과 배포용 dist/index.html) 한 파일로 만들어요.

사용법: python3 web/build.py
필요: pip install fonttools
"""
import base64
import io
import json
import pathlib

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent
FONTS = ROOT.parent / "sempan_the_game" / "Fonts"
SOUNDS = ROOT.parent / "sempan_the_game" / "Sounds"
SRC = ROOT / "index.html"
OUT = ROOT / "dist" / "sempan.html"


def glyphs(text: str) -> str:
    # 페이지에 나오는 글자 + 영숫자·기호 전부 (숫자 단위와 날짜 표시용 글자 포함)
    chars = set(text) | {chr(c) for c in range(0x20, 0x7F)} | set("만억조경오전후년월일²×÷−▲∞…·")
    return "".join(sorted(c for c in chars if c.isprintable()))


def subset_font(path: pathlib.Path, text: str) -> str:
    font = TTFont(path)
    opts = subset.Options()
    opts.flavor = "woff"
    opts.layout_features = ["*"]
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    buf = io.BytesIO()
    font.flavor = "woff"
    font.save(buf)
    return base64.b64encode(buf.getvalue()).decode()


def main() -> None:
    html = SRC.read_text(encoding="utf-8")
    text = glyphs(html)
    faces = []
    for name, weight in [("Gaegu-Regular", 400), ("Gaegu-Bold", 700)]:
        data = subset_font(FONTS / f"{name}.ttf", text)
        faces.append(f"@font-face{{font-family:'Gaegu';font-weight:{weight};font-display:swap;"
                     f"src:url(data:font/woff;base64,{data}) format('woff')}}")
    out = html.replace("/*@FONTS@*/", "\n".join(faces), 1)
    # 앱과 같은 아이콘 (탭 아이콘, 홈 화면 아이콘). web/icons는 앱 아이콘을 줄인 그림이에요
    icon = lambda px: "data:image/png;base64," + base64.b64encode((ROOT / "icons" / f"icon-{px}.png").read_bytes()).decode()
    out = out.replace("<!--@ICONS@-->",
                      f'<link rel="icon" type="image/png" sizes="32x32" href="{icon(32)}">\n'
                      f'<link rel="icon" type="image/png" sizes="192x192" href="{icon(192)}">\n'
                      f'<link rel="apple-touch-icon" sizes="180x180" href="{icon(180)}">', 1)
    # 효과음과 배경음 (sound/gen.py가 만든 WAV)
    sounds = {f.stem: base64.b64encode(f.read_bytes()).decode() for f in sorted(SOUNDS.glob("*.wav"))}
    out = out.replace("/*@SOUNDS@*/", "window.SOUND_DATA=" + json.dumps(sounds) + ";", 1)
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(out, encoding="utf-8")
    # 배포용: 같은 파일을 index.html로도 둬요 (Vercel 정적 배포)
    (OUT.parent / "index.html").write_text(out, encoding="utf-8")
    print(f"{OUT.relative_to(ROOT.parent)}: {len(out) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
