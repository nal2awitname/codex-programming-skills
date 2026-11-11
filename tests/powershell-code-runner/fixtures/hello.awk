BEGIN {
    text = ""
    for (i = 1; i < ARGC; i++) text = text (i > 1 ? "|" : "") ARGV[i]
    print "OK:" text
    exit 3
}
