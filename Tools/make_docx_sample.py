#!/usr/bin/env python3
"""Writes the non-PDF sample syllabi to SampleSyllabi/.

Run from the repository root:  python3 Tools/make_docx_sample.py

- MoneyBanking_Syllabus.docx   Word document with a schedule table
- Seminar_NoDates.txt          plain text with graded work but no dates
- Broken_Syllabus.pdf          not really a PDF, for the error path
The .docx is also copied into the unit test target as a fixture.
"""
import os
import shutil
import zipfile
from xml.sax.saxutils import escape

OUT = "SampleSyllabi"
TEST_FIXTURES = "AssignmentTracker/AssignmentTrackerTests/Fixtures"
os.makedirs(OUT, exist_ok=True)
os.makedirs(TEST_FIXTURES, exist_ok=True)

W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'


def para(text, bold=False):
    props = "<w:rPr><w:b/></w:rPr>" if bold else ""
    return f'<w:p><w:r>{props}<w:t xml:space="preserve">{escape(text)}</w:t></w:r></w:p>'


def table(rows):
    out = ["<w:tbl>"]
    for i, row in enumerate(rows):
        out.append("<w:tr>")
        for cell in row:
            out.append(f"<w:tc>{para(cell, bold=(i == 0))}</w:tc>")
        out.append("</w:tr>")
    out.append("</w:tbl>")
    return "".join(out)


body = "".join([
    para("ECON 315: Money & Banking", bold=True),
    para("Fall 2026 · Prof. Amara Chen · Mon/Wed 3:00 PM"),
    para("The first day of class is September 1, 2026."),
    para("Assessment", bold=True),
    table([
        ["Due", "Assessment", "Weight"],
        ["Mon, Oct 5", "Bank balance sheet memo", "10%"],
        ["Thu, Oct 21", "Case analysis: 2008 crisis", "15%"],
        ["Wed, Nov 4", "Midterm exam", "25%"],
        ["Nov 16", "Group presentation", "15%"],
        ["Dec 7 at 11:59 PM", "Term paper", "20%"],
        ["Dec 16", "Final exam", "15%"],
    ]),
    para("Academic integrity: all submitted work must be your own."),
])
document = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}</w:body></w:document>'

content_types = (
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    "</Types>"
)
rels = (
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/></Relationships>'
)

docx_path = os.path.join(OUT, "MoneyBanking_Syllabus.docx")
with zipfile.ZipFile(docx_path, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", content_types)
    z.writestr("_rels/.rels", rels)
    z.writestr("word/document.xml", document)
shutil.copy(docx_path, os.path.join(TEST_FIXTURES, "MoneyBanking_Syllabus.docx"))

with open(os.path.join(OUT, "Seminar_NoDates.txt"), "w") as f:
    f.write(
        "HIST 480 Senior Seminar: The History of Central Banking\n"
        "Instructor: Dr. Paul Novak\n\n"
        "Course requirements\n"
        "Weekly reading responses — 20%\n"
        "Book review essay — 25%\n"
        "Research proposal — 15%\n"
        "Final research paper — 40%\n\n"
        "Due dates will be posted on Canvas.\n"
    )

with open(os.path.join(OUT, "Broken_Syllabus.pdf"), "wb") as f:
    f.write(b"This is not a PDF file, just some text with a .pdf extension.\n" * 3)

print(f"Wrote samples to {OUT}/ and fixture to {TEST_FIXTURES}/")
