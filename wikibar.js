window.addEventListener("load", function() {
	"use strict";

	const textarea = document.getElementById("text");

	const toolbar = document.createElement("ul");
	toolbar.className = "wikibar";

	addButton("bold",    "Bold text: '''Example'''", "'''",      "'''");
	addButton("italic",  "Italic text: ''Example''", "''",       "''");
	addButton("heading", "Heading: === Example ===", "\n=== ",   " ===\n");
	addButton("link",    "Link: [[Example]]",        "[[",       "]]");
	addButton("list",    "List: *Example",           "\n*",      "");
	addButton("hr",      "Horizontal rule: ----",    "\n----\n", "");

	textarea.parentNode.insertBefore(toolbar, textarea);

	function addButton(id, title, prefix, suffix) {
		const li = document.createElement("li");
		const a = document.createElement("a");
		const span = document.createElement("span");

		a.id = id;
		a.title = title;
		a.addEventListener("click", encloseText.bind(this, prefix, suffix));

		span.appendChild(document.createTextNode(id));
		a.appendChild(span);
		li.appendChild(a);
		toolbar.appendChild(li);
	}

	function encloseText(prefix, suffix) {
		let start = 0;
		let end = 0;
		let selection = "";
		let scrollPos = 0;

		textarea.focus();

		if (document.selection != undefined) {
			selection = document.selection.createRange().text;
		} else if (textarea.setSelectionRange != undefined) {
			start = textarea.selectionStart;
			end = textarea.selectionEnd;
			selection = textarea.value.substring(start, end);
			scrollPos = textarea.scrollTop;
		}

		if (selection.endsWith(" ")) { // excludes ending space, if any
			selection = selection.substring(0, selection.length - 1);
			suffix += " ";
		}

		const subst = prefix + selection + suffix;

		if (document.selection != undefined) {
			textarea.caretPos -= suffix.length;
		} else if (textarea.setSelectionRange != undefined) {
			const range = textarea.value.substring(0, start);
			textarea.value = range + subst + textarea.value.substring(end);

			if (selection != "") {
				textarea.setSelectionRange(
					start + subst.length,
					start + subst.length
				);
			} else {
				textarea.setSelectionRange(
					start + prefix.length,
					start + prefix.length
				);
			}

			textarea.scrollTop = scrollPos;
		}
	}
});