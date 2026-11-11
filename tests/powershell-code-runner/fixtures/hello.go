package main

import (
	"fmt"
	"os"
	"strings"
)

func main() {
	fmt.Println("OK:" + strings.Join(os.Args[1:], "|"))
	os.Exit(3)
}
