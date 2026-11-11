(format t "OK:~{~a~^|~}~%" (rest sb-ext:*posix-argv*))
(sb-ext:exit :code 3)
