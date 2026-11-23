package main

import (
	"fmt"
	"net/http"
)

func main() {
	// just a simple https request to opencode.de
	resp, err := http.Get("https://opencode.de")
	if err != nil {
		panic(err)
	}
	defer resp.Body.Close()

	fmt.Println("Works!")
}
