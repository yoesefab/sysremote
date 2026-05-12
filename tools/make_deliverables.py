#!/usr/bin/env python3
"""Generate required school deliverables without external Python packages."""

from __future__ import annotations

import html
import os
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEAM = "TeamID"
PDF = ROOT / f"{TEAM}-devoir-shell.pdf"
PPTX = ROOT / f"{TEAM}-devoir-shell.pptx"
ZIP = ROOT / f"{TEAM}-devoir-shell.zip"


REPORT_LINES = [
    "sysremote - devoir shell",
    "",
    "But: automatiser l'administration distante multi-hotes sous Linux.",
    "Utilisateurs: administrateurs systeme, DevOps, developpeurs et utilisateurs Linux.",
    "Besoin: gagner du temps, reduire l'effort repetitif et fiabiliser les operations.",
    "",
    "Script principal: bin/sysremote.sh",
    "Syntaxe: sysremote [options] commande [arguments]",
    "",
    "Options obligatoires:",
    "-h aide complete",
    "-f fork avec processus enfants, & et wait",
    "-t thread/worker pool avec xargs -P",
    "-s sous-shell avec (...)",
    "-l dossier de logs",
    "-r restauration admin uniquement",
    "",
    "Logs:",
    "/var/log/sysremote/history.log ou dossier donne par -l.",
    "Format: yyyy-mm-dd-hh-mm-ss : username : INFOS|ERROR : message",
    "",
    "Concepts Bash/Linux:",
    "conditions, case, for, while, until, fonctions, variables d'environnement, regex,",
    "manipulation de fichiers, find, tar.gz, grep, awk, sed, cut, sort, uniq, droits.",
    "",
    "Benchmarks:",
    "benchmark light, benchmark medium, benchmark heavy comparent normal/fork/thread/subshell.",
    "",
    "Captures a inserer dans la version finale remise:",
    "1. aide -h",
    "2. history.log",
    "3. benchmark light",
    "4. archive tar.gz creee",
]


def pdf_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def make_pdf() -> None:
    content_lines = ["BT", "/F1 12 Tf", "50 790 Td", "14 TL"]
    for line in REPORT_LINES:
        content_lines.append(f"({pdf_escape(line)}) Tj")
        content_lines.append("T*")
    content_lines.append("ET")
    stream = "\n".join(content_lines).encode("latin-1")

    objects: list[bytes] = []
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objects.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    objects.append(
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
        b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
    )
    objects.append(b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream")
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    chunks = [b"%PDF-1.4\n"]
    offsets = [0]
    for index, obj in enumerate(objects, start=1):
        offsets.append(sum(len(chunk) for chunk in chunks))
        chunks.append(f"{index} 0 obj\n".encode("ascii"))
        chunks.append(obj)
        chunks.append(b"\nendobj\n")
    xref_offset = sum(len(chunk) for chunk in chunks)
    chunks.append(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    chunks.append(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        chunks.append(f"{offset:010d} 00000 n \n".encode("ascii"))
    chunks.append(
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n".encode(
            "ascii"
        )
    )
    PDF.write_bytes(b"".join(chunks))


def make_pptx() -> None:
    title = "sysremote"
    bullets = [
        "Bash CLI pour administration distante multi-hotes",
        "Logs: terminal + history.log avec INFOS/ERROR",
        "Modes: normal, fork, thread, subshell",
        "Benchmarks light/medium/heavy et archive tar.gz",
    ]
    bullet_xml = "".join(
        f"""
        <a:p><a:r><a:rPr lang="fr-FR" sz="2200"/><a:t>{html.escape(item)}</a:t></a:r></a:p>
        """
        for item in bullets
    )

    files = {
        "[Content_Types].xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
</Types>
""",
        "_rels/.rels": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>
""",
        "ppt/presentation.xml": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>
  <p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>
""",
        "ppt/_rels/presentation.xml.rels": """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
</Relationships>
""",
        "ppt/slides/slide1.xml": f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
      <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
        <p:spPr><a:xfrm><a:off x="700000" y="500000"/><a:ext cx="10800000" cy="900000"/></a:xfrm></p:spPr>
        <p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="fr-FR" sz="4400" b="1"/><a:t>{html.escape(title)}</a:t></a:r></a:p></p:txBody>
      </p:sp>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="3" name="Summary"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
        <p:spPr><a:xfrm><a:off x="900000" y="1700000"/><a:ext cx="10400000" cy="4000000"/></a:xfrm></p:spPr>
        <p:txBody><a:bodyPr/><a:lstStyle/>{bullet_xml}</p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>
""",
    }
    with zipfile.ZipFile(PPTX, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in files.items():
            archive.writestr(name, content)


def make_zip() -> None:
    include = [
        PDF,
        PPTX,
        ROOT / "README.md",
        ROOT / "inventory.example",
        ROOT / "sysremote.conf.example",
        ROOT / "bin" / "sysremote.sh",
        ROOT / "docs" / "usage-rapide.md",
        ROOT / "docs" / "tests-manuels.md",
        ROOT / "docs" / "rapport-shell.md",
        ROOT / "tools" / "make_deliverables.py",
    ]
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in include:
            archive.write(path, path.relative_to(ROOT))


def main() -> None:
    make_pdf()
    make_pptx()
    make_zip()
    print(PDF.name)
    print(PPTX.name)
    print(ZIP.name)


if __name__ == "__main__":
    os.chdir(ROOT)
    main()
