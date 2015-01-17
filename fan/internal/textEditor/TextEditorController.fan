using afIoc
using afReflux
using fwt

**
** TextEditorController manages user events on the text editor.
**
internal class TextEditorController : TextEditorSupport {
	@Inject private Reflux		reflux

	override TextEditor editor { private set }
	Int		caretLine
	Int		caretCol
	Bool	inUndo := false

	Str		actorGotoLast	:= "1"
	
	new make(TextEditor editor, |This|in) {
		in(this)
		this.editor = editor
	}

//////////////////////////////////////////////////////////////////////////
// Eventing
//////////////////////////////////////////////////////////////////////////

	Void register() {
		richText.onVerifyKey.add	{ onVerifyKey(it) }
		richText.onVerify.add		{ onVerify(it) }
		richText.onModify.add		{ onModified(it) }
		richText.onCaret.add		{ onCaret(it) }
		richText.onFocus.add		{ onFocus(it) }
	}

	Void onVerifyKey(Event event) {
		checkBlockIndent(event)
	}

	Void onVerify(Event event) {
		clearBraceMatch
		checkAutoIndent(event)
	}

	Void onModified(Event event) {
		pushUndo(event.data)
		editor.isDirty = true
	}

	Void onCaret(Event event) {
		updateCaretPos
		updateCaretStatus
		checkBraceMatch(event)
	}

	Void onFocus(Event event) {
		checkFileOutOfDate
	}

//////////////////////////////////////////////////////////////////////////
// Update Caret
//////////////////////////////////////////////////////////////////////////

	Void updateCaretPos() {
		offset := editor.richText.caretOffset
		this.caretLine = doc.lineAtOffset(offset)
		this.caretCol	= offset-doc.offsetAtLine(caretLine)
		doc.caretLine = this.caretLine
	}

	Void updateCaretStatus() {
		try {
			editor.caretField.text = "${(caretLine+1)}:${caretCol+1}"
			editor.caretField.parent?.relayout
		}
		catch (Err e) e.trace
	}

//////////////////////////////////////////////////////////////////////////
// Indenting
//////////////////////////////////////////////////////////////////////////

	internal Void checkAutoIndent(Event event) {
		// we only auto-indent on return/enter
		TextChange tc := event.data
		if (tc.newText != "\n") return

		// get the last previous line above the insert point
		lastNewLine := doc.line(tc.startLine+tc.newNumNewlines-1)

		// compute leading whitespace
		pos := 0
		while (pos < lastNewLine.size && lastNewLine[pos].isSpace) pos++
		if (pos == 0) return
		ws := lastNewLine[0..<pos]

		// insert leading whitespace into text to modify
		tc.newText += ws
	}

	Void checkBlockIndent(Event event) {
		// check if tab or shift+tab
		indent := event.key == blockIndentKey
		unindent := event.key == blockUnindentKey
		if (!indent && !unindent) return

		// we only block indent if multiple lines are selected, although
		// we don't really count the last line if the selection is at first col
		selStart	:= richText.selectStart
		selEnd		:= selStart + richText.selectSize
		startLine	:= doc.lineAtOffset(selStart)
		endLine		:= doc.lineAtOffset(selEnd)
		if (startLine == endLine) return
		if (selEnd == doc.offsetAtLine(endLine)) --endLine

		// consume this event to prevent further propagation
		event.consume

		// build a replacement string for lines
		s := StrBuf()
		ws := "\t"
		(startLine..endLine).each |Int i| {
		
			line := doc.line(i)
			if (indent) {
				// indent
				s.add(ws).add(line).addChar('\n')
			} else {
				// unindent
				if (line.startsWith(ws)) line = line[ws.size..-1]
				else line = line.trimStart
				s.add(line).addChar('\n')
			}
		}
		s.remove(-1) // last newline

		// replace the existing lines and re-select
		start := doc.offsetAtLine(startLine)
		end	 := doc.offsetAtLine(endLine) + doc.line(endLine).size
		doc.modify(start, end-start, s.toStr)
		richText.select(start, s.size)
	}

	private static const Key blockIndentKey := Key("Tab")
	private static const Key blockUnindentKey := Key("Shift+Tab")

//////////////////////////////////////////////////////////////////////////
// Undo
//////////////////////////////////////////////////////////////////////////

	Void pushUndo(TextChange change) {
		if (!inUndo)
			editor.addUndoRedo(
				|->| {   
					inUndo = true
					try		change.undo(richText)
					finally	inUndo = false
				}, 
				|->| {   
					inUndo = true
					try		change.redo(richText)
					finally	inUndo = false
				}
			)
	}

//////////////////////////////////////////////////////////////////////////
// Brace Matching
//////////////////////////////////////////////////////////////////////////

	Void clearBraceMatch() {
		if (doc.bracketLine1 == null) return
		oldLine1 := doc.bracketLine1
		oldLine2 := doc.bracketLine2
		doc.bracketLine1 = doc.bracketCol1 = null
		doc.bracketLine2 = doc.bracketCol2 = null
		richText.repaintLine(oldLine1)
		richText.repaintLine(oldLine2)
	}

	Void checkBraceMatch(Event event) {
		// clear old brace match
		clearBraceMatch

		// get character before caret
		offset := event.offset
		lineIndex := doc.lineAtOffset(offset)
		lineOffset := doc.offsetAtLine(lineIndex)
		col := offset-lineOffset-1
		if (lineOffset >= event.offset) return
		ch := doc.line(lineIndex)[col]
		if (!rules.brackets.containsChar(ch)) return

		// attempt to find match
		matchOffset := doc.matchBracket(offset-1)
		if (matchOffset == null) return
		matchLine := doc.lineAtOffset(matchOffset)

		// cache bracket locations doc and repaint
		matchCol := matchOffset-doc.offsetAtLine(matchLine)
		doc.setBracketMatch(lineIndex, col, matchLine, matchCol)
		richText.repaintLine(doc.bracketLine1)
		richText.repaintLine(doc.bracketLine2)
	}

//////////////////////////////////////////////////////////////////////////
// File Out-of-Date
//////////////////////////////////////////////////////////////////////////

	Void checkFileOutOfDate() {
		// on focus always check if the file has been modified
		// from out from under us and ask user if they want to reload
		if (editor.fileTimeAtLoad == editor.file.modified) return
		editor.fileTimeAtLoad = editor.file.modified

		// prompt user to reload
		r := Dialog.openQuestion(reflux.window,
			"File has been modified by another application:
			
			     $editor.file.name
			
			 Reload the file?", Dialog.yesNo)
		if (r == Dialog.yes) editor.refresh
	}

//////////////////////////////////////////////////////////////////////////
// Mark
//////////////////////////////////////////////////////////////////////////

//	Void onGotoMark(Mark mark)
//	{
//		if (mark.line == null) return
//		line := doc.lines[mark.line-1] // line num is one based
//		offset := line.offset
//		if (mark.col != null) offset += mark.col-1 // col num is one based
//		richText.focus
//		richText.select(offset, 0)
//		richText.caretOffset = offset
//	}

//////////////////////////////////////////////////////////////////////////
// Commands
//////////////////////////////////////////////////////////////////////////


	Void onGoto(Event event) {	
		r := Dialog.openPromptStr(reflux.window, "Goto Line:", actorGotoLast, 6)
		if (r == null) return

		line := r.toInt(10, false)
		if (line == null) return
		actorGotoLast = r

		line -= 1
		if (line >= doc.lineCount) line = doc.lineCount-1
		if (line < 0) line = 0
		richText.select(doc.offsetAtLine(line), 0)
		updateCaretStatus
	}
}