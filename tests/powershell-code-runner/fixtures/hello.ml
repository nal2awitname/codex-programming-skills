let () =
  print_endline ("OK:" ^ String.concat "|" (List.tl (Array.to_list Sys.argv)));
  exit 3
