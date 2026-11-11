program hello
  implicit none
  integer :: i
  character(len=256) :: value
  character(len=1024) :: line
  line = 'OK:'
  do i = 1, command_argument_count()
    call get_command_argument(i, value)
    if (i > 1) line = trim(line) // '|'
    line = trim(line) // trim(value)
  end do
  print '(a)', trim(line)
  call exit(3)
end program hello
