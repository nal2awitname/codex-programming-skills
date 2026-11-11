Dim text, i
text = ""
For i = 0 To WScript.Arguments.Count - 1
    If i > 0 Then text = text & "|"
    text = text & WScript.Arguments(i)
Next
WScript.Echo "OK:" & text
WScript.Quit 3
