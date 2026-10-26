#!/usr/bin/env python3
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("docs", Path(__file__).with_name("check-docs.py"))
docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(docs)


class DocumentationCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()

    def write(self, file, text):
        path = self.root / file
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_recursively_detects_unpaired_guide(self):
        file = self.write("docs/deep/guide.md", "# Guide")
        self.assertIn("missing Chinese peer", docs.check(self.root, [file])[1][0])

    def test_wrong_language_link_is_not_a_reciprocal_link(self):
        en = self.write("docs/guides/a.md", "[简体中文](a.md)")
        zh = self.write("docs/guides/a.zh-CN.md", "[English](a.md)")
        count, errors = docs.check(self.root, [en, zh])
        self.assertEqual(count, 1)
        self.assertEqual(len(errors), 1)
        self.assertIn("reciprocal", errors[0])

    def test_nested_relative_links_and_code_examples(self):
        en = self.write("docs/guides/a.md", "[简体中文](a.zh-CN.md)\n[Root](../../LICENSE)\n```md\n[Example](absent.md)\n```\n")
        zh = self.write("docs/guides/a.zh-CN.md", "[English](a.md)")
        self.write("LICENSE", "GPL")
        self.assertEqual(docs.check(self.root, [en, zh]), (1, []))

    def test_current_github_link_resolves_locally(self):
        source = self.write("internal.md", f"[Guide]({docs.GITHUB_ROOT}docs/missing.md)")
        self.assertIn("broken link", docs.check(self.root, [source])[1][0])

    def test_immutable_release_link_remains_historical(self):
        file = self.write("docs/archive/old.md", "[Old](https://github.com/chenyuhao0628/displayweave/blob/v0.1.0/removed.md)")
        self.assertEqual(docs.check(self.root, [file]), (0, []))

    def test_reference_links_are_checked(self):
        file = self.write("internal.md", "[Broken][x]\n[x]: absent.md")
        self.assertIn("broken link", docs.check(self.root, [file])[1][0])

    def test_dynamic_website_english_path_is_checked(self):
        file = self.write("src/Link.tsx", f'const url = `{docs.GITHUB_ROOT}docs/missing${{chinese ? ".zh-CN" : ""}}.md`;')
        self.assertIn("broken GitHub main link", docs.check(self.root, [file])[1][0])

    def test_dynamic_website_chinese_path_is_checked(self):
        self.write("docs/README.md", "# English")
        file = self.write("src/Link.tsx", f'const url = `{docs.GITHUB_ROOT}docs/README${{chinese ? ".zh-CN" : ""}}.md`;')
        errors = docs.check(self.root, [file])[1]
        self.assertEqual(len(errors), 1)
        self.assertIn("README.zh-CN.md", errors[0])

    def test_inline_markdown_example_is_not_a_link(self):
        file = self.write("internal.md", "Use `[English](...)` as an example.")
        self.assertEqual(docs.check(self.root, [file]), (0, []))


if __name__ == "__main__":
    unittest.main()
