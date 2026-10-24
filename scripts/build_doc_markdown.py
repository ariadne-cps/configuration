#!/usr/bin/env python3
"""Generate Hugo-friendly Markdown API pages from Doxygen XML with Moxygen."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def output_modes(index: Path) -> list[str]:
    """Enable only Moxygen output modes actually present in Doxygen XML."""
    try:
        root = ET.parse(index).getroot()
    except ET.ParseError as exc:
        raise ValueError(f"Invalid Doxygen XML index {index}: {exc}") from exc

    kinds = {compound.get("kind") for compound in root.findall("compound")}
    if not kinds:
        raise ValueError(f"No Doxygen compounds found in {index}")

    modes = []
    # Doxygen uses separate kinds for classes, structs, unions and interfaces.
    if kinds.intersection({"class", "struct", "union", "interface"}):
        modes.append("--classes")
    if "group" in kinds:
        modes.append("--groups")
    if "page" in kinds:
        modes.append("--pages")
    return modes


# A non-public nested class may still appear in Doxygen's XML index, even
# with EXTRACT_PRIVATE=NO. Moxygen selects types from that index without
# considering their access. Filter the XML copy used for public Markdown.
_NON_PUBLIC = {"private", "protected"}
_COMPOUND_TYPES = {"class", "struct", "union", "interface"}


def public_xml(source: Path, destination: Path) -> set[str]:
    """Copy Doxygen XML, omitting inaccessible nested types and their children.

    Both compounddef/prot and the enclosing innerclass/prot are checked;
    the enclosing declaration is authoritative for C++ nested access.
    The original Doxygen XML, LaTeX and HTML remain unmodified.
    """
    index_tree = ET.parse(source / "index.xml")
    root = index_tree.getroot()
    compounds = {
        entry.get("refid"): entry for entry in root.findall("compound")
    }
    if not compounds:
        raise ValueError("Empty Doxygen XML index")
    hidden: set[str] = set()
    owners: dict[str, str] = {}

    for refid, entry in compounds.items():
        path = source / (str(refid) + ".xml")
        if not path.is_file():
            raise ValueError(f"Missing Doxygen XML compound: {path}")
        node = ET.parse(path).getroot().find("compounddef")
        if node is None:
            raise ValueError(f"No compounddef found in {path}")
        if entry.get("kind") in _COMPOUND_TYPES and node.get("prot") in _NON_PUBLIC:
            hidden.add(refid)
        for inner in node.findall("innerclass"):
            child = inner.get("refid")
            if child in compounds:
                owners[child] = refid
                if inner.get("prot") in _NON_PUBLIC:
                    hidden.add(child)

    # A public type nested inside a private/protected type is still inaccessible.
    changed = True
    while changed:
        before = len(hidden)
        hidden.update(child for child, parent in owners.items() if parent in hidden)
        changed = len(hidden) != before

    shutil.copytree(source, destination)
    for compound in list(root.findall("compound")):
        if compound.get("refid") in hidden:
            root.remove(compound)
    index_tree.write(destination / "index.xml", encoding="utf-8", xml_declaration=True)

    for refid in hidden:
        (destination / (refid + ".xml")).unlink(missing_ok=True)

    for path in destination.glob("*.xml"):
        if path.name == "index.xml":
            continue
        tree = ET.parse(path)
        node = tree.getroot().find("compounddef")
        if node is None:
            continue
        refs = [c for c in node.findall("innerclass") if c.get("refid") in hidden]
        if refs:
            for c in refs:
                node.remove(c)
            tree.write(path, encoding="utf-8", xml_declaration=True)

    print(f"Excluded {len(hidden)} non-public Doxygen compounds from public XML", flush=True)
    return hidden



def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xml", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    index = args.xml / "index.xml"
    if not index.is_file():
        parser.error(f"Doxygen XML index not found: {index}")
    tool = shutil.which("moxygen")
    if tool is None:
        parser.error("Install Node.js 20+ and run npm install -g moxygen@2.1.19")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="utility-docs-", dir=args.output.parent) as tmp:
        filtered = Path(tmp) / "public-xml"
        try:
            public_xml(args.xml, filtered)
            modes = output_modes(filtered / "index.xml")
        except (ValueError, ET.ParseError) as exc:
            parser.error(str(exc))
        stage = Path(tmp) / "markdown"
        stage.mkdir()
        # When no compound category is split into individual pages, use the
        # default single-page Moxygen output instead of a %s filename.
        filename = "api-%s.md" if modes else "api.md"
        command = [
            tool, *modes, "--anchors", "--frontmatter", "--flavour", "github",
            "--output", str(stage / filename), str(filtered)
        ]
        print("Moxygen output modes:", " ".join(modes) if modes else "single page", flush=True)
        subprocess.run(command, check=True)

        pages = sorted(stage.rglob("*.md"))
        if not pages:
            print("Moxygen produced no Markdown pages", file=sys.stderr)
            return 1
        # Replace the output only when generation succeeded. This also removes
        # obsolete pages that could otherwise survive into a Hugo publication.
        if args.output.exists():
            shutil.rmtree(args.output)
        shutil.move(str(stage), str(args.output))
        print(f"Generated {len(pages)} Markdown pages in {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
