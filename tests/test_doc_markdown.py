"""Public Markdown excludes inaccessible nested compounds, not public ones."""
import tempfile
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

from scripts.build_doc_markdown import public_xml, output_modes


class PublicDocumentationTests(unittest.TestCase):
    def test_private_protected_and_descendants(self):
        with tempfile.TemporaryDirectory() as temp:
            raw = Path(temp) / "raw"
            raw.mkdir()
            members = [
                ("outer", "class", "Outer", "public"),
                ("private", "struct", "Outer::AgeValuePair", "public"),
                ("protected", "struct", "Outer::Helper", "protected"),
                ("child", "struct", "Outer::Helper::Child", "public"),
                ("public", "struct", "Outer::PublicNested", "public"),
                ("standalone", "class", "Other", "public"),
            ]
            entries = "".join(
                f'<compound refid="{ref}" kind="{kind}"><name>{name}</name></compound>'
                for ref, kind, name, _ in members
            )
            (raw / "index.xml").write_text(
                f"<doxygenindex>{entries}</doxygenindex>", encoding="utf-8"
            )
            children = {
                "outer": [
                    ("private", "private"), ("protected", "protected"),
                    ("public", "public")
                ],
                "protected": [("child", "public")],
            }
            for ref, kind, _, access in members:
                inners = "".join(
                    f'<innerclass refid="{rid}" prot="{prot}">Inner</innerclass>'
                    for rid, prot in children.get(ref, [])
                )
                (raw / (ref + ".xml")).write_text(
                    f'<doxygen><compounddef id="{ref}" kind="{kind}" prot="{access}">'
                    f'{inners}</compounddef></doxygen>', encoding="utf-8"
                )
            filtered = Path(temp) / "filtered"
            excluded = public_xml(raw, filtered)
            self.assertEqual(excluded, {"private", "protected", "child"})
            remaining = {
                c.get("refid") for c in ET.parse(filtered / "index.xml").getroot()
            }
            self.assertEqual(remaining, {"outer", "public", "standalone"})
            owner = ET.parse(filtered / "outer.xml").getroot().find("compounddef")
            self.assertEqual(
                [node.get("refid") for node in owner.findall("innerclass")],
                ["public"],
            )
            self.assertFalse((filtered / "private.xml").exists())
            self.assertTrue((raw / "private.xml").exists())
            self.assertIn("--classes", output_modes(filtered / "index.xml"))


if __name__ == "__main__":
    unittest.main()
