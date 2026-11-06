import unittest

from release_notes import paragraph, plain


class ParagraphTests(unittest.TestCase):
    def test_takes_the_first_paragraph_on_one_line(self):
        body = "Typing in large notes\nis smoother.\n\nTechnical details."
        self.assertEqual(paragraph(body), "Typing in large notes is smoother.")

    def test_skips_comments_headings_and_images(self):
        body = "<!-- template -->\n## Summary\n\n![Before](a.png)\n\nFixed it."
        self.assertEqual(paragraph(body), "Fixed it.")

    def test_keeps_prose_right_under_a_heading(self):
        self.assertEqual(paragraph("## Summary\nFixed a crash."), "Fixed a crash.")

    def test_empty_body(self):
        self.assertEqual(paragraph(""), "")


class PlainTests(unittest.TestCase):
    def test_turns_markdown_into_plain_text(self):
        markdown = (
            "## New\n\n"
            "- **Undo** after moving a note to [Trash](https://x.y) (#291)\n"
            "* Smoother typing in `large` notes (#290)\n\n\n\n"
            "Thanks for *testing*!"
        )
        self.assertEqual(
            plain(markdown),
            "New\n\n• Undo after moving a note to Trash\n"
            "• Smoother typing in large notes\n\nThanks for testing!",
        )

    def test_keeps_snake_case_and_lone_asterisks(self):
        self.assertEqual(plain("Use 2 * 3 in a_b_c"), "Use 2 * 3 in a_b_c")


if __name__ == "__main__":
    unittest.main()
